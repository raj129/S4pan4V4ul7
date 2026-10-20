package com.system.calculator

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.work.ForegroundInfo
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.OnProgressListener
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import com.google.firebase.storage.UploadTask
import org.json.JSONObject
import java.io.RandomAccessFile
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** UI actions and journal updates share a lock; service/worker ownership uses
 * a file lock so process death releases it without stale leases. */
object ChatUploadRuntime {
    private val gate = Any()
    private val running = mutableMapOf<String, UploadTask>()
    fun <T> locked(action: () -> T): T = synchronized(gate) { action() }
    fun interrupt(id: String, destructive: Boolean = false) {
        running[id]?.let { if (destructive) it.cancel() else it.pause() }
    }

    fun drain(context: Context, shouldStop: () -> Boolean = { false },
        progress: (JSONObject) -> Unit = {}): Boolean {
        val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(8)
        val stopped = { shouldStop() || System.nanoTime() >= deadline }
        ChatUploadStore(context).use { store ->
            RandomAccessFile(java.io.File(store.directory, "owner.lock"), "rw").use { owner ->
                val claim = try { owner.channel.tryLock() } catch (_: java.nio.channels.OverlappingFileLockException) { null }
                if (claim == null) return false
                claim.use {
                    locked { store.reconcile() }
                    val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return true
                    val connectivity = context.getSystemService(android.net.ConnectivityManager::class.java)
                    val network = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                    if (network?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) != true) {
                        return false
                    }
                    var retry = false
                    for (record in store.all()) {
                        if (stopped()) return false
                        val id = record.getString("messageId")
                        val state = record.getString("state")
                        if (record.getString("senderId") != uid ||
                            !ChatUploadPolicy.runnable(state)) continue
                        if (record.optLong("eligibleAt") > System.currentTimeMillis()) { retry = true; continue }
                        val revision = locked {
                            val job = store.get(id)!!
                            if (!ChatUploadPolicy.runnable(job.getString("state")) ||
                                FirebaseAuth.getInstance().currentUser?.uid != uid) return@locked null
                            job.put("state", "uploading").put("error", "").put("delivering", false)
                            store.put(job)
                            job.optInt("revision")
                        } ?: continue
                        try {
                            if (record.optBoolean("hasThumb")) upload(context, store, id, uid, revision, true, stopped, progress)
                            upload(context, store, id, uid, revision, false, stopped, progress)
                            locked {
                                val job = checkJob(store, id, uid, revision)
                                job.put("delivering", true)
                                store.put(job)
                            }
                            val job = store.get(id)!!
                            deliver(job, uid)
                            locked {
                                val complete = store.get(id)!!
                                complete.put("state", "completed").put("delivering", false)
                                    .put("processedBytes", complete.getLong("totalBytes"))
                                store.put(complete)
                                progress(complete)
                            }
                            store.blob(id).delete(); store.blob(id, true).delete()
                        } catch (error: Exception) {
                            locked {
                                val job = store.get(id)!!
                                if (job.optInt("revision") != revision) {
                                    if (ChatUploadPolicy.runnable(job.getString("state"))) retry = true
                                    return@locked
                                }
                                if (stopped() || FirebaseAuth.getInstance().currentUser?.uid != uid) {
                                    job.put("state", "queued").put("delivering", false)
                                    store.put(job)
                                    retry = true
                                    return@locked
                                }
                                val attempts = job.optInt("attempts") + 1
                                val cause = error.cause ?: error
                                val permanent = cause is IllegalArgumentException ||
                                    (cause is StorageException && cause.errorCode in listOf(
                                        StorageException.ERROR_NOT_AUTHORIZED, StorageException.ERROR_QUOTA_EXCEEDED))
                                job.put("attempts", attempts).put("delivering", false)
                                    .put("state", if (permanent || attempts >= 8) "failed" else "retrying")
                                    .put("error", if (permanent) "Permission, quota, or content failure" else "Transfer interrupted; retry pending")
                                    .put("eligibleAt", System.currentTimeMillis() +
                                        ((30_000L shl attempts.coerceAtMost(8)).coerceAtMost(3_600_000L)) +
                                        java.security.SecureRandom().nextInt(10_000))
                                store.put(job)
                                progress(job)
                                if (!permanent && attempts < 8) retry = true
                            }
                        } finally {
                            locked {
                                running[id]?.let { if (it.isComplete || it.isPaused) running.remove(id) }
                            }
                        }
                    }
                    return !retry
                }
            }
        }
    }
    private fun checkJob(store: ChatUploadStore, id: String, uid: String, revision: Int): JSONObject {
        check(FirebaseAuth.getInstance().currentUser?.uid == uid) { "Account changed" }
        val job = store.get(id) ?: throw IllegalStateException("Upload missing")
        check(job.optInt("revision") == revision && ChatUploadPolicy.runnable(job.getString("state")))
        return job
    }
    private fun upload(context: Context, store: ChatUploadStore, id: String, uid: String,
        revision: Int, thumb: Boolean, shouldStop: () -> Boolean, progress: (JSONObject) -> Unit,
        allowFreshSession: Boolean = true) {
        val field = if (thumb) "thumbRef" else "mediaRef"
        var job = locked { checkJob(store, id, uid, revision) }
        if (job.optString(field).isNotEmpty()) {
            try {
                val metadata = Tasks.await(
                    FirebaseStorage.getInstance().getReference(job.getString(field)).metadata,
                    30, TimeUnit.SECONDS)
                if (!job.optBoolean("legacyFinalized")) {
                    require(metadata.getCustomMetadata("sha256") ==
                        job.getString(if (thumb) "thumbDigest" else "digest")) {
                        "Completed attachment identity mismatch"
                    }
                }
                return
            } catch (error: Exception) {
                val cause = error.cause ?: error
                if (cause !is StorageException ||
                    cause.errorCode != StorageException.ERROR_OBJECT_NOT_FOUND) throw error
                require(!job.optBoolean("legacyFinalized")) {
                    "Older remote attachment is missing; reattach the original file"
                }
                job = locked {
                    val current = checkJob(store, id, uid, revision)
                    current.remove(field)
                    current.remove(if (thumb) "thumbSession" else "mediaSession")
                    store.put(current)
                    current
                }
            }
        }
        val file = store.blob(id, thumb)
        require(file.exists()) { "Encrypted staging file unavailable; reattach the file" }
        val path = "chat_media/${job.getString("threadId")}/$id/${if (thumb) "thumb" else "media"}.enc"
        val ref = FirebaseStorage.getInstance().getReference(path)
        val digest = job.getString(if (thumb) "thumbDigest" else "digest")
        val startedKey = if (thumb) "thumbStarted" else "mediaStarted"
        val actualDigest = java.security.MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                actualDigest.update(buffer, 0, count)
            }
        }
        require(actualDigest.digest().joinToString("") { "%02x".format(it) } == digest) {
            "Encrypted staging file is corrupted; reattach the file"
        }
        // Reconcile a successful remote finalize whose local checkpoint was lost.
        if (job.optString(if (thumb) "thumbSession" else "mediaSession").isEmpty() &&
            (job.optBoolean(startedKey) || job.optInt("attempts") > 0)) try {
            val meta = Tasks.await(ref.metadata, 30, TimeUnit.SECONDS)
            if (meta.getCustomMetadata("sha256") == digest && meta.sizeBytes == file.length()) {
                checkpoint(store, id, uid, revision, field, path)
                return
            }
            throw IllegalArgumentException("Remote attachment identity mismatch")
        } catch (error: Exception) {
            val cause = error.cause ?: error
            if (cause !is StorageException || cause.errorCode != StorageException.ERROR_OBJECT_NOT_FOUND) throw error
        }
        val sessionKey = if (thumb) "thumbSession" else "mediaSession"
        val metadata = StorageMetadata.Builder().setContentType("application/octet-stream")
            .setCustomMetadata("sha256", digest).build()
        val session = job.optString(sessionKey)
        val task = locked {
            // Pause/cancel may arrive while metadata reconciliation is waiting.
            // Register ownership atomically with the last revision check.
            val current = checkJob(store, id, uid, revision)
            running[id]?.let { check(it.isComplete || it.isPaused) { "Previous upload is still pausing" } }
            current.put(startedKey, true)
            store.put(current)
            val transfer = if (session.isEmpty()) ref.putFile(Uri.fromFile(file), metadata)
                else ref.putFile(Uri.fromFile(file), metadata, Uri.parse(session))
            running[id] = transfer
            transfer
        }
        val listener = OnProgressListener<UploadTask.TaskSnapshot> { snapshot ->
            locked {
                try {
                    val current = checkJob(store, id, uid, revision)
                    if (shouldStop()) { task.pause(); return@locked }
                    snapshot.uploadSessionUri?.let { current.put(sessionKey, it.toString()) }
                    val prefix = if (thumb) 0 else if (current.optBoolean("hasThumb")) store.blob(id, true).length() else 0
                    // A reattached SDK task initially reports zero before its
                    // server-offset query. Keep the last confirmed checkpoint.
                    current.put("processedBytes", ChatUploadPolicy.confirmedProgress(
                        current.optLong("processedBytes"), prefix + snapshot.bytesTransferred,
                        session.isNotEmpty() && snapshot.uploadSessionUri?.toString() == session))
                    store.put(current)
                    progress(current)
                } catch (_: IllegalStateException) {
                    if (store.get(id)?.optString("state") == "cancelled") task.cancel()
                    else task.pause()
                }
            }
        }
        task.addOnProgressListener(listener)
        try {
            while (!task.isComplete) {
                if (shouldStop()) throw java.util.concurrent.TimeoutException("Upload execution budget exhausted")
                locked { checkJob(store, id, uid, revision) }
                try { Tasks.await(task, 5, TimeUnit.SECONDS) }
                catch (_: java.util.concurrent.TimeoutException) { /* Recheck cancellation and execution budget. */ }
            }
            Tasks.await(task)
        } catch (error: Exception) {
            // Pausing must not send Firebase's destructive session-cancel
            // request. Let the in-flight request settle before another owner
            // reattaches to the saved session.
            if (locked { store.get(id)?.optString("state") == "cancelled" }) task.cancel()
            else if (!task.isComplete) task.pause()
            val pauseDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(35)
            while (!task.isComplete && !task.isPaused && System.nanoTime() < pauseDeadline) {
                Thread.sleep(25)
            }
            check(task.isComplete || task.isPaused) { "Upload pause is still settling; retry later" }
            locked {
                val current = store.get(id)!!
                val cause = error.cause ?: error
                task.snapshot.uploadSessionUri?.let {
                    if (current.optString("state") != "cancelled") current.put(sessionKey, it.toString())
                }
                val invalidSession = cause is StorageException &&
                    cause.httpResultCode in listOf(404, 410)
                if (invalidSession) {
                    current.remove(sessionKey)
                    current.put("processedBytes", if (!thumb && current.optBoolean("hasThumb")) store.blob(id, true).length() else 0L)
                    current.put("error", "Upload session expired; restarting this encrypted object")
                }
                store.put(current)
            }
            val cause = error.cause ?: error
            // A crash after remote finalize but before the journal checkpoint
            // makes a saved session report "final", not an expired-session 404.
            if (session.isNotEmpty() && cause is StorageException &&
                cause.httpResultCode == 200 && !shouldStop()) {
                locked { checkJob(store, id, uid, revision) }
                try {
                    val completed = Tasks.await(ref.metadata, 30, TimeUnit.SECONDS)
                    require(completed.sizeBytes == file.length() &&
                        completed.getCustomMetadata("sha256") == digest) {
                        "Completed attachment identity mismatch"
                    }
                    checkpoint(store, id, uid, revision, field, path)
                    return
                } catch (reconciliationError: Exception) {
                    val reconciliationCause = reconciliationError.cause ?: reconciliationError
                    if (reconciliationCause !is StorageException ||
                        reconciliationCause.errorCode != StorageException.ERROR_OBJECT_NOT_FOUND) {
                        throw reconciliationError
                    }
                    locked {
                        val current = checkJob(store, id, uid, revision)
                        current.remove(sessionKey)
                        store.put(current)
                    }
                    if (allowFreshSession) {
                        upload(context, store, id, uid, revision, thumb, shouldStop, progress, false)
                        return
                    }
                }
            }
            if (allowFreshSession && !shouldStop() && cause is StorageException &&
                ChatUploadPolicy.restartExpiredSession(session.isNotEmpty(), cause.httpResultCode)) {
                locked { checkJob(store, id, uid, revision) }
                upload(context, store, id, uid, revision, thumb, shouldStop, progress, false)
                return
            }
            throw error
        } finally {
            task.removeOnProgressListener(listener)
        }
        checkpoint(store, id, uid, revision, field, path)
    }
    private fun checkpoint(store: ChatUploadStore, id: String, uid: String,
        revision: Int, field: String, path: String) = locked {
        val current = checkJob(store, id, uid, revision)
        current.put(field, path)
        if (field == "thumbRef") current.getJSONObject("mediaMeta").put("thumbRef", path)
        store.put(current)
    }
    private fun deliver(job: JSONObject, uid: String) {
        val db = FirebaseFirestore.getInstance(FirebaseApp.getInstance(), "default1")
        val thread = db.collection("threads").document(job.getString("threadId"))
        val message = thread.collection("messages").document(job.getString("messageId"))
        Tasks.await(db.runTransaction { tx ->
            check(FirebaseAuth.getInstance().currentUser?.uid == uid)
            val existing = tx.get(message)
            if (existing.exists()) {
                require(existing.getString("senderId") == uid &&
                    (existing.getString("uploadDigest") == job.getString("digest") ||
                        (job.optBoolean("legacyFinalized") &&
                            (existing.getString("mediaRef") == job.getString("mediaRef") ||
                                existing.getBoolean("deletedForEveryone") == true)))) { "Message identity mismatch" }
            } else {
                val parent = tx.get(thread)
                require((parent.get("participantIds") as? List<*>)?.contains(uid) == true)
                val payload = mapOf(
                    "messageId" to job.getString("messageId"), "threadId" to job.getString("threadId"),
                    "senderId" to uid, "encryptedText" to job.getString("encryptedText"),
                    "sentAt" to job.getLong("sentAt"), "mediaRef" to job.getString("mediaRef"),
                    "mediaType" to job.getString("mediaType"),
                    "isForwarded" to job.optBoolean("isForwarded"),
                    "uploadDigest" to job.getString("digest"),
                    "mediaMeta" to ChatUploadPlugin.jsonMap(job.getJSONObject("mediaMeta")),
                    "deletedFor" to emptyList<String>(), "readBy" to emptyList<String>(),
                    "deliveredTo" to emptyList<String>(), "deletedForEveryone" to false,
                    "reactions" to emptyMap<String, String>())
                tx.set(message, payload)
                val updates = mutableMapOf<String, Any>("unreadCounts.${job.getString("recipientUid")}" to FieldValue.increment(1))
                if ((parent.getLong("lastMessageAt") ?: 0L) <= job.getLong("sentAt")) {
                    updates["lastMessage"] = ""
                    updates["lastMessageAt"] = job.getLong("sentAt")
                }
                tx.update(thread, updates)
            }
            null
        }, 60, TimeUnit.SECONDS)
    }
}

class ChatUploadWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        FirebaseApp.initializeApp(applicationContext)
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        val pending = ChatUploadRuntime.locked {
            ChatUploadStore(applicationContext).use { store ->
                store.all().any { it.getString("senderId") == uid && ChatUploadPolicy.runnable(it.getString("state")) }
            }
        }
        if (pending) {
            val notification = ChatUploadNotifications.build(applicationContext, "Uploading encrypted attachments")
            val info = if (Build.VERSION.SDK_INT >= 29)
                ForegroundInfo(4727, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                else ForegroundInfo(4727, notification)
            setForegroundAsync(info).get(15, TimeUnit.SECONDS)
        }
        if (ChatUploadRuntime.drain(applicationContext, { isStopped }) { job ->
            applicationContext.getSystemService(NotificationManager::class.java).notify(4727,
                ChatUploadNotifications.build(applicationContext,
                    "${job.optLong("processedBytes")} / ${job.optLong("totalBytes")} bytes", job.getString("messageId")))
        }) Result.success() else Result.retry()
    } catch (error: Exception) {
        android.util.Log.e("ChatUploads", "Encrypted upload journal unavailable: ${error.javaClass.simpleName}")
        if (runAttemptCount < 8) Result.retry() else Result.failure()
    }
}

class ChatUploadService : Service() {
    private val io = Executors.newSingleThreadExecutor()
    @Volatile private var stopping = false
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.getStringExtra("action")
        val id = intent?.getStringExtra("messageId")
        if (action != null && id != null) {
            ChatUploadRuntime.locked {
                ChatUploadStore(this).use { store ->
                    val job = store.get(id)
                    if (job != null && job.getString("senderId") == FirebaseAuth.getInstance().currentUser?.uid) {
                        val next = ChatUploadPolicy.transition(job.getString("state"), action, job.optBoolean("delivering"))
                        if (next == job.getString("state")) return@use
                        job.put("state", next)
                            .put("revision", job.optInt("revision") + 1)
                        store.put(job)
                        ChatUploadRuntime.interrupt(id, next == "cancelled")
                        if (next == "cancelled") store.reconcile()
                    }
                }
            }
        }
        val notification = ChatUploadNotifications.build(this, "Uploading encrypted attachments")
        if (Build.VERSION.SDK_INT >= 29) startForeground(4726, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(4726, notification)
        io.execute {
            try { ChatUploadRuntime.drain(this, { stopping }) { job ->
                getSystemService(NotificationManager::class.java).notify(4726,
                    ChatUploadNotifications.build(this, "${job.optLong("processedBytes")} / ${job.optLong("totalBytes")} bytes",
                        job.getString("messageId")))
            } } catch (error: Exception) {
                android.util.Log.e("ChatUploads", "Encrypted upload service interrupted: ${error.javaClass.simpleName}")
            } finally {
                ChatUploadPlugin.schedule(this)
                stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopping = true; stopSelf(startId) }
    override fun onDestroy() { stopping = true; io.shutdown(); super.onDestroy() }
}

object ChatUploadNotifications {
    fun build(context: Context, text: String, id: String? = null): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel("chat_uploads", "Encrypted attachment uploads", NotificationManager.IMPORTANCE_LOW))
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, "chat_uploads") else Notification.Builder(context)
        builder.setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("Calculator").setContentText(text).setOngoing(true)
        if (id != null) {
            for ((index, action) in listOf("pause", "cancel").withIndex()) {
                val intent = Intent(context, ChatUploadService::class.java)
                    .putExtra("action", action).putExtra("messageId", id)
                    .setData(Uri.parse("chat-upload://$id/$action"))
                val pending = PendingIntent.getService(context, index, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                builder.addAction(Notification.Action.Builder(null,
                    if (action == "pause") "Pause" else "Cancel", pending).build())
            }
        }
        return builder.build()
    }
}
