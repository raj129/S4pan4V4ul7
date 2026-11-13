package com.system.calculator

import android.os.Bundle
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep screenshots blocked until Flutter applies the persisted preference.
        ScreenshotProtectionState.applyTo(window)
        HighRefreshRate.apply(this)
    }

    override fun onResume() {
        super.onResume()
        // Some OEMs reset the preferred mode when the window loses focus.
        HighRefreshRate.apply(this)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREENSHOT_PROTECTION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val enabled = call.argument<Boolean>("enabled")
            if (enabled == null) {
                result.error("invalid_argument", "Expected an enabled boolean.", null)
                return@setMethodCallHandler
            }
            ScreenshotProtectionState.setEnabled(window, enabled)
            result.success(null)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HDR_PREVIEW_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "isSupported") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val display = window.decorView.display
            val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                display?.hdrCapabilities?.supportedHdrTypes?.isNotEmpty() == true
            result.success(supported)
        }
        flutterEngine.plugins.add(ChatSecureMediaPlugin())
        flutterEngine.plugins.add(ChatUploadPlugin())
        flutterEngine.plugins.add(MapsDiagnosticsPlugin())
        flutterEngine.plugins.add(MockLocationPlugin())
        flutterEngine.plugins.add(BatteryPlugin())
        flutterEngine.plugins.add(CallLogPlugin())
    }

    private companion object {
        const val SCREENSHOT_PROTECTION_CHANNEL =
            "com.system.calculator/screenshot_protection"
        const val HDR_PREVIEW_CHANNEL = "photo_vault/hdr_preview"
    }
}
