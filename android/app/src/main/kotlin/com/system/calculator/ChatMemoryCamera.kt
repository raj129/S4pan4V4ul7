package com.system.calculator

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import android.view.TextureView
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Camera2 JPEG output stays in ImageReader/byte memory, never a file URI. */
internal class ChatMemoryCamera(
    private val activity: Activity,
    private val completed: (ByteArray?, Throwable?) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("ChatMemoryCamera").apply { start() }
    private val handler = Handler(thread.looper)
    private val dialog = Dialog(activity)
    private val preview = TextureView(activity)
    private val capture = Button(activity).apply { text = "Capture"; isEnabled = false }
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var surface: Surface? = null
    @Volatile private var closed = false
    private var orientation = 0
    private var finishing = false
    private val timeout = Runnable { finish(null, IllegalStateException("Camera timed out")) }

    fun show() {
        val layout = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        layout.addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
        layout.addView(TextView(activity).apply { text = "Photo capture stays inside this app." })
        layout.addView(capture)
        layout.addView(Button(activity).apply { text = "Cancel"; setOnClickListener { close() } })
        dialog.setContentView(layout)
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        dialog.setOnDismissListener { if (!closed) finish(null, null) }
        capture.setOnClickListener {
            capture.isEnabled = false
            handler.post {
                try {
                    val camera = device ?: throw IllegalStateException()
                    val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                        addTarget(reader!!.surface)
                        set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                        set(CaptureRequest.JPEG_ORIENTATION, orientation)
                    }
                    session!!.capture(request.build(), null, handler)
                    main.postDelayed(timeout, 15000)
                } catch (e: Exception) { main.post { finish(null, e) } }
            }
        }
        preview.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) { open(texture) }
            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {}
            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean { close(); return true }
            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
        }
        dialog.show()
        dialog.window?.setLayout(-1, -1)
        main.postDelayed(timeout, 20000)
    }

    @Suppress("MissingPermission")
    private fun open(texture: SurfaceTexture) {
        try {
            val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = manager.cameraIdList.firstOrNull {
                manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: manager.cameraIdList.first()
            val characteristics = manager.getCameraCharacteristics(id)
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: throw IllegalStateException()
            // Avoid unbounded sensor images; 2 MP is sufficient for attachments.
            val jpeg = map.getOutputSizes(ImageFormat.JPEG)
                .filter { it.width.toLong() * it.height <= 2_100_000 }
                .maxByOrNull { it.width.toLong() * it.height } ?: throw IllegalStateException()
            val previewSize = map.getOutputSizes(SurfaceTexture::class.java)
                .filter { it.width <= 1920 && it.height <= 1920 }
                .minByOrNull { kotlin.math.abs(it.width.toFloat() / it.height - jpeg.width.toFloat() / jpeg.height) }
                ?: throw IllegalStateException()
            texture.setDefaultBufferSize(previewSize.width, previewSize.height)
            surface = Surface(texture)
            val sensor = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            @Suppress("DEPRECATION")
            val rotation = when (activity.windowManager.defaultDisplay.rotation) {
                Surface.ROTATION_90 -> 90
                Surface.ROTATION_180 -> 180
                Surface.ROTATION_270 -> 270
                else -> 0
            }
            orientation = (sensor - rotation + 360) % 360
            reader = ImageReader.newInstance(jpeg.width, jpeg.height, ImageFormat.JPEG, 1).apply {
                setOnImageAvailableListener({ source ->
                    try {
                        val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                        val bytes = image.use {
                            val buffer = it.planes[0].buffer
                            require(buffer.remaining() in 1..ChatMemoryDataSource.MAX_BYTES)
                            ByteArray(buffer.remaining()).also { output -> buffer.get(output) }
                        }
                        main.post {
                            if (closed) bytes.fill(0) else finish(bytes, null)
                        }
                    } catch (e: Exception) { main.post { finish(null, e) } }
                }, handler)
            }
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    if (closed) { camera.close(); return }
                    device = camera
                    try {
                        @Suppress("DEPRECATION")
                        camera.createCaptureSession(listOf(surface!!, reader!!.surface),
                            object : CameraCaptureSession.StateCallback() {
                                override fun onConfigured(configured: CameraCaptureSession) {
                                    if (closed) { configured.close(); return }
                                    session = configured
                                    try {
                                        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                            addTarget(surface!!)
                                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                        }
                                        configured.setRepeatingRequest(request.build(), null, handler)
                                        main.post {
                                            main.removeCallbacks(timeout)
                                            if (!closed) capture.isEnabled = true
                                        }
                                    } catch (e: Exception) { main.post { finish(null, e) } }
                                }
                                override fun onConfigureFailed(session: CameraCaptureSession) {
                                    main.post { finish(null, IllegalStateException()) }
                                }
                            }, handler)
                    } catch (e: Exception) { main.post { finish(null, e) } }
                }
                override fun onDisconnected(camera: CameraDevice) { camera.close(); main.post { finish(null, IllegalStateException()) } }
                override fun onError(camera: CameraDevice, error: Int) { camera.close(); main.post { finish(null, IllegalStateException()) } }
            }, handler)
        } catch (e: Exception) { finish(null, e) }
    }

    private fun finish(bytes: ByteArray?, error: Throwable?) {
        if (closed || finishing) { bytes?.fill(0); return }
        finishing = true
        closed = true
        main.removeCallbacks(timeout)
        capture.isEnabled = false
        // Serial teardown with camera callbacks avoids closing ImageReader
        // while its JPEG is being copied on the camera thread.
        handler.post {
            try { session?.close() } catch (_: Exception) {}
            try { device?.close() } catch (_: Exception) {}
            try { reader?.close() } catch (_: Exception) {}
            surface?.release()
            session = null
            device = null
            reader = null
            surface = null
            thread.quitSafely()
            main.post {
                dialog.dismiss()
                completed(bytes, error)
            }
        }
    }

    fun close() = finish(null, null)
}
