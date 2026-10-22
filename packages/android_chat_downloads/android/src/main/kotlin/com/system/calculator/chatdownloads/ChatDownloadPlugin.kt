package com.system.calculator.chatdownloads

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.firebase.auth.FirebaseAuth
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** A real Flutter plugin so WorkManager's headless engines use the same channel. */
class ChatDownloadPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var localMediaChannel: MethodChannel
    private lateinit var localMediaHandler: ChatLocalMediaChannel
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "photo_vault/chat_downloads")
        channel.setMethodCallHandler(this)
        localMediaHandler = ChatLocalMediaChannel(context)
        localMediaChannel = MethodChannel(binding.binaryMessenger, "photo_vault/chat_local_media")
        localMediaChannel.setMethodCallHandler(localMediaHandler)
        schedule(context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        localMediaChannel.setMethodCallHandler(null)
        localMediaHandler.close()
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        io.execute {
            var response: Any? = null
            try {
                response = ChatDownloadRuntime.locked {
                    val uid = FirebaseAuth.getInstance().currentUser?.uid
                        ?: throw SecurityException("Chat sign-in required")
                    if (call.method !in listOf("list", "wake")) {
                        require(call.argument<String>("uid") == uid) { "Download account changed" }
                    }
                    ChatDownloadStore(context).use { store ->
                        if (call.method == "list") return@use store.all()
                            .filter { it.getString("uid") == uid }.map { publicJob(it) }
                        if (call.method == "wake") return@use null
                        val path = call.argument<String>("storagePath") ?: throw IllegalArgumentException()
                        val segments = ChatLocalMediaPolicy.attachmentPath(uid, path)
                        val id = store.id(uid, path)
                        if (call.method == "enqueue") store.pruneAcknowledged()
                        val job = store.get(id)
                        when (call.method) {
                            "enqueue" -> {
                                require(call.argument<String>("threadId") == segments[1])
                                val senderId = call.argument<String>("senderId")
                                if (senderId != null) {
                                    require(ChatDownloadPolicy.receivedSender(uid, senderId, segments[1])) {
                                        "Invalid received attachment sender"
                                    }
                                }
                                if (job == null) {
                                    require(store.all().size < 128) { "Download queue full" }
                                    store.put(
                                        JSONObject().put("id", id).put("uid", uid)
                                            .put("threadId", segments[1]).put("storagePath", path)
                                            .put("state", "queued").put("processedBytes", 0L).put("totalBytes", 0L)
                                            .put("revision", 0).put("createdAt", System.currentTimeMillis())
                                            .put("updatedAt", System.currentTimeMillis()).apply {
                                                if (senderId != null) put("senderId", senderId)
                                            })
                                }
                                null
                            }

                            "read" -> {
                                require(job != null && job.getString("state") == "completed")
                                val file = store.blob(id)
                                require(file.length() == job.getLong("totalBytes") && file.length() in 29..ChatDownloadPolicy.MAX_BYTES)
                                file.readBytes()
                            }

                            "acknowledge" -> {
                                if (job != null) {
                                    require(job.getString("state") == "completed")
                                    // A short bounded grace period allows another engine's
                                    // already-waiting authenticated acquisition to read.
                                    job.put("acknowledgedAt", System.currentTimeMillis())
                                    store.put(job)
                                }
                                null
                            }

                            "pause", "resume", "retry", "cancel" -> {
                                if (job == null && call.method == "cancel") return@use null
                                require(job != null) { "Download no longer exists" }
                                val next = ChatDownloadPolicy.transition(job.getString("state"), call.method)
                                if (next != job.getString("state")) {
                                    job.put("state", next).put("revision", job.optInt("revision") + 1)
                                        .put("eligibleAt", 0L).put("updatedAt", System.currentTimeMillis())
                                    if (call.method == "retry") job.put("attempts", 0).put("error", "")
                                    job.remove("acknowledgedAt")
                                    if (next == "cancelled") {
                                        store.deleteBlob(id)
                                        job.put("processedBytes", 0L).put("totalBytes", 0L)
                                        job.remove("generation")
                                        job.remove("etag")
                                    }
                                    store.put(job)
                                }
                                null
                            }

                            else -> throw IllegalArgumentException("Unknown download action")
                        }
                    }
                }
                if (call.method == "acknowledge") scheduleCleanup(context)
                if (call.method in listOf("enqueue", "wake", "resume", "retry")) {
                    schedule(context)
                    ChatDownloadRuntime.kick(context)
                }
                val value = response
                main.post {
                    try {
                        result.success(value)
                    } finally {
                        (value as? ByteArray)?.fill(0)
                    }
                }
            } catch (error: Exception) {
                (response as? ByteArray)?.fill(0)
                main.post {
                    result.error(
                        if (error is SecurityException) "unauthorized" else "download_unavailable",
                        "Encrypted download action failed. Check sign-in, attachment availability and device storage.",
                        null
                    )
                }
            }
        }
    }

    private fun publicJob(job: JSONObject): Map<String, Any> = mapOf(
        "uid" to job.getString("uid"), "threadId" to job.getString("threadId"),
        "storagePath" to job.getString("storagePath"), "state" to job.getString("state"),
        "processedBytes" to job.optLong("processedBytes"), "totalBytes" to job.optLong("totalBytes"),
        "error" to job.optString("error")
    )

    companion object {
        fun scheduleCleanup(
            context: Context, delayMillis: Long = 125_000L,
            policy: ExistingWorkPolicy = ExistingWorkPolicy.KEEP
        ) {
            val request = OneTimeWorkRequestBuilder<ChatDownloadCleanupWorker>()
                .setInitialDelay(delayMillis.coerceAtLeast(1_000L), TimeUnit.MILLISECONDS).build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "chat_encrypted_download_cleanup", policy, request
            )
        }

        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<ChatDownloadWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS).build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "chat_encrypted_downloads", ExistingWorkPolicy.APPEND_OR_REPLACE, request
            )
        }
    }
}

class ChatDownloadCleanupWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        val next = ChatDownloadRuntime.locked {
            ChatDownloadStore(applicationContext).use { it.pruneAcknowledged() }
        }
        if (next != null) ChatDownloadPlugin.scheduleCleanup(
            applicationContext, next, ExistingWorkPolicy.APPEND_OR_REPLACE
        )
        Result.success()
    } catch (error: Exception) {
        android.util.Log.e("ChatDownloads", "Download cleanup failed: ${error.javaClass.simpleName}")
        if (runAttemptCount < 8) Result.retry() else Result.failure()
    }
}

class ChatDownloadWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        if (ChatDownloadRuntime.drain(applicationContext) { isStopped }) Result.success() else Result.retry()
    } catch (error: Exception) {
        android.util.Log.e("ChatDownloads", "Download recovery failed: ${error.javaClass.simpleName}")
        if (runAttemptCount < 8) Result.retry() else Result.failure()
    }
}
