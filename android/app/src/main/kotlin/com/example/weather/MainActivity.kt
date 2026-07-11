package com.example.weather

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent vault content appearing in the Android app switcher or being
        // captured in screenshots. This mirrors Flutter's secure_application approach.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
