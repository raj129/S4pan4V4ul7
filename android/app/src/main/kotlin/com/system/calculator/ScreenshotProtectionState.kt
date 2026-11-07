package com.system.calculator

import android.view.Window
import android.view.WindowManager

internal object ScreenshotProtectionState {
    @Volatile
    var enabled = true
        private set

    fun setEnabled(window: Window, value: Boolean) {
        enabled = value
        applyTo(window)
    }

    fun applyTo(window: Window?) {
        if (enabled) {
            window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
