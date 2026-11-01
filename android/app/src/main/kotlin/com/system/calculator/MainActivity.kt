package com.system.calculator

import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent vault content appearing in the Android app switcher or being
        // captured in screenshots. This mirrors Flutter's secure_application approach.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        HighRefreshRate.apply(this)
    }

    override fun onResume() {
        super.onResume()
        // Some OEMs reset the preferred mode when the window loses focus.
        HighRefreshRate.apply(this)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ChatSecureMediaPlugin())
        flutterEngine.plugins.add(ChatUploadPlugin())
        flutterEngine.plugins.add(MapsDiagnosticsPlugin())
        flutterEngine.plugins.add(MockLocationPlugin())
        flutterEngine.plugins.add(ArrivalGeofencePlugin())
        flutterEngine.plugins.add(BatteryPlugin())
    }
}
