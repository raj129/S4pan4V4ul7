package com.system.calculator

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Reads and writes the system call log.
 *
 * Writing needs WRITE_CALL_LOG, which Google Play limits to default dialer
 * apps, so this only works for sideloaded or internally distributed builds.
 */
class CallLogPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("not_attached", "Call log plugin is not attached.", null)
            return
        }
        when (call.method) {
            "status" -> result.success(status(ctx))
            "request" -> requestPermissions(ctx, result)
            "list" -> {
                if (!granted(ctx, Manifest.permission.READ_CALL_LOG)) {
                    result.error("permission_denied", "READ_CALL_LOG not granted.", null)
                    return
                }
                result.success(queryCalls(ctx, call.argument<Int>("limit") ?: DEFAULT_LIMIT))
            }
            "insert" -> {
                if (!granted(ctx, Manifest.permission.WRITE_CALL_LOG)) {
                    result.error("permission_denied", "WRITE_CALL_LOG not granted.", null)
                    return
                }
                val number = call.argument<String>("number")
                val type = call.argument<Int>("type")
                val timestampMs = call.argument<Number>("timestampMs")?.toLong()
                if (number.isNullOrBlank() || type == null || timestampMs == null) {
                    result.error("invalid_argument", "number, type and timestampMs are required.", null)
                    return
                }
                val values = ContentValues().apply {
                    put(CallLog.Calls.NUMBER, number)
                    put(CallLog.Calls.CACHED_NAME, call.argument<String>("name"))
                    put(CallLog.Calls.TYPE, type)
                    put(CallLog.Calls.DATE, timestampMs)
                    put(CallLog.Calls.DURATION, call.argument<Int>("durationSeconds") ?: 0)
                    put(CallLog.Calls.NEW, 0)
                }
                val uri = ctx.contentResolver.insert(CallLog.Calls.CONTENT_URI, values)
                result.success(uri != null)
            }
            "update" -> {
                if (!granted(ctx, Manifest.permission.WRITE_CALL_LOG)) {
                    result.error("permission_denied", "WRITE_CALL_LOG not granted.", null)
                    return
                }
                val id = call.argument<String>("id")
                val timestampMs = call.argument<Number>("timestampMs")?.toLong()
                if (id.isNullOrBlank() || timestampMs == null) {
                    result.error("invalid_argument", "id and timestampMs are required.", null)
                    return
                }
                val values = ContentValues().apply {
                    put(CallLog.Calls.DATE, timestampMs)
                    put(CallLog.Calls.DURATION, call.argument<Int>("durationSeconds") ?: 0)
                }
                val updated = ctx.contentResolver.update(
                    CallLog.Calls.CONTENT_URI,
                    values,
                    "${CallLog.Calls._ID} = ?",
                    arrayOf(id),
                )
                result.success(updated > 0)
            }
            else -> result.notImplemented()
        }
    }

    private fun granted(ctx: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(ctx, permission) == PackageManager.PERMISSION_GRANTED

    private fun status(ctx: Context): Map<String, Boolean> = mapOf(
        "read" to granted(ctx, Manifest.permission.READ_CALL_LOG),
        "write" to granted(ctx, Manifest.permission.WRITE_CALL_LOG),
    )

    private fun requestPermissions(ctx: Context, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("no_activity", "No foreground activity to request permissions.", null)
            return
        }
        val missing = PERMISSIONS.filterNot { granted(ctx, it) }
        if (missing.isEmpty()) {
            result.success(status(ctx))
            return
        }
        if (pendingResult != null) {
            result.error("busy", "A permission request is already in progress.", null)
            return
        }
        pendingResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        pendingResult = null
        val ctx = context
        if (ctx == null) {
            result.error("not_attached", "Call log plugin is not attached.", null)
        } else {
            result.success(status(ctx))
        }
        return true
    }

    private fun queryCalls(ctx: Context, limit: Int): List<Map<String, Any?>> {
        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
        )
        // LIMIT is applied in code: some OEM call log providers reject it in sortOrder.
        val cursor = ctx.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            projection,
            null,
            null,
            "${CallLog.Calls.DATE} DESC",
        ) ?: return emptyList()
        cursor.use { c ->
            val rows = ArrayList<Map<String, Any?>>(minOf(c.count, limit))
            val idIdx = c.getColumnIndexOrThrow(CallLog.Calls._ID)
            val numberIdx = c.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
            val nameIdx = c.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)
            val typeIdx = c.getColumnIndexOrThrow(CallLog.Calls.TYPE)
            val dateIdx = c.getColumnIndexOrThrow(CallLog.Calls.DATE)
            val durationIdx = c.getColumnIndexOrThrow(CallLog.Calls.DURATION)
            while (c.moveToNext() && rows.size < limit) {
                rows.add(
                    mapOf(
                        "id" to c.getLong(idIdx).toString(),
                        "number" to c.getString(numberIdx),
                        "name" to c.getString(nameIdx),
                        "type" to c.getInt(typeIdx),
                        "timestampMs" to c.getLong(dateIdx),
                        "durationSeconds" to c.getLong(durationIdx),
                    ),
                )
            }
            return rows
        }
    }

    private companion object {
        const val CHANNEL = "photo_vault/call_log"
        const val REQUEST_CODE = 7421
        const val DEFAULT_LIMIT = 500
        val PERMISSIONS = arrayOf(
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.WRITE_CALL_LOG,
        )
    }
}
