package com.system.calculator

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Reports what the installed APK presents to Google Maps (manifest key status,
 * package name, and signing certificate SHA-1), supplies the build-time
 * GIPHY API key from AndroidManifest metadata when Dart environment defines
 * were not passed on the command line, and manages window surface flags while
 * the native Google Map platform view is active.
 */
class MapsDiagnosticsPlugin : FlutterPlugin, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "report" -> result.success(report(context))
                    "getGiphyApiKey" -> result.success(getGiphyApiKey(context))
                    "getMapsApiIdentity" -> result.success(getMapsApiIdentity(context))
                    "setMapActive" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        setMapActive(active)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun setMapActive(active: Boolean) {
        val window = activity?.window ?: return
        if (active) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            ScreenshotProtectionState.applyTo(window)
        }
    }

    private fun getGiphyApiKey(context: Context): String {
        val pm = context.packageManager
        val appInfo = pm.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
        return appInfo.metaData?.getString("com.system.calculator.GIPHY_API_KEY").orEmpty()
    }

    /**
     * What Google needs to accept REST calls made with an Android-restricted
     * key: the key itself plus this app's package and signing certificate.
     */
    private fun getMapsApiIdentity(context: Context): Map<String, String> {
        val pm = context.packageManager
        val appInfo = pm.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
        return mapOf(
            "key" to appInfo.metaData?.getString("com.google.android.geo.API_KEY").orEmpty(),
            "package" to context.packageName,
            "sha1" to (signingSha1(context)?.replace(":", "") ?: ""),
        )
    }

    private fun report(context: Context): Map<String, Any?> {
        val pm = context.packageManager
        val appInfo = pm.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
        val key = appInfo.metaData?.getString("com.google.android.geo.API_KEY").orEmpty()
        // Release builds only reveal whether a key is baked in.
        if (appInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            return mapOf("keyPresent" to key.isNotBlank())
        }
        return mapOf(
            "package" to context.packageName,
            "keyPresent" to key.isNotBlank(),
            "keyMasked" to maskKey(key),
            "signingSha1" to signingSha1(context),
        )
    }

    private fun maskKey(key: String): String =
        if (key.length <= 10) {
            if (key.isEmpty()) "" else "*".repeat(key.length)
        } else {
            "${key.take(6)}…${key.takeLast(4)} (${key.length} chars)"
        }

    @Suppress("DEPRECATION")
    private fun signingSha1(context: Context): String? {
        val pm = context.packageManager
        val signature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            info.signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
                .signatures?.firstOrNull()
        } ?: return null
        return MessageDigest.getInstance("SHA-1")
            .digest(signature.toByteArray())
            .joinToString(":") { "%02X".format(it) }
    }

    companion object {
        const val CHANNEL = "com.system.calculator/maps_diagnostics"
    }
}
