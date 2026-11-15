package com.system.calculator.ringalerts

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat

class RingAlertService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var currentAlertId: String? = null
    private var cameraManager: CameraManager? = null
    private var torchCameraId: String? = null
    private var flashlightOn = false
    private var flashRunnable: Runnable? = null
    private var volumeKeySession: MediaSession? = null
    private var volumeReceiverRegistered = false
    private val volumeChangedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_VOLUME_CHANGED) return
            val stream = intent.getIntExtra(EXTRA_VOLUME_STREAM_TYPE, -1)
            if (stream >= 0) {
                Log.i(TAG, "Volume stream $stream changed; silencing ring request.")
                stopAlert()
            }
        }
    }

    private val repeatRingtone = object : Runnable {
        override fun run() {
            val current = ringtone ?: return
            if (!current.isPlaying) current.play()
            handler.postDelayed(this, 4_000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            val requestedId = intent.getStringExtra(EXTRA_ALERT_ID)
            if (requestedId == null || requestedId == currentAlertId) stopAlert()
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        stopAlert(removeForeground = false)
        currentAlertId = intent.getStringExtra(EXTRA_ALERT_ID)
        val source = RingAlertPolicy.parseSource(intent.getStringExtra(EXTRA_SOURCE))
        val ringSoundEnabled =
            intent.getBooleanExtra(EXTRA_RING_SOUND_ENABLED, true)
        val vibrationEnabled =
            intent.getBooleanExtra(EXTRA_VIBRATION_ENABLED, true)
        val timeoutSeconds = intent
            .getIntExtra(EXTRA_TIMEOUT_SECONDS, 5)
            .coerceIn(5, 120)
        val delaySeconds = intent
            .getIntExtra(EXTRA_START_DELAY_SECONDS, 0)
            .coerceIn(0, 15)
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val systemMode = when (audio.ringerMode) {
            AudioManager.RINGER_MODE_NORMAL -> SystemRingerMode.NORMAL
            AudioManager.RINGER_MODE_VIBRATE -> SystemRingerMode.VIBRATE
            AudioManager.RINGER_MODE_SILENT -> SystemRingerMode.SILENT
            else -> SystemRingerMode.UNKNOWN
        }
        @Suppress("DEPRECATION")
        val vibratesWhenRinging = audio.shouldVibrate(AudioManager.VIBRATE_TYPE_RINGER)
        val doNotDisturb = isDoNotDisturbActive()
        val output = RingAlertPolicy.resolve(
            source = source,
            ringSoundEnabled = ringSoundEnabled,
            vibrationEnabled = vibrationEnabled,
            systemMode = systemMode,
            systemVibratesWhenRinging = vibratesWhenRinging,
            doNotDisturb = doNotDisturb,
        )

        val requestedFlashlight = RingAlertPolicy.flashlightEnabled(
            source = source,
            appFlashlightEnabled =
                intent.getBooleanExtra(EXTRA_FLASHLIGHT_ENABLED, false),
            systemFlashlightEnabled = readSystemToggle("camera_flash_notification"),
            doNotDisturb = doNotDisturb,
        ) && (intent.getBooleanExtra(EXTRA_ALLOW_FLASH_IN_BACKGROUND, false) ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
        if (output == RingAlertOutput.SILENT && !requestedFlashlight) {
            stopAlert()
            return START_NOT_STICKY
        }
        val cameraPermissionGranted = checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        val useFlashlight = requestedFlashlight && cameraPermissionGranted &&
            hasFlashlightHardware()

        createChannel()
        val notification = buildNotification()
        val flashlightAllowedByService = startForegroundForAlert(
            notification,
            useFlashlight,
        )
        startVolumeKeySilencer()
        val beginAlert = Runnable {
            if (output == RingAlertOutput.RING ||
                output == RingAlertOutput.RING_AND_VIBRATE
            ) {
                startRingtone(source, intent.getStringExtra(EXTRA_RINGTONE_URI))
            }
            if (output == RingAlertOutput.VIBRATE ||
                output == RingAlertOutput.RING_AND_VIBRATE
            ) {
                val vibrationPattern = if (source == RingAlertSource.CUSTOM) {
                    intent.getStringExtra(EXTRA_VIBRATION_PATTERN)
                } else {
                    null
                }
                startVibration(vibrationPattern, source)
            }
            if (flashlightAllowedByService) {
                startFlashlight(intent.getStringExtra(EXTRA_FLASH_PATTERN))
            }
            handler.postDelayed({ stopAlert() }, timeoutSeconds * 1000L)
        }
        if (delaySeconds == 0) {
            beginAlert.run()
        } else {
            handler.postDelayed(beginAlert, delaySeconds * 1000L)
        }
        return START_NOT_STICKY
    }

    private fun isDoNotDisturbActive(): Boolean {
        return try {
            getSystemService(NotificationManager::class.java)
                .currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
        } catch (error: SecurityException) {
            Log.w(TAG, "Could not read Do Not Disturb state; suppressing alert.", error)
            true
        }
    }

    private fun readSystemToggle(name: String): Boolean {
        return try {
            Settings.System.getInt(contentResolver, name, 0) == 1
        } catch (error: SecurityException) {
            Log.w(TAG, "Could not read system flash-notification setting.", error)
            false
        }
    }

    private fun startForegroundForAlert(
        notification: Notification,
        useFlashlight: Boolean,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification)
            return useFlashlight
        }

        val mediaPlaybackType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        if (!useFlashlight) {
            startForeground(NOTIFICATION_ID, notification, mediaPlaybackType)
            return false
        }
        return try {
            startForeground(
                NOTIFICATION_ID,
                notification,
                mediaPlaybackType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA,
            )
            true
        } catch (error: SecurityException) {
            Log.w(TAG, "Camera foreground access unavailable for ring alert.", error)
            startForeground(NOTIFICATION_ID, notification, mediaPlaybackType)
            false
        }
    }

    private fun startVolumeKeySilencer() {
        if (volumeKeySession != null) return
        val filter = IntentFilter(ACTION_VOLUME_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(volumeChangedReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(volumeChangedReceiver, filter)
        }
        volumeReceiverRegistered = true
        val session = MediaSession(this, "Ring request alert")
        session.setPlaybackToRemote(
            object : VolumeProvider(
                VolumeProvider.VOLUME_CONTROL_RELATIVE,
                100,
                50,
            ) {
                override fun onAdjustVolume(direction: Int) {
                    Log.i(TAG, "Hardware volume adjustment silencing ring alert.")
                    handler.post { stopAlert() }
                }

                override fun onSetVolumeTo(volume: Int) {
                    Log.i(TAG, "Hardware volume set silencing ring alert.")
                    handler.post { stopAlert() }
                }
            },
        )
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_STOP)
                .setState(
                    PlaybackState.STATE_PLAYING,
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    1f,
                )
                .build(),
        )
        session.isActive = true
        volumeKeySession = session
    }

    private fun stopVolumeKeySilencer() {
        volumeKeySession?.let { session ->
            session.isActive = false
            session.release()
        }
        volumeKeySession = null
        if (volumeReceiverRegistered) {
            try {
                unregisterReceiver(volumeChangedReceiver)
            } catch (error: IllegalArgumentException) {
                Log.w(TAG, "Ringer volume listener was already removed.", error)
            }
            volumeReceiverRegistered = false
        }
    }

    private fun startRingtone(source: RingAlertSource, uriString: String?) {
        val selectedUri = if (source == RingAlertSource.CUSTOM) {
            uriString?.takeIf(String::isNotBlank)?.let(Uri::parse)
        } else {
            null
        }
        val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val sound = try {
            RingtoneManager.getRingtone(this, selectedUri ?: defaultUri)
                ?: RingtoneManager.getRingtone(this, defaultUri)
        } catch (_: SecurityException) {
            RingtoneManager.getRingtone(this, defaultUri)
        } catch (_: IllegalArgumentException) {
            RingtoneManager.getRingtone(this, defaultUri)
        } ?: return
        sound.audioAttributes = AudioAttributes.Builder()
            .setUsage(
                if (source == RingAlertSource.CUSTOM) {
                    AudioAttributes.USAGE_ALARM
                } else {
                    AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                },
            )
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            sound.isLooping = true
        } else {
            handler.postDelayed(repeatRingtone, 4_000)
        }
        ringtone = sound
        sound.play()
    }

    private fun startVibration(patternName: String?, source: RingAlertSource) {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        val timings = when (patternName) {
            "shortPulses" -> longArrayOf(0, 180, 160, 180, 700)
            "longPulses" -> longArrayOf(0, 1_100, 450)
            else -> longArrayOf(0, 700, 500)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createWaveform(timings, 0)
            if (Build.VERSION.SDK_INT >= 33) {
                val attributes = VibrationAttributes.Builder()
                    .setUsage(
                        if (source == RingAlertSource.CUSTOM) {
                            VibrationAttributes.USAGE_ALARM
                        } else {
                            VibrationAttributes.USAGE_RINGTONE
                        },
                    )
                    .build()
                vibrator?.vibrate(effect, attributes)
            } else {
                val attributes = AudioAttributes.Builder()
                    .setUsage(
                        if (source == RingAlertSource.CUSTOM) {
                            AudioAttributes.USAGE_ALARM
                        } else {
                            AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                        },
                    )
                    .build()
                vibrator?.vibrate(effect, attributes)
            }
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(timings, 0)
        }
    }

    private fun hasFlashlightHardware(): Boolean {
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            manager.cameraIdList.any { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (error: Exception) {
            Log.w(TAG, "Could not check ring-alert flashlight support.", error)
            false
        }
    }

    private fun startFlashlight(patternName: String?) {
        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = try {
            manager.cameraIdList.firstOrNull { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (error: Exception) {
            Log.w(TAG, "Could not access flashlight for ring alert.", error)
            null
        } ?: return
        cameraManager = manager
        torchCameraId = cameraId

        val steps = when (patternName) {
            "doubleBlink" -> listOf(
                FlashStep(true, 140),
                FlashStep(false, 160),
                FlashStep(true, 140),
                FlashStep(false, 900),
            )
            "fastBlink" -> listOf(
                FlashStep(true, 120),
                FlashStep(false, 180),
            )
            else -> listOf(
                FlashStep(true, 650),
                FlashStep(false, 650),
            )
        }
        var index = 0
        val task = object : Runnable {
            override fun run() {
                val step = steps[index]
                index = (index + 1) % steps.size
                try {
                    manager.setTorchMode(cameraId, step.enabled)
                    flashlightOn = step.enabled
                    handler.postDelayed(this, step.durationMillis)
                } catch (error: Exception) {
                    Log.w(TAG, "Flashlight pattern could not continue.", error)
                    stopFlashlight()
                }
            }
        }
        flashRunnable = task
        task.run()
    }

    private fun stopFlashlight() {
        flashRunnable?.let(handler::removeCallbacks)
        flashRunnable = null
        val manager = cameraManager
        val cameraId = torchCameraId
        cameraManager = null
        torchCameraId = null
        if (flashlightOn && manager != null && cameraId != null) {
            try {
                manager.setTorchMode(cameraId, false)
            } catch (error: CameraAccessException) {
                Log.w(TAG, "Could not switch off the ring-alert flashlight.", error)
            } catch (error: SecurityException) {
                Log.w(TAG, "Flashlight permission ended before shutdown.", error)
            }
        }
        flashlightOn = false
    }

    private fun buildNotification(): Notification {
        val silenceIntent = Intent(this, RingAlertActionReceiver::class.java)
            .setAction(ACTION_STOP)
            .putExtra(EXTRA_ALERT_ID, currentAlertId)
        val silencePendingIntent = PendingIntent.getBroadcast(
            this,
            NOTIFICATION_ID,
            silenceIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setSilent(true)
            .addAction(android.R.drawable.ic_media_pause, "Silence", silencePendingIntent)
        return builder.build()
    }

    private fun silencePendingIntent(): PendingIntent {
        val silenceIntent = Intent(this, RingAlertActionReceiver::class.java)
            .setAction(ACTION_STOP)
            .putExtra(EXTRA_ALERT_ID, currentAlertId)
        return PendingIntent.getBroadcast(
            this,
            NOTIFICATION_ID,
            silenceIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Ring requests",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Alerts for incoming chat ring requests."
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
    }

    private fun stopAlert(removeForeground: Boolean = true) {
        handler.removeCallbacksAndMessages(null)
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
        stopFlashlight()
        stopVolumeKeySilencer()
        currentAlertId = null
        if (removeForeground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
    }

    override fun onDestroy() {
        stopAlert(removeForeground = false)
        super.onDestroy()
    }

    private data class FlashStep(
        val enabled: Boolean,
        val durationMillis: Long,
    )

    companion object {
        const val ACTION_START = "com.system.calculator.ringalerts.START"
        const val ACTION_STOP = "com.system.calculator.ringalerts.STOP"
        const val EXTRA_ALERT_ID = "alertId"
        const val EXTRA_SOURCE = "source"
        const val EXTRA_RING_SOUND_ENABLED = "ringSoundEnabled"
        const val EXTRA_VIBRATION_ENABLED = "vibrationEnabled"
        const val EXTRA_TIMEOUT_SECONDS = "timeoutSeconds"
        const val EXTRA_RINGTONE_URI = "ringtoneUri"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_VIBRATION_PATTERN = "vibrationPattern"
        const val EXTRA_FLASHLIGHT_ENABLED = "flashlightEnabled"
        const val EXTRA_FLASH_PATTERN = "flashPattern"
        const val EXTRA_START_DELAY_SECONDS = "startDelaySeconds"
        const val EXTRA_ALLOW_FLASH_IN_BACKGROUND = "allowFlashInBackground"
        private const val ACTION_VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"
        private const val EXTRA_VOLUME_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE"
        private const val CHANNEL_ID = "chat_ring_alerts_minimal"
        private const val NOTIFICATION_ID = 7321
        private const val TAG = "RingAlertService"
    }
}

class RingAlertActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        context.stopService(Intent(context, RingAlertService::class.java))
    }
}
