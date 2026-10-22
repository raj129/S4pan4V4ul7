package com.system.calculator.chatdownloads

import android.content.Context
import android.database.sqlite.SQLiteFullException
import android.os.Handler
import android.os.Looper
import android.system.ErrnoException
import android.system.OsConstants
import com.google.firebase.auth.FirebaseAuth
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class ChatLocalMediaChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    fun close() {
        io.shutdown()
    }

    private fun requireAccount(uid: String) {
        if (uid.isEmpty() || FirebaseAuth.getInstance().currentUser?.uid != uid) {
            throw LocalMediaException("local_media_unauthorized")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("read", "metadata", "put", "remove", "markMoved", "clear")) {
            result.notImplemented()
            return
        }
        io.execute {
            var response: Any? = null
            var input: ByteArray? = null
            try {
                input = call.argument<ByteArray>("bytes")
                val uid = call.argument<String>("uid")
                    ?: throw LocalMediaException("local_media_unauthorized")
                requireAccount(uid)
                response = ChatLocalMediaStore.locked(context) { store ->
                    requireAccount(uid)
                    if (call.method == "clear") {
                        store.clear(uid)
                        return@locked null
                    }
                    val path = call.argument<String>("path")
                        ?: throw LocalMediaException("local_media_invalid_identity")
                    when (call.method) {
                        "read" -> store.read(uid, path, call.argument<String>("direction") ?: "received")
                        "metadata" -> store.metadata(uid, path)
                        "put" -> {
                            val flags = call.argument<Number>("sourceFlags")?.toLong()
                            if (flags != null && flags !in 0..Int.MAX_VALUE.toLong()) {
                                throw LocalMediaException("local_media_invalid_source")
                            }
                            store.put(
                                uid, path, call.argument<String>("direction")
                                    ?: throw LocalMediaException("local_media_invalid_direction"),
                                input ?: throw LocalMediaException("local_media_invalid_size"),
                                call.argument<String>("sourceUri"), call.argument<String>("sourceDigest"),
                                flags?.toInt()
                            )
                            null
                        }

                        "remove", "markMoved" -> {
                            store.remove(uid, path, call.method == "markMoved")
                            null
                        }

                        else -> null
                    }
                }
                val value = response
                main.post {
                    try {
                        requireAccount(uid)
                        result.success(value)
                    } catch (_: Exception) {
                        result.error("local_media_unauthorized", "Chat sign-in changed. Reopen the attachment.", null)
                    } finally {
                        (value as? ByteArray)?.fill(0)
                    }
                }
            } catch (error: Exception) {
                (response as? ByteArray)?.fill(0)
                val code = when {
                    error is LocalMediaException -> error.code
                    generateSequence<Throwable>(error) { it.cause }.any {
                        it is SQLiteFullException || (it is ErrnoException && it.errno == OsConstants.ENOSPC)
                    } -> "local_media_storage_full"

                    error is ClassCastException || error is IllegalArgumentException -> "local_media_invalid_arguments"
                    else -> "local_media_unavailable"
                }
                main.post {
                    result.error(
                        code,
                        "Encrypted local attachment action failed. Check sign-in and device storage.", null
                    )
                }
            } finally {
                input?.fill(0)
            }
        }
    }
}
