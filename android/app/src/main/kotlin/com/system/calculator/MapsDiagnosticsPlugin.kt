package com.system.calculator

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Debug-only report of what the installed APK presents to Google Maps: the
 * manifest key (masked), package name and signing certificate SHA-1. Release
 * builds only report whether a key is present.
 */
class MapsDiagnosticsPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                if (call.method != "report") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(report(context))
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
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
