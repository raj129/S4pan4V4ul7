package com.system.calculator

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.work.*
import com.google.firebase.auth.FirebaseAuth
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ChatUploadPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "photo_vault/chat_uploads")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        io.execute {
            try {
                val uid = FirebaseAuth.getInstance().currentUser?.uid
                    ?: throw IllegalStateException("Sign in to send attachments")
                val value = ChatUploadRuntime.locked {
                    ChatUploadStore(context).use { store ->
                        when (call.method) {
                            "recoverUploaded" -> {
                                val args = call.arguments as Map<*, *>
                                require(args["senderId"] == uid)
                                val id = args["messageId"] as String
                                require(id.matches(Regex("[A-Za-z0-9-]{1,128}")))
                                val thread = args["threadId"] as String
                                val ref = args["mediaRef"] as String
                                require(thread.split("_").sorted() == listOf(uid, args["recipientUid"] as String).sorted())
                                require(ref.startsWith("chat_media/$thread/$id/") && !ref.contains(".."))
                                val existing = store.get(id)
                                if (existing != null) {
                                    require(existing.getString("senderId") == uid && existing.getString("threadId") == thread)
                                    return@use publicJob(existing)
                                }
                                val job = JSONObject().apply {
                                    put("messageId", id); put("threadId", thread); put("senderId", uid)
                                    put("recipientUid", args["recipientUid"]); put("encryptedText", args["encryptedText"])
                                    put("mediaRef", ref); put("mediaType", args["mediaType"])
                                    put("mediaMeta", JSONObject(args["mediaMeta"] as? Map<*, *> ?: emptyMap<Any, Any>()))
                                    put("sentAt", args["sentAt"]); put("legacyFinalized", true)
                                    put("digest", MessageDigest.getInstance("SHA-256").digest(ref.toByteArray())
                                        .joinToString("") { "%02x".format(it) })
                                    put("hasThumb", false); put("totalBytes", 0); put("processedBytes", 0)
                                    put("state", "queued"); put("attempts", 0); put("eligibleAt", 0L); put("revision", 0)
                                }
                                store.put(job)
                                publicJob(job)
                            }
                            "enqueue" -> {
                                val args = call.arguments as Map<*, *>
                                require(args["senderId"] == uid)
                                val id = args["messageId"] as String
                                require(id.matches(Regex("[A-Za-z0-9-]{1,128}")))
                                val thread = args["threadId"] as String
                                require(thread.split("_").sorted() == listOf(uid, args["recipientUid"] as String).sorted())
                                require(args["mediaType"] in listOf("image", "video", "audio", "file"))
                                require((args["encryptedText"] as String).isNotEmpty())
                                val bytes = args["bytes"] as ByteArray
                                val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
                                    .joinToString("") { "%02x".format(it) }
                                val existing = store.get(id)
                                if (existing != null) {
                                    require(existing.getString("senderId") == uid &&
                                        existing.getString("threadId") == thread &&
                                        existing.getString("digest") == digest) { "Duplicate identity mismatch" }
                                    return@use publicJob(existing)
                                }
                                store.stage(id, bytes)
                                val thumbnail = args["thumbnail"] as? ByteArray
                                if (thumbnail != null) store.stage(id, thumbnail, true)
                                val job = JSONObject().apply {
                                    put("messageId", id); put("threadId", thread); put("senderId", uid)
                                    put("recipientUid", args["recipientUid"])
                                    put("encryptedText", args["encryptedText"]); put("mediaType", args["mediaType"])
                                    put("mediaMeta", JSONObject(args["mediaMeta"] as? Map<*, *> ?: emptyMap<Any, Any>()))
                                    put("sentAt", args["sentAt"]); put("digest", digest)
                                    put("isForwarded", args["isForwarded"] == true)
                                    put("thumbDigest", thumbnail?.let {
                                        MessageDigest.getInstance("SHA-256").digest(it).joinToString("") { b -> "%02x".format(b) }
                                    } ?: "")
                                    put("hasThumb", thumbnail != null); put("totalBytes", bytes.size + (thumbnail?.size ?: 0))
                                    put("processedBytes", 0); put("state", "queued"); put("attempts", 0)
                                    put("eligibleAt", 0L); put("revision", 0)
                                }
                                store.put(job)
                                publicJob(job)
                            }
                            "list" -> store.all().filter { it.getString("senderId") == uid }.map { publicJob(it) }
                            "wake" -> null
                            "acknowledge" -> {
                                val id = call.argument<String>("messageId") ?: throw IllegalArgumentException()
                                val job = store.get(id)
                                if (job != null) {
                                    require(job.getString("senderId") == uid && job.getString("state") == "completed")
                                    store.acknowledge(id)
                                }
                                null
                            }
                            "pause", "resume", "cancel", "retry" -> {
                                val id = call.argument<String>("messageId") ?: throw IllegalArgumentException()
                                val job = store.get(id) ?: throw IllegalArgumentException("Unknown upload")
                                require(job.getString("senderId") == uid)
                                val state = job.getString("state")
                                val next = ChatUploadPolicy.transition(state, call.method, job.optBoolean("delivering"))
                                if (state != next) {
                                    job.put("state", next).put("eligibleAt", 0L)
                                        .put("revision", job.optInt("revision") + 1)
                                    if (call.method == "retry") job.put("attempts", 0)
                                    // The runtime's last snapshot is checkpointed
                                    // by its settling owner before another drain.
                                    store.put(job)
                                    ChatUploadRuntime.interrupt(id, next == "cancelled")
                                    if (next == "cancelled") {
                                        for (file in listOf(store.blob(id), store.blob(id, true))) {
                                            check(!file.exists() || file.delete()) { "Could not clean cancelled encrypted attachment" }
                                        }
                                    }
                                }
                                publicJob(job)
                            }
                            else -> throw IllegalArgumentException("Unknown upload command")
                        }
                    }
                }
                if (call.method in listOf("enqueue", "recoverUploaded", "wake", "resume", "retry")) {
                    schedule(context)
                    if (call.method != "wake") {
                        try {
                            val intent = Intent(context, ChatUploadService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                            else context.startService(intent)
                        } catch (_: IllegalStateException) {
                            // Android may disallow an FGS start; durable WorkManager work remains.
                        } catch (_: SecurityException) {
                            // Notification/service restrictions do not discard the durable job.
                        }
                    }
                }
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("upload_unavailable", error.message ?: "Upload unavailable", null) }
            }
        }
    }
    companion object {
        fun schedule(context: Context, delay: Long = 0) {
            val request = OneTimeWorkRequestBuilder<ChatUploadWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setInitialDelay(delay.coerceAtLeast(0), TimeUnit.MILLISECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork("chat_encrypted_uploads",
                // A new intent arriving while a drain exits must leave a
                // durable successor; KEEP can lose that wake-up.
                ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
        fun publicJob(job: JSONObject): Map<String, Any?> = mapOf(
            "messageId" to job.getString("messageId"), "threadId" to job.getString("threadId"),
            "senderId" to job.getString("senderId"), "encryptedText" to job.getString("encryptedText"),
            "mediaType" to job.getString("mediaType"), "sentAt" to job.getLong("sentAt"),
            "isForwarded" to job.optBoolean("isForwarded"),
            "state" to job.getString("state"), "processedBytes" to job.optLong("processedBytes"),
            "totalBytes" to job.getLong("totalBytes"),
            "mediaRef" to (job.optString("mediaRef").takeIf { it.isNotEmpty() }
                ?: "chat_media/${job.getString("threadId")}/${job.getString("messageId")}/media.enc"),
            "mediaMeta" to jsonMap(job.getJSONObject("mediaMeta")),
            "error" to job.optString("error").takeIf { it.isNotEmpty() }
        )
        fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith {
            val value = json.get(it)
            if (value is JSONObject) jsonMap(value) else if (value == JSONObject.NULL) null else value
        }
    }
}
