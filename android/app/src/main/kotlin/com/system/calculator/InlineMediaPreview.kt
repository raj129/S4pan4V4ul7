package com.system.calculator

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageDecoder
import android.os.Build
import android.view.Gravity
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.TextureView
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.datasource.DataSource
import androidx.media3.ui.AspectRatioFrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.ByteBuffer
import java.util.concurrent.Executors

internal const val INLINE_MEDIA_VIEW_TYPE = "photo_vault/inline_media"

internal class InlineMediaPreviewFactory(
    private val messenger: BinaryMessenger,
    private val onCreated: (InlineMediaPreview) -> Unit,
    private val onDisposed: (InlineMediaPreview) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *> ?: emptyMap<Any, Any>()
        return InlineMediaPreview(
            context = context,
            viewId = viewId,
            messenger = messenger,
            parameters = parameters,
            onCreated = onCreated,
            onDisposed = onDisposed,
        )
    }
}

internal class InlineMediaPreview(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val parameters: Map<*, *>,
    private val onCreated: (InlineMediaPreview) -> Unit,
    private val onDisposed: (InlineMediaPreview) -> Unit,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val root = FrameLayout(context).apply { setBackgroundColor(Color.BLACK) }
    private val channel = MethodChannel(messenger, "$INLINE_MEDIA_VIEW_TYPE/$viewId")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val hostActivity = context.findActivity()
    private val previousColorMode = hostActivity?.window?.colorMode
    private val kind = parameters["kind"] as? String
    private var bytes = (parameters["bytes"] as? ByteArray)?.copyOf()
    private var loop = parameters["loop"] as? Boolean ?: false
    private var status = "loading"
    private var closed = false
    private var disposed = false
    private var image: ImageView? = null
    private var bitmap: Bitmap? = null
    private var player: ExoPlayer? = null
    private var textureView: TextureView? = null
    private var videoContainer: AspectRatioFrameLayout? = null
    private var source: ChatMemoryDataSource? = null

    init {
        channel.setMethodCallHandler(this)
        onCreated(this)
        when (kind) {
            "hdrImage" -> createHdrImage()
            "motionPhoto" -> createMotionPlayer()
            else -> setError("Unsupported inline media type.")
        }
    }

    override fun getView(): View = root

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(
                mapOf(
                    "status" to status,
                    "playing" to (player?.isPlaying == true),
                ),
            )
            "toggle" -> {
                val current = player
                if (current == null || closed) {
                    result.error("unavailable", "Inline video is unavailable.", null)
                } else {
                    if (current.isPlaying) {
                        current.pause()
                    } else {
                        if (current.playbackState == Player.STATE_ENDED) {
                            current.seekTo(0)
                        }
                        current.play()
                    }
                    result.success(null)
                }
            }
            "setLoop" -> {
                val current = player
                val next = call.argument<Boolean>("loop")
                if (current == null || next == null || closed) {
                    result.error("unavailable", "Inline video is unavailable.", null)
                } else {
                    loop = next
                    current.repeatMode = if (loop) {
                        Player.REPEAT_MODE_ONE
                    } else {
                        Player.REPEAT_MODE_OFF
                    }
                    if (loop && current.playbackState == Player.STATE_ENDED) {
                        status = "ready"
                        current.seekTo(0)
                        current.play()
                    }
                    result.success(null)
                }
            }
            "close" -> {
                close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun createHdrImage() {
        val sourceBytes = bytes
        val imageView = ImageView(context).apply {
            scaleType = if (parameters["fit"] == "cover") {
                ImageView.ScaleType.CENTER_CROP
            } else {
                ImageView.ScaleType.FIT_CENTER
            }
            setBackgroundColor(Color.BLACK)
        }
        image = imageView
        root.addView(
            imageView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        if (sourceBytes == null || sourceBytes.isEmpty()) {
            setError("HDR image is empty.")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            hostActivity?.window?.setColorMode(ActivityInfo.COLOR_MODE_HDR)
        }
        worker.execute {
            val decoded = try {
                decodeImage(sourceBytes)
            } catch (_: Exception) {
                null
            }
            main.post {
                if (closed || disposed) {
                    recycle(decoded)
                    sourceBytes.fill(0)
                } else if (decoded == null) {
                    sourceBytes.fill(0)
                    bytes = null
                    setError("HDR image could not be decoded.")
                } else {
                    bytes = null
                    sourceBytes.fill(0)
                    bitmap = decoded
                    imageView.setImageBitmap(decoded)
                    status = "ready"
                    notifyStatus()
                }
            }
        }
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun createMotionPlayer() {
        val sourceBytes = bytes
        if (sourceBytes == null || sourceBytes.isEmpty()) {
            setError("Motion Photo video is empty.")
            return
        }
        try {
            val memorySource = ChatMemoryDataSource(sourceBytes)
            source = memorySource
            val mediaSource = ProgressiveMediaSource.Factory(
                DataSource.Factory { ChatMedia3DataSource(memorySource) },
            ).createMediaSource(
                MediaItem.fromUri("chat-memory://inline-motion-photo"),
            )
            val playback = ExoPlayer.Builder(context).build()
            player = playback
            playback.repeatMode = if (loop) {
                Player.REPEAT_MODE_ONE
            } else {
                Player.REPEAT_MODE_OFF
            }
            playback.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    channel.invokeMethod("playingChanged", isPlaying)
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width > 0 && videoSize.height > 0) {
                        var aspectRatio =
                            videoSize.width * videoSize.pixelWidthHeightRatio /
                                videoSize.height
                        if (videoSize.unappliedRotationDegrees % 180 != 0) {
                            aspectRatio = 1f / aspectRatio
                        }
                        videoContainer?.setAspectRatio(
                            aspectRatio,
                        )
                    }
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_ENDED && !loop) {
                        status = "ended"
                        channel.invokeMethod("ended", null)
                    }
                }

                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    setError(error.message ?: "Motion Photo playback failed.")
                }
            })
            val view = TextureView(context).apply { keepScreenOn = true }
            val container = AspectRatioFrameLayout(context).apply {
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
            }
            textureView = view
            videoContainer = container
            root.addView(
                container,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                ),
            )
            playback.setVideoTextureView(view)
            playback.setMediaSource(mediaSource)
            playback.prepare()
            playback.playWhenReady = true
            status = "ready"
            notifyStatus()
        } catch (error: Exception) {
            setError(error.message ?: "Motion Photo playback is unavailable.")
        }
    }

    private fun decodeImage(data: ByteArray): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                return ImageDecoder.decodeBitmap(
                    ImageDecoder.createSource(ByteBuffer.wrap(data)),
                )
            } catch (_: Exception) {
                // Older/unsupported HDR formats use the platform's SDR fallback.
            }
        }
        return BitmapFactory.decodeByteArray(data, 0, data.size)
    }

    private fun setError(message: String) {
        status = "error"
        channel.invokeMethod("statusChanged", mapOf("status" to status, "message" to message))
    }

    private fun notifyStatus() {
        channel.invokeMethod(
            "statusChanged",
            mapOf("status" to status, "playing" to (player?.isPlaying == true)),
        )
    }

    private fun recycle(value: Bitmap?) {
        if (value != null && value.config != Bitmap.Config.HARDWARE && !value.isRecycled) {
            value.recycle()
        }
    }

    fun close() {
        if (closed) return
        closed = true
        status = "closed"
        channel.invokeMethod("statusChanged", mapOf("status" to status))
        textureView?.let { player?.clearVideoTextureView(it) }
        textureView = null
        videoContainer = null
        player?.release()
        player = null
        source?.close()
        source = null
        bytes?.fill(0)
        bytes = null
        image?.setImageDrawable(null)
        image = null
        recycle(bitmap)
        bitmap = null
        if (kind == "hdrImage" &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            previousColorMode != null) {
            hostActivity?.window?.setColorMode(previousColorMode)
        }
        root.removeAllViews()
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        close()
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
        onDisposed(this)
    }
}

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return current as? Activity
}
