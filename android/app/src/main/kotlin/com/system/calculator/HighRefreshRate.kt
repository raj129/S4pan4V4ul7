package com.system.calculator

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.Display

/**
 * Requests the highest refresh rate (e.g. 90/120 Hz) the panel supports at the
 * current resolution. Flutter follows the display vsync, so once the window
 * asks for a faster mode the engine renders at that rate automatically.
 */
object HighRefreshRate {
    private const val TAG = "HighRefreshRate"

    fun apply(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val display = currentDisplay(activity) ?: return
            val current = display.mode
            val best = display.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            val window = activity.window
            val params = window.attributes
            if (params.preferredDisplayModeId == best.modeId &&
                params.preferredRefreshRate == best.refreshRate
            ) {
                return
            }
            params.preferredDisplayModeId = best.modeId
            params.preferredRefreshRate = best.refreshRate
            window.attributes = params
        } catch (t: Throwable) {
            Log.w(TAG, "Unable to request high refresh rate", t)
        }
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(activity: Activity): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            activity.windowManager.defaultDisplay
        }
}
