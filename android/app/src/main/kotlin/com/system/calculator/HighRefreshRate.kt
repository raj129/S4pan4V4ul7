package com.system.calculator

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import java.util.WeakHashMap

internal data class DisplayModeCandidate(
    val modeId: Int,
    val physicalWidth: Int,
    val physicalHeight: Int,
    val refreshRate: Float,
)

internal fun selectBestMode(
    currentWidth: Int,
    currentHeight: Int,
    modes: List<DisplayModeCandidate>,
): DisplayModeCandidate? =
    modes
        .filter { it.physicalWidth == currentWidth && it.physicalHeight == currentHeight }
        .maxByOrNull { it.refreshRate }

/**
 * Requests the highest refresh rate (e.g. 90/120 Hz) the panel supports at the
 * current resolution. On Android 11+ (including LTPO / Adaptive Refresh Rate
 * panels), also hints the underlying SurfaceView's Surface frame rate so
 * SurfaceFlinger keeps rendering at the high refresh rate.
 */
object HighRefreshRate {
    private const val TAG = "HighRefreshRate"
    private val surfaceCallbacks = WeakHashMap<SurfaceView, FrameRateSurfaceCallback>()

    fun apply(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val display = currentDisplay(activity) ?: return
            val current = display.mode
            val candidates = display.supportedModes.map {
                DisplayModeCandidate(
                    modeId = it.modeId,
                    physicalWidth = it.physicalWidth,
                    physicalHeight = it.physicalHeight,
                    refreshRate = it.refreshRate,
                )
            }
            val best = selectBestMode(
                currentWidth = current.physicalWidth,
                currentHeight = current.physicalHeight,
                modes = candidates,
            ) ?: return

            val window = activity.window ?: return
            val params = window.attributes
            if (params.preferredDisplayModeId != best.modeId ||
                params.preferredRefreshRate != best.refreshRate
            ) {
                params.preferredDisplayModeId = best.modeId
                params.preferredRefreshRate = best.refreshRate
                window.attributes = params
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val decorView = window.decorView
                val surfaceView = findSurfaceView(decorView)
                if (surfaceView != null) {
                    ensureSurfaceFrameRate(surfaceView, best.refreshRate)
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Unable to request high refresh rate", t)
        }
    }

    fun registerDisplayListener(activity: Activity): DisplayManager.DisplayListener? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return null
        val listener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) {
                apply(activity)
            }

            override fun onDisplayRemoved(displayId: Int) {}

            override fun onDisplayChanged(displayId: Int) {
                apply(activity)
            }
        }
        displayManager.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
        return listener
    }

    fun unregisterDisplayListener(
        activity: Activity,
        listener: DisplayManager.DisplayListener?,
    ) {
        if (listener == null) return
        val displayManager =
            activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return
        displayManager.unregisterDisplayListener(listener)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun ensureSurfaceFrameRate(surfaceView: SurfaceView, refreshRate: Float) {
        val existing = surfaceCallbacks[surfaceView]
        if (existing != null) {
            existing.targetRefreshRate = refreshRate
        } else {
            val callback = FrameRateSurfaceCallback(refreshRate)
            surfaceCallbacks[surfaceView] = callback
            surfaceView.holder.addCallback(callback)
        }
        applySurfaceFrameRate(surfaceView.holder.surface, refreshRate)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun applySurfaceFrameRate(surface: Surface?, refreshRate: Float) {
        if (surface == null || !surface.isValid) return
        val strategy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Surface.CHANGE_FRAME_RATE_ALWAYS
        } else {
            Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
        }
        surface.setFrameRate(
            refreshRate,
            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
            strategy,
        )
    }

    private class FrameRateSurfaceCallback(
        @Volatile var targetRefreshRate: Float,
    ) : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                applySurfaceFrameRate(holder.surface, targetRefreshRate)
            }
        }

        override fun surfaceChanged(
            holder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                applySurfaceFrameRate(holder.surface, targetRefreshRate)
            }
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {}
    }

    private fun findSurfaceView(view: View?): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findSurfaceView(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(activity: Activity): Display? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.let { return it }
            val dm = activity.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
            return dm?.getDisplay(Display.DEFAULT_DISPLAY)
        }
        return activity.windowManager.defaultDisplay
    }
}
