package com.system.calculator.chatdownloads

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageException
import org.json.JSONObject
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection

internal object ChatDownloadRuntime {
    private val gate = Any()
    private val foreground = Executors.newSingleThreadExecutor()
    fun <T> locked(action: () -> T): T = synchronized(gate) { action() }
    fun kick(context: Context) {
        foreground.execute {
            try {
                drain(context)
            } catch (error: Exception) {
                android.util.Log.e("ChatDownloads", "Download drain failed: ${error.javaClass.simpleName}")
            }
        }
    }

    private class Yield : Exception()
    private class Permanent(val explanation: String) : Exception()

    private fun check(store: ChatDownloadStore, id: String, uid: String, revision: Int): JSONObject {
        if (FirebaseAuth.getInstance().currentUser?.uid != uid) throw Yield()
        val job = store.get(id) ?: throw Yield()
        if (job.optInt("revision") != revision || !ChatDownloadPolicy.runnable(job.getString("state"))) throw Yield()
        return job
    }

    fun drain(context: Context, stopping: () -> Boolean = { false }): Boolean {
        if (FirebaseApp.getApps(context).isEmpty()) FirebaseApp.initializeApp(context)
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return true
        val network = context.getSystemService(ConnectivityManager::class.java)
        if (network.getNetworkCapabilities(network.activeNetwork)
                ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) != true
        ) return false
        val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(8)
        ChatDownloadStore(context).use { store ->
            RandomAccessFile(java.io.File(store.directory, "owner.lock"), "rw").use { owner ->
                val lock = try {
                    owner.channel.tryLock()
                } catch (_: java.nio.channels.OverlappingFileLockException) {
                    null
                }
                if (lock == null) return false
                lock.use {
                    locked { store.reconcile() }
                    var retry = false
                    for (record in locked { store.all() }) {
                        if (stopping() || System.nanoTime() >= deadline) return false
                        if (record.getString("uid") != uid || !ChatDownloadPolicy.runnable(record.getString("state"))) continue
                        if (record.optLong("eligibleAt") > System.currentTimeMillis()) {
                            retry = true; continue
                        }
                        val id = record.getString("id")
                        val revision = locked {
                            val job = store.get(id) ?: return@locked null
                            if (!ChatDownloadPolicy.runnable(job.getString("state"))) return@locked null
                            job.put("state", "uploading")
                            store.put(job)
                            job.optInt("revision")
                        } ?: continue
                        try {
                            transfer(store, id, uid, revision) { stopping() || System.nanoTime() >= deadline }
                        } catch (_: Yield) {
                            locked {
                                val job = store.get(id)
                                if (job != null && job.optInt("revision") == revision &&
                                    ChatDownloadPolicy.runnable(job.getString("state"))
                                ) {
                                    job.put("state", "queued")
                                    store.put(job)
                                    retry = true
                                } else if (job != null && ChatDownloadPolicy.runnable(job.getString("state"))) {
                                    retry = true
                                }
                            }
                        } catch (error: Exception) {
                            locked {
                                val job = store.get(id) ?: return@locked
                                if (job.optInt("revision") != revision) {
                                    if (ChatDownloadPolicy.runnable(job.getString("state"))) retry = true
                                    return@locked
                                }
                                val cause = error.cause ?: error
                                val permanentMessage = when {
                                    error is Permanent -> error.explanation
                                    cause is StorageException && cause.errorCode == StorageException.ERROR_OBJECT_NOT_FOUND ->
                                        "Attachment no longer exists. Ask the sender to reattach it."

                                    cause is StorageException && cause.errorCode == StorageException.ERROR_NOT_AUTHORIZED ->
                                        "Attachment access was denied. Sign in again or contact the sender."

                                    cause is StorageException && cause.errorCode == StorageException.ERROR_QUOTA_EXCEEDED ->
                                        "Storage quota exceeded. Retry after the quota is available."

                                    error is IllegalArgumentException -> "Invalid attachment or remote size."
                                    error is IllegalStateException -> "Device download storage unavailable or full. Free space and retry."
                                    cause is android.system.ErrnoException &&
                                            cause.errno == android.system.OsConstants.ENOSPC ->
                                        "Device storage is full. Free space and retry the saved download."

                                    else -> null
                                }
                                val attempts = job.optInt("attempts") + 1
                                val terminal = permanentMessage != null || attempts >= 8
                                job.put("attempts", attempts).put("state", if (terminal) "failed" else "retrying")
                                    .put(
                                        "error",
                                        permanentMessage ?: "Network interrupted; saved encrypted progress will resume."
                                    )
                                    .put(
                                        "eligibleAt", System.currentTimeMillis() +
                                                (5_000L shl attempts.coerceAtMost(7)).coerceAtMost(600_000)
                                    )
                                    .put("updatedAt", System.currentTimeMillis())
                                store.put(job)
                                if (!terminal) retry = true
                            }
                        }
                    }
                    return !retry
                }
            }
        }
    }

    private fun transfer(
        store: ChatDownloadStore, id: String, uid: String,
        revision: Int, stopping: () -> Boolean
    ) {
        var job = locked { check(store, id, uid, revision) }
        if (job.optString("senderId").isEmpty()) {
            // Older journals did not distinguish sent from received objects.
            // Classify the message before acquiring any attachment bytes.
            val parts = job.getString("storagePath").split('/')
            if (parts.size != 4) throw Permanent("Attachment identity is unsupported.")
            val message = Tasks.await(
                FirebaseFirestore.getInstance(FirebaseApp.getInstance(), "default1")
                    .collection("threads").document(job.getString("threadId"))
                    .collection("messages").document(parts[2]).get(),
                30, TimeUnit.SECONDS
            )
            val sender = message.getString("senderId") ?: ""
            if (sender == uid) {
                locked {
                    val current = check(store, id, uid, revision)
                    store.deleteBlob(id)
                    current.put("state", "cancelled").put("processedBytes", 0L)
                        .put("revision", revision + 1)
                        .put("error", "Sent attachments open from the original source or encrypted local sent copy.")
                    store.put(current)
                }
                return
            }
            if (!message.exists() || message.getBoolean("deletedForEveryone") == true ||
                (message.get("deletedFor") as? List<*>)?.contains(uid) == true ||
                !ChatDownloadPolicy.receivedSender(uid, sender, job.getString("threadId"))
            ) {
                throw Permanent("The received attachment message is unavailable.")
            }
            val thumb = (message.get("mediaMeta") as? Map<*, *>)?.get("thumbRef")
            if (message.getString("mediaRef") != job.getString("storagePath") &&
                thumb != job.getString("storagePath")
            ) {
                throw Permanent("Attachment does not belong to this message.")
            }
            locked {
                job = check(store, id, uid, revision)
                job.put("senderId", sender)
                store.put(job)
            }
        }
        if (!ChatDownloadPolicy.receivedSender(uid, job.getString("senderId"), job.getString("threadId"))) {
            throw Permanent("Sent attachments are never downloaded from the server.")
        }
        val ref = FirebaseStorage.getInstance().getReference(job.getString("storagePath"))
        val metadata = Tasks.await(ref.metadata, 30, TimeUnit.SECONDS)
        val total = metadata.sizeBytes
        if (total !in 29..ChatDownloadPolicy.MAX_BYTES) throw Permanent("Attachment is empty or exceeds the 64 MB limit.")
        val generation = metadata.generation ?: throw IOException("Object version unavailable")
        locked {
            job = check(store, id, uid, revision)
            store.reserve(total, id)
            if (job.optString("generation").isNotEmpty() && job.getString("generation") != generation) {
                store.deleteBlob(id)
                job.put("processedBytes", 0L).remove("etag")
                job.put("error", "Remote attachment changed; restarting the encrypted download.")
            }
            job.put("generation", generation).put("totalBytes", total)
            store.put(job)
        }
        // The URL is a short-lived in-memory capability, never journaled or logged.
        val uri = Tasks.await(ref.downloadUrl, 30, TimeUnit.SECONDS)
        val url = URL(uri.toString())
        if (url.protocol != "https" || url.host !in setOf("firebasestorage.googleapis.com", "storage.googleapis.com")) {
            throw Permanent("Unsupported attachment download endpoint.")
        }
        while (true) {
            if (stopping()) throw Yield()
            job = locked { check(store, id, uid, revision) }
            val offset = ChatDownloadPolicy.recoveredOffset(
                job.optLong("processedBytes"),
                store.blob(id).length(), total
            )
            if (offset == total) break
            val connection = url.openConnection() as HttpsURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.setRequestProperty("Range", "bytes=$offset-")
            val etag = job.optString("etag")
            if (etag.isNotEmpty()) connection.setRequestProperty("If-Match", etag)
            try {
                val code = connection.responseCode
                if (code == HttpURLConnection.HTTP_NOT_FOUND) throw Permanent("Attachment no longer exists. Ask the sender to reattach it.")
                if (code in listOf(401, 403)) throw Permanent("Attachment download permission was denied.")
                if (code == 412) {
                    locked {
                        val current = check(store, id, uid, revision)
                        store.deleteBlob(id)
                        current.put("processedBytes", 0L).remove("generation")
                        current.remove("etag")
                        current.put("error", "Remote attachment changed; download must restart.")
                        store.put(current)
                    }
                    throw IOException("Object changed during download")
                }
                if (code == 416) {
                    val header = connection.getHeaderField("Content-Range")
                    if (header == "bytes */$total" && offset == total) break
                    locked {
                        val current = check(store, id, uid, revision)
                        store.deleteBlob(id)
                        current.put("processedBytes", 0L)
                            .put("error", "Server rejected saved progress; restarting the encrypted download.")
                        store.put(current)
                    }
                    throw IOException("Server rejected the saved download offset")
                }
                val response = ChatDownloadPolicy.response(
                    code,
                    connection.getHeaderField("Content-Range"), offset, total, connection.contentLengthLong
                )
                val start = response.start
                val expected = response.bytes
                val responseTag = connection.getHeaderField("ETag")
                if (etag.isNotEmpty() && responseTag != null && responseTag != etag) {
                    locked {
                        val current = check(store, id, uid, revision)
                        store.deleteBlob(id)
                        current.put("processedBytes", 0L).remove("generation")
                        current.remove("etag")
                        store.put(current)
                    }
                    throw IOException("Remote object identity changed")
                }
                locked {
                    val current = check(store, id, uid, revision)
                    if (code == 200 && offset > 0) {
                        current.put("processedBytes", 0L)
                        current.put("error", "Server did not support range resume; restarting encrypted download.")
                    }
                    if (!responseTag.isNullOrEmpty()) current.put("etag", responseTag)
                    store.put(current)
                }
                val destination = locked {
                    check(store, id, uid, revision)
                    RandomAccessFile(store.blob(id), "rw").apply {
                        try {
                            setLength(start)
                            seek(start)
                        } catch (error: Exception) {
                            close()
                            throw error
                        }
                    }
                }
                destination.use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var received = 0L
                    var durableAt = start
                    var lastFlush = System.nanoTime()
                    try {
                        connection.inputStream.use { input ->
                            while (received < expected) {
                                if (stopping()) throw Yield()
                                locked { check(store, id, uid, revision) }
                                val count =
                                    input.read(buffer, 0, minOf(buffer.size.toLong(), expected - received).toInt())
                                if (count < 0) throw IOException("Attachment download was truncated")
                                if (count == 0) continue
                                // Serialize the file mutation with cancel/delete.
                                locked {
                                    check(store, id, uid, revision)
                                    output.write(buffer, 0, count)
                                }
                                received += count
                                val position = start + received
                                if (position - durableAt >= 256 * 1024 || System.nanoTime() - lastFlush >= 500_000_000) {
                                    checkpoint(store, id, uid, revision, output, position)
                                    durableAt = position
                                    lastFlush = System.nanoTime()
                                }
                            }
                            if (input.read() != -1) throw IOException("Attachment exceeded its declared length")
                        }
                        checkpoint(store, id, uid, revision, output, start + received)
                    } finally {
                        buffer.fill(0)
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
        val finalVersion = Tasks.await(ref.metadata, 30, TimeUnit.SECONDS)
        if (finalVersion.generation != generation || finalVersion.sizeBytes != total) {
            locked {
                val current = check(store, id, uid, revision)
                store.deleteBlob(id)
                current.put("processedBytes", 0L).remove("generation")
                current.remove("etag")
                store.put(current)
            }
            throw IOException("Attachment changed before authentication")
        }
        val sha = java.security.MessageDigest.getInstance("SHA-256")
        val md5 = java.security.MessageDigest.getInstance("MD5")
        store.blob(id).inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            try {
                while (true) {
                    if (stopping()) throw Yield()
                    locked { check(store, id, uid, revision) }
                    val count = input.read(buffer)
                    if (count < 0) break
                    sha.update(buffer, 0, count)
                    md5.update(buffer, 0, count)
                }
            } finally {
                buffer.fill(0)
            }
        }
        val actualSha = sha.digest().joinToString("") { "%02x".format(it) }
        val actualMd5 = android.util.Base64.encodeToString(md5.digest(), android.util.Base64.NO_WRAP)
        if (!ChatDownloadPolicy.checksumsMatch(
                finalVersion.getCustomMetadata("sha256"),
                actualSha, finalVersion.md5Hash, actualMd5
            )
        ) {
            locked {
                val current = check(store, id, uid, revision)
                store.deleteBlob(id)
                current.put("processedBytes", 0L)
                store.put(current)
            }
            throw Permanent("Downloaded encrypted bytes failed integrity checks. Retry to restart safely.")
        }
        locked {
            val current = check(store, id, uid, revision)
            current.put("state", "completed").put("processedBytes", total)
                .put("updatedAt", System.currentTimeMillis())
            store.put(current)
        }
    }

    private fun checkpoint(
        store: ChatDownloadStore, id: String, uid: String,
        revision: Int, output: RandomAccessFile, position: Long
    ) = locked {
        val current = check(store, id, uid, revision)
        output.fd.sync()
        current.put("processedBytes", position).put("updatedAt", System.currentTimeMillis())
        store.put(current)
    }
}
