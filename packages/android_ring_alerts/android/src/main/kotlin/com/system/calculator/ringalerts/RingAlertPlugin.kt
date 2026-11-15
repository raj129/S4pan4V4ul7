package com.system.calculator.ringalerts

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class RingAlertPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pickerResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickRingtone" -> pickRingtone(call, result)
            "ringtoneTitle" -> {
                val uri = call.argument<String>("uri")?.let(Uri::parse)
                result.success(uri?.let {
                    RingtoneManager.getRingtone(applicationContext, it)
                        ?.getTitle(applicationContext)
                })
            }
            "hasFlashlight" -> result.success(hasFlashlight())
            "systemAlertSettings" -> result.success(systemAlertSettings())
            "openSystemRingtoneSettings" -> {
                applicationContext.startActivity(
                    Intent(Settings.ACTION_SOUND_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "openSystemFlashSettings" -> {
                applicationContext.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "startAlert" -> startAlert(call, result)
            "stopAlert" -> {
                val intent = Intent(applicationContext, RingAlertService::class.java)
                    .setAction(RingAlertService.ACTION_STOP)
                    .putExtra(RingAlertService.EXTRA_ALERT_ID, call.argument<String>("alertId"))
                applicationContext.startService(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startAlert(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        val alertId = call.argument<String>("alertId")
        val source = call.argument<String>("source")
        val legacyMode = call.argument<String>("mode")
        val ringSoundEnabled = call.argument<Boolean>("ringSoundEnabled")
            ?: (legacyMode == "ringAndVibrate" || legacyMode == "ringtone")
        val vibrationEnabled = call.argument<Boolean>("vibrationEnabled")
            ?: (legacyMode == "ringAndVibrate" || legacyMode == "vibrate")
        val timeout = call.argument<Int>("timeoutSeconds")
        val startDelay = call.argument<Int>("startDelaySeconds") ?: 0
        if (alertId.isNullOrBlank() ||
            source !in setOf("system", "custom") ||
            timeout == null ||
            startDelay !in setOf(0, 3, 5, 10, 15)
        ) {
            result.error("invalid_argument", "Invalid ring alert configuration.", null)
            return
        }
        val intent = Intent(context, RingAlertService::class.java)
            .setAction(RingAlertService.ACTION_START)
            .putExtra(RingAlertService.EXTRA_ALERT_ID, alertId)
            .putExtra(RingAlertService.EXTRA_SOURCE, source)
            .putExtra(RingAlertService.EXTRA_RING_SOUND_ENABLED, ringSoundEnabled)
            .putExtra(RingAlertService.EXTRA_VIBRATION_ENABLED, vibrationEnabled)
            .putExtra(RingAlertService.EXTRA_TIMEOUT_SECONDS, timeout.coerceIn(5, 120))
            .putExtra(RingAlertService.EXTRA_TITLE, call.argument<String>("title") ?: "Ring request")
            .putExtra(RingAlertService.EXTRA_BODY, call.argument<String>("body") ?: "Someone is asking you to ring.")
            .putExtra(RingAlertService.EXTRA_RINGTONE_URI, call.argument<String>("ringtoneUri"))
            .putExtra(RingAlertService.EXTRA_VIBRATION_PATTERN, call.argument<String>("vibrationPattern") ?: "standard")
            .putExtra(RingAlertService.EXTRA_FLASHLIGHT_ENABLED, call.argument<Boolean>("flashlightEnabled") == true)
            .putExtra(RingAlertService.EXTRA_FLASH_PATTERN, call.argument<String>("flashPattern") ?: "slowBlink")
            .putExtra(RingAlertService.EXTRA_START_DELAY_SECONDS, startDelay)
            .putExtra(RingAlertService.EXTRA_ALLOW_FLASH_IN_BACKGROUND, call.argument<Boolean>("allowFlashInBackground") == true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        result.success(null)
    }

    private fun hasFlashlight(): Boolean {
        if (applicationContext.checkSelfPermission(android.Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        return try {
            val manager = applicationContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            manager.cameraIdList.any { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun systemAlertSettings(): Map<String, Any?> {
        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val ringtoneTitle = ringtoneUri?.let {
            RingtoneManager.getRingtone(applicationContext, it)
                ?.getTitle(applicationContext)
        }
        val cameraFlashEnabled = readSystemToggle("camera_flash_notification")
        val screenFlashEnabled = readSystemToggle("screen_flash_notification")
        return mapOf(
            "ringtoneTitle" to ringtoneTitle,
            "cameraFlashEnabled" to cameraFlashEnabled,
            "screenFlashEnabled" to screenFlashEnabled,
        )
    }

    private fun readSystemToggle(name: String): Boolean {
        return try {
            Settings.System.getInt(applicationContext.contentResolver, name, 0) == 1
        } catch (_: SecurityException) {
            false
        }
    }

    private fun pickRingtone(call: MethodCall, result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("unavailable", "No Android activity is attached.", null)
            return
        }
        if (pickerResult != null) {
            result.error("picker_busy", "The ringtone picker is already open.", null)
            return
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_RINGTONE)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
        call.argument<String>("currentUri")?.let {
            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(it))
        }
        pickerResult = result
        currentActivity.startActivityForResult(intent, RINGTONE_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != RINGTONE_REQUEST_CODE) return false
        val result = pickerResult ?: return true
        pickerResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return true
        }
        val uri = data.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        result.success(uri?.toString())
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    private companion object {
        const val CHANNEL = "com.system.calculator/ring_alerts"
        const val RINGTONE_REQUEST_CODE = 7312
    }
}
