package com.system.calculator

import android.Manifest
import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Criteria
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * Feeds the in-app mock position into Android's location providers so other
 * apps see it too. Requires this app to be chosen under Developer options →
 * "Select mock location app". A foreground service keeps re-publishing the
 * last position and shows an ongoing reminder with a Stop action.
 */
class MockLocationPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val ch = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel = ch
        MockLocationEngine.onStopRequested = {
            Handler(Looper.getMainLooper()).post { ch.invokeMethod("stopRequested", null) }
        }
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isMockAppSelected" -> result.success(MockLocationEngine.isMockAppSelected(context))
                    "openDeveloperSettings" -> {
                        openDeveloperSettings(context)
                        result.success(null)
                    }
                    "start" -> {
                        if (!MockLocationEngine.isMockAppSelected(context)) {
                            result.error("not_selected", "Select this app as the mock location app.", null)
                            return@setMethodCallHandler
                        }
                        MockLocationEngine.addProviders(context)
                        MockLocationEngine.status = call.argument<String>("status") ?: ""
                        MockLocationService.start(context)
                        result.success(null)
                    }
                    "push" -> {
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        if (lat == null || lng == null) {
                            result.error("bad_args", "lat and lng are required.", null)
                            return@setMethodCallHandler
                        }
                        call.argument<String>("status")?.let { MockLocationEngine.status = it }
                        MockLocationEngine.push(
                            context,
                            MockFix(
                                lat, lng,
                                call.argument<Double>("acc") ?: 5.0,
                                call.argument<Double>("alt") ?: 0.0,
                                call.argument<Double>("bearing") ?: 0.0,
                                call.argument<Double>("speed") ?: 0.0,
                            ),
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        MockLocationService.stop(context)
                        MockLocationEngine.removeProviders(context)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("not_selected", e.message ?: "Mock locations are not allowed for this app.", null)
            } catch (e: Exception) {
                result.error("mock_failed", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // The engine is gone, so nothing can keep the mock in sync: stop it.
        MockLocationService.stop(binding.applicationContext)
        MockLocationEngine.removeProviders(binding.applicationContext)
        MockLocationEngine.onStopRequested = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun openDeveloperSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    companion object {
        const val CHANNEL = "com.system.calculator/mock_location"
    }
}

data class MockFix(
    val lat: Double,
    val lng: Double,
    val accuracy: Double,
    val altitude: Double,
    val bearing: Double,
    val speed: Double,
)

object MockLocationEngine {
    @Volatile var last: MockFix? = null
    @Volatile var status: String = ""
    @Volatile var onStopRequested: (() -> Unit)? = null
    private val added = mutableSetOf<String>()

    private fun providers(): List<String> {
        val list = mutableListOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        if (Build.VERSION.SDK_INT >= 31) list.add(LocationManager.FUSED_PROVIDER)
        return list
    }

    fun isMockAppSelected(context: Context): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java) ?: return false
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_MOCK_LOCATION, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_MOCK_LOCATION, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    @Synchronized
    fun addProviders(context: Context) {
        val lm = context.getSystemService(LocationManager::class.java)
        for (name in providers()) {
            if (name in added) continue
            try {
                lm.removeTestProvider(name)
            } catch (_: IllegalArgumentException) {
            }
            if (Build.VERSION.SDK_INT >= 31) {
                lm.addTestProvider(
                    name,
                    ProviderProperties.Builder()
                        .setHasAltitudeSupport(true)
                        .setHasSpeedSupport(true)
                        .setHasBearingSupport(true)
                        .setPowerUsage(ProviderProperties.POWER_USAGE_LOW)
                        .setAccuracy(ProviderProperties.ACCURACY_FINE)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                lm.addTestProvider(
                    name, false, name == LocationManager.GPS_PROVIDER, false, false,
                    true, true, true, Criteria.POWER_LOW, Criteria.ACCURACY_FINE,
                )
            }
            lm.setTestProviderEnabled(name, true)
            added.add(name)
        }
    }

    @Synchronized
    fun removeProviders(context: Context) {
        val lm = context.getSystemService(LocationManager::class.java)
        for (name in added.toList()) {
            try {
                lm.setTestProviderEnabled(name, false)
                lm.removeTestProvider(name)
            } catch (_: Exception) {
            }
        }
        added.clear()
        last = null
    }

    fun push(context: Context, fix: MockFix) {
        last = fix
        republish(context)
    }

    @Synchronized
    fun republish(context: Context) {
        val fix = last ?: return
        if (added.isEmpty()) return
        val lm = context.getSystemService(LocationManager::class.java)
        for (name in added) {
            val location = Location(name).apply {
                latitude = fix.lat
                longitude = fix.lng
                accuracy = fix.accuracy.toFloat()
                altitude = fix.altitude
                bearing = fix.bearing.toFloat()
                speed = fix.speed.toFloat()
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                if (Build.VERSION.SDK_INT >= 26) {
                    bearingAccuracyDegrees = 5f
                    speedAccuracyMetersPerSecond = 0.5f
                    verticalAccuracyMeters = 3f
                }
            }
            lm.setTestProviderLocation(name, location)
        }
    }
}

/** Keeps the system mock alive and visible while it is running. */
class MockLocationService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            try {
                MockLocationEngine.republish(this@MockLocationService)
                notificationManager().notify(NOTIFICATION_ID, buildNotification())
            } catch (e: SecurityException) {
                // Mock app was deselected in system settings.
                requestStop()
                return
            } catch (_: Exception) {
            }
            handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            requestStop()
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 29 && hasLocationPermission()) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else if (Build.VERSION.SDK_INT < 29) {
                startForeground(NOTIFICATION_ID, notification)
            } else {
                notificationManager().notify(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            android.util.Log.w("MockLocation", "Could not start foreground: ${e.javaClass.simpleName}")
            notificationManager().notify(NOTIFICATION_ID, notification)
        }
        handler.removeCallbacks(ticker)
        handler.post(ticker)
        return START_NOT_STICKY
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun requestStop() {
        handler.removeCallbacks(ticker)
        MockLocationEngine.removeProviders(this)
        MockLocationEngine.onStopRequested?.invoke()
        stopForeground(STOP_FOREGROUND_REMOVE)
        notificationManager().cancel(NOTIFICATION_ID)
        stopSelf()
    }

    override fun onTimeout(startId: Int, fgsType: Int) = requestStop()

    override fun onDestroy() {
        handler.removeCallbacks(ticker)
        notificationManager().cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    private fun notificationManager() = getSystemService(NotificationManager::class.java)

    @SuppressLint("LaunchActivityFromNotification")
    private fun buildNotification(): Notification {
        val manager = notificationManager()
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Mock location", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val stop = PendingIntent.getService(
            this, 0,
            Intent(this, MockLocationService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 1, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val status = MockLocationEngine.status.ifEmpty { "Other apps see a simulated position" }
        builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Mock location is on")
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop mock", stop).build())
        if (open != null) builder.setContentIntent(open)
        return builder.build()
    }

    companion object {
        private const val CHANNEL_ID = "mock_location"
        private const val NOTIFICATION_ID = 4731
        private const val ACTION_STOP = "com.system.calculator.mock_location.STOP"

        fun start(context: Context) {
            val intent = Intent(context, MockLocationService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MockLocationService::class.java))
        }
    }
}
