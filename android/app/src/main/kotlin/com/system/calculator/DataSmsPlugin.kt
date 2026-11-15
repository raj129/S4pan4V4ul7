package com.system.calculator

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class DataSmsPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "photo_vault/data_sms").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isSupported" -> result.success(supported(context))
                        "pending" -> DataSmsStore(context).use { result.success(it.snapshot()) }
                        "acknowledge" -> {
                            val id = requireNotNull(call.argument<String>("messageId"))
                            val source = requireNotNull(call.argument<String>("source"))
                            DataSmsStore(context).use { it.acknowledge(id, source) }
                            result.success(null)
                        }
                        "acknowledgeOutgoing" -> {
                            val id = requireNotNull(call.argument<String>("messageId"))
                            DataSmsStore(context).use { it.acknowledgeOutgoing(id) }
                            result.success(null)
                        }
                        "send" -> {
                            val id = requireNotNull(call.argument<String>("messageId")).lowercase()
                            val phone = requireNotNull(call.argument<String>("phone")).trim()
                            val payload = requireNotNull(call.argument<ByteArray>("payload"))
                            result.success(send(context, id, phone, payload))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("data_sms_error", e.message ?: "Data SMS failed", null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun send(context: Context, id: String, phone: String, payload: ByteArray): Map<String, Any?> {
        check(supported(context)) { "Data SMS is not supported on this device" }
        check(ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED) {
            "SMS permissions are required"
        }
        require(phone.matches(Regex("^\\+?[0-9]{3,20}$"))) { "Invalid destination phone number" }
        val chunks = DataSmsProtocol.split(id, payload)
        val subscription = SubscriptionManager.getDefaultSmsSubscriptionId()
        check(SubscriptionManager.isValidSubscriptionId(subscription)) {
            "Set a default SMS SIM in system settings before sending"
        }
        @Suppress("DEPRECATION")
        val manager = SmsManager.getSmsManagerForSubscriptionId(subscription)
        DataSmsStore(context).use { store ->
            store.createOutgoing(id, phone, chunks.size)
            for ((index, chunk) in chunks.withIndex()) {
                store.submitState(id, index, "submitting")
                try {
                    manager.sendDataMessage(phone, null, DataSmsProtocol.PORT.toShort(), chunk,
                        callbackIntent(context, id, index, "sent"),
                        callbackIntent(context, id, index, "delivery"))
                    store.submitState(id, index, "submitted")
                } catch (e: Exception) {
                    // This call may have reached telephony; never retry automatically.
                    store.submitState(id, index, "failed", e.message ?: "Submission failed")
                    break
                }
            }
            @Suppress("UNCHECKED_CAST")
            return (store.snapshot()["outgoing"] as List<Map<String, Any?>>).first { it["id"] == id }
        }
    }

    private fun callbackIntent(context: Context, id: String, index: Int, kind: String): PendingIntent {
        val intent = Intent(context, DataSmsCallbackReceiver::class.java).apply {
            action = "com.system.calculator.DATA_SMS_$kind"
            data = Uri.Builder().scheme("datasms").authority(context.packageName)
                .appendPath(id).appendPath(index.toString()).appendPath(kind).build()
        }
        // Telephony supplies the delivery-report PDU through fill-in extras.
        val mutability = if (kind == "delivery" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else if (kind == "delivery") {
            0
        } else {
            PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutability)
    }

    companion object {
        private fun supported(context: Context): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                context.packageManager.hasSystemFeature(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                        PackageManager.FEATURE_TELEPHONY_MESSAGING
                    else PackageManager.FEATURE_TELEPHONY)
    }
}

class DataSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.DATA_SMS_RECEIVED_ACTION) return
        val pending = goAsync()
        val app = context.applicationContext
        try {
            receiverExecutor.execute {
                try {
                    val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                    if (messages.size > DataSmsProtocol.MAX_SEGMENTS) return@execute
                    DataSmsStore(app).use { store ->
                        for (message in messages) {
                            val source = message.originatingAddress ?: continue
                            if (source.isBlank() || source.length > 64) continue
                            val part = DataSmsProtocol.parse(message.userData ?: continue) ?: continue
                            store.receive(source, part)
                        }
                    }
                } catch (_: Exception) {
                    // A malformed or unpersistable broadcast is never acknowledged as imported.
                } finally {
                    pending.finish()
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            pending.finish()
        }
    }

    companion object {
        private val receiverExecutor = ThreadPoolExecutor(
            1, 1, 0, TimeUnit.SECONDS, ArrayBlockingQueue(16))
    }
}

class DataSmsCallbackReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.data ?: return
        if (data.scheme != "datasms" || data.authority != context.packageName) return
        val path = data.pathSegments
        if (path.size != 3) return
        val index = path[1].toIntOrNull() ?: return
        if (index !in 0 until DataSmsProtocol.MAX_SEGMENTS) return
        val kind = path[2]
        var success = resultCode == Activity.RESULT_OK
        if (kind == "delivery" && success) {
            val pdu = intent.getByteArrayExtra("pdu") ?: return
            val format = intent.getStringExtra("format")
            @Suppress("DEPRECATION")
            val report = if (format != null) {
                SmsMessage.createFromPdu(pdu, format)
            } else {
                SmsMessage.createFromPdu(pdu)
            } ?: return
            val status = report.status
            if (status in 0x20..0x3f) return
            success = status in 0..0x1f
        }
        if (kind != "sent" && kind != "delivery") return
        DataSmsStore(context).use { it.callback(path[0], index, kind, success, resultCode) }
    }
}
