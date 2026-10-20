package com.system.calculator

import android.Manifest
import android.app.Activity
import android.app.Application
import android.app.Dialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.*
import android.os.storage.StorageManager
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import android.view.WindowManager
import android.widget.*
import com.google.firebase.auth.FirebaseAuth
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** All chat-created persistence is ciphertext. Viewing/capture are in-app and
 * stopped on background/detach. No external OPEN intent or plaintext staging. */
class ChatSecureMediaPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener,
    Application.ActivityLifecycleCallbacks {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var pendingPicker: MethodChannel.Result? = null
    private var pendingPickerAccountEpoch = 0
    private var pendingPickerUid: String? = null
    private var permissionResult: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var viewer: Dialog? = null
    private var viewerCleanup: (() -> Unit)? = null
    private var recorder: ChatEncryptedRecorder? = null
    private var recordingBusy = false
    private var recordingEpoch = 0
    private var camera: ChatMemoryCamera? = null
    @Volatile private var generation = 0
    @Volatile private var engineAttached = false
    private val sourceAccountEpoch = AtomicInteger()
    private val sourceAuthListener = FirebaseAuth.AuthStateListener {
        sourceAccountEpoch.incrementAndGet()
    }
    private var active = false
    private val audioFocus = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0) main.post { cancelRecording() }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "photo_vault/chat_secure_media")
        channel.setMethodCallHandler(this)
        engineAttached = true
        FirebaseAuth.getInstance().addAuthStateListener(sourceAuthListener)
        (context as Application).registerActivityLifecycleCallbacks(this)
        io.execute { ChatEncryptedRecorder.cleanAbandoned(context) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engineAttached = false
        FirebaseAuth.getInstance().removeAuthStateListener(sourceAuthListener)
        close()
        pendingPicker?.error("interrupted", "Acquisition interrupted.", null)
        pendingPicker = null
        channel.setMethodCallHandler(null)
        (context as Application).unregisterActivityLifecycleCallbacks(this)
        io.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        activity = binding.activity
        active = true
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    private fun detach() {
        active = false
        close()
        pendingPicker?.error("interrupted", "Acquisition interrupted.", null)
        pendingPicker = null
        binding?.removeActivityResultListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        activity = null
    }

    override fun onDetachedFromActivity() = detach()
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickAttachments" -> pick(call, result)
                "readSource", "releaseSourcePermission" -> sourceAction(call, result)
                "readContentUri" -> {
                    val uri = android.net.Uri.parse(call.argument<String>("uri") ?: "")
                    require(uri.scheme == "content")
                    val epoch = generation
                    background(result) {
                        val attachment = readUri(uri, ChatMemoryDataSource.MAX_BYTES)
                        if (epoch != generation) {
                            (attachment["bytes"] as ByteArray).fill(0)
                            throw IllegalStateException("Acquisition interrupted")
                        }
                        attachment
                    }
                }
                "capturePhoto" -> permission(Manifest.permission.CAMERA, result) { capture(result) }
                "startRecording" -> permission(Manifest.permission.RECORD_AUDIO, result) { startRecording(result) }
                "stopRecording" -> stopRecording(result)
                "pauseRecording", "resumeRecording" -> {
                    val current = recorder ?: throw IllegalStateException("Recording unavailable")
                    check(!recordingBusy && active)
                    recordingBusy = true
                    val epoch = recordingEpoch
                    io.execute {
                        try {
                            if (call.method == "pauseRecording") current.pause() else current.resume()
                            main.post {
                                recordingBusy = false
                                if (!active || epoch != recordingEpoch || recorder !== current) {
                                    result.error("interrupted", "Recording interrupted.", null)
                                } else {
                                    result.success(null)
                                }
                            }
                        } catch (_: Exception) {
                            main.post {
                                recordingBusy = false
                                result.error("unavailable", "Recording could not be paused or resumed.", null)
                            }
                        }
                    }
                }
                "recordingStatus" -> result.success(recorder?.status() ?: "interrupted")
                "cancelRecording" -> cancelRecording(result)
                "showAudio", "showVideo", "showPdf" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                    if (bytes.isEmpty() || bytes.size > ChatMemoryDataSource.MAX_BYTES) {
                        bytes.fill(0)
                        result.error("size_limit", "Attachment must be nonempty and below 64 MB.", null)
                    } else if (!active || activity == null) {
                        bytes.fill(0)
                        result.error("interrupted", "Open media while the app is active.", null)
                    } else if (call.method == "showPdf") {
                        showPdf(bytes, result)
                    } else {
                        if (call.method == "showVideo") showVideoPlayer(bytes, result, call.argument<Boolean>("measureStartup") == true)
                        else showAudioPlayer(bytes, result)
                    }
                }
                "close" -> { close(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: SecurityException) {
            result.error("permission_denied", "Access permission denied.", null)
        } catch (_: Exception) {
            result.error("unavailable", "Secure media unavailable.", null)
        }
    }

    private fun background(result: MethodChannel.Result, guard: (() -> Boolean)? = null, task: () -> Any?) {
        io.execute {
            try {
                val value = task()
                main.post {
                    try {
                        if (guard?.invoke() == false) result.error("interrupted", "Acquisition interrupted.", null)
                        else result.success(value)
                    } finally {
                        // StandardMethodCodec copies synchronously into the reply.
                        when (value) {
                            is Map<*, *> -> (value["bytes"] as? ByteArray)?.fill(0)
                            is List<*> -> value.forEach { (it as? Map<*, *>)?.get("bytes")?.let { b -> (b as? ByteArray)?.fill(0) } }
                        }
                    }
                }
            } catch (_: SizeLimitException) {
                main.post { result.error("size_limit", "Selected attachments exceed the 64 MB memory limit.", null) }
            } catch (_: SecurityException) {
                main.post { result.error("permission_denied", "Source permission denied. Select the file again.", null) }
            } catch (_: Exception) {
                main.post { result.error("unavailable", "Media interrupted, corrupt, or unsupported.", null) }
            }
        }
    }

    private fun permission(name: String, result: MethodChannel.Result, action: () -> Unit) {
        val host = activity
        if (host == null || !active) {
            result.error("interrupted", "Open media while the app is active.", null)
            return
        }
        if (host.checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED) {
            action()
        } else if (permissionResult != null) {
            result.error("busy", "Another permission request is active.", null)
        } else {
            permissionResult = result
            permissionAction = action
            host.requestPermissions(arrayOf(name), PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (code != PERMISSION_REQUEST) return false
        val result = permissionResult
        val action = permissionAction
        permissionResult = null
        permissionAction = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && active) {
            try { action?.invoke() } catch (_: Exception) { result?.error("unavailable", "Media unavailable.", null) }
        } else {
            val permanent = permissions.firstOrNull()?.let { activity?.shouldShowRequestPermissionRationale(it) == false } ?: false
            result?.error(if (permanent) "permission_permanently_denied" else "permission_denied",
                "Permission denied. Enable camera/microphone in Android Settings if needed.", null)
        }
        return true
    }

    private fun pick(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPicker != null) {
            result.error("busy", "A picker is already open.", null)
            return
        }
        val host = activity ?: throw IllegalStateException()
        val types = call.argument<List<String>>("mimeTypes") ?: listOf("*/*")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            type = types.singleOrNull() ?: "*/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
        }
        pendingPicker = result
        pendingPickerAccountEpoch = sourceAccountEpoch.get()
        pendingPickerUid = FirebaseAuth.getInstance().currentUser?.uid
        try { host.startActivityForResult(intent, PICK_REQUEST) }
        catch (e: Exception) { pendingPicker = null; throw e }
    }

    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != PICK_REQUEST) return false
        val result = pendingPicker ?: return true
        pendingPicker = null
        val accountEpoch = pendingPickerAccountEpoch
        val pickerUid = pendingPickerUid
        pendingPickerUid = null
        if (accountEpoch != sourceAccountEpoch.get() || FirebaseAuth.getInstance().currentUser?.uid != pickerUid) {
            result.error("interrupted", "Acquisition interrupted.", null)
            return true
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Any>())
            return true
        }
        val uris = mutableListOf<android.net.Uri>()
        val clip = data.clipData
        if (clip != null) {
            if (clip.itemCount > 20) {
                result.error("size_limit", "Select at most 20 attachments.", null)
                return true
            }
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else data.data?.let { uris.add(it) }
        val epoch = generation
        val grantFlags = data.flags
        background(result, guard = {
            engineAttached && epoch == generation && accountEpoch == sourceAccountEpoch.get() &&
                FirebaseAuth.getInstance().currentUser?.uid == pickerUid
        }) {
            val attachments = mutableListOf<Map<String, Any>>()
            var remaining = ChatMemoryDataSource.MAX_BYTES
            try {
                uris.forEach { uri ->
                    check(epoch == generation && accountEpoch == sourceAccountEpoch.get() &&
                        FirebaseAuth.getInstance().currentUser?.uid == pickerUid)
                    val flags = retainSourcePermission(uri, grantFlags)
                    val attachment = readUri(uri, remaining)
                    remaining -= (attachment["bytes"] as ByteArray).size
                    attachments.add(attachment + mapOf("sourceUri" to uri.toString(), "sourceFlags" to flags))
                }
                check(epoch == generation && accountEpoch == sourceAccountEpoch.get() &&
                    FirebaseAuth.getInstance().currentUser?.uid == pickerUid)
                attachments
            } catch (e: Exception) {
                attachments.forEach { (it["bytes"] as ByteArray).fill(0) }
                throw e
            }
        }
        return true
    }

    private fun readUri(uri: android.net.Uri, limit: Int): Map<String, Any> {
        require(uri.scheme == "content")
        val resolver = context.contentResolver
        var name = "attachment"
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeColumn >= 0 && !cursor.isNull(sizeColumn) && cursor.getLong(sizeColumn) > limit) throw SizeLimitException()
                val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameColumn >= 0) name = cursor.getString(nameColumn) ?: name
            }
        }
        val mimeType = resolver.getType(uri) ?: "application/octet-stream"
        // Unknown content lengths are bounded while streaming; never use paths.
        val input = resolver.openInputStream(uri) ?: throw FileNotFoundException()
        return readStream(input, name, mimeType, limit)
    }

    private fun readStream(input: InputStream, name: String, mimeType: String, limit: Int): Map<String, Any> {
        var attachment: Map<String, Any>? = null
        try {
            input.use { attachment = readAttachment(it, name, mimeType, limit) }
            return attachment!!
        } catch (error: Exception) {
            (attachment?.get("bytes") as? ByteArray)?.fill(0)
            throw error
        }
    }

    private fun readAttachment(input: InputStream, name: String, mimeType: String, limit: Int): Map<String, Any> {
        val output = WipingOutput()
        val buffer = ByteArray(16384)
        try {
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size() > limit - count) throw SizeLimitException()
                output.write(buffer, 0, count)
            }
            if (output.size() == 0) throw IOException("Empty attachment source")
            val safeName = name.substringAfterLast('/').substringAfterLast('\\')
                .filter { it >= ' ' && it != '\u007f' }.take(200).ifEmpty { "attachment" }
            return mapOf("bytes" to output.toByteArray(), "fileName" to safeName,
                "mimeType" to mimeType)
        } finally {
            buffer.fill(0)
            output.wipe()
        }
    }

    private fun persistedSourceFlags(uri: android.net.Uri): Int =
        if (context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission })
            Intent.FLAG_GRANT_READ_URI_PERMISSION else 0

    private fun retainSourcePermission(uri: android.net.Uri, flags: Int): Int {
        if (uri.scheme != "content") return 0
        if (flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0 &&
            flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0) {
            try {
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {
                android.util.Log.d("ChatSecureMedia", "Source provider did not retain read permission.")
            } catch (_: UnsupportedOperationException) {
                android.util.Log.d("ChatSecureMedia", "Source provider does not support retained permission.")
            } catch (_: IllegalArgumentException) {
                android.util.Log.d("ChatSecureMedia", "Source provider refused retained permission.")
            }
        }
        return try { persistedSourceFlags(uri) } catch (_: SecurityException) { 0 }
    }

    private fun sourceAction(call: MethodCall, result: MethodChannel.Result) {
        val uid = call.argument<String>("uid")
        if (uid.isNullOrBlank() || FirebaseAuth.getInstance().currentUser?.uid != uid) {
            result.error("account_changed", "Source account changed. Retry with the current account.", null)
            return
        }
        val rawUri = call.argument<String>("sourceUri") ?: ""
        val parsed = try { ChatOriginalSourcePolicy.validate(rawUri) } catch (_: Exception) {
            result.error("source_unavailable", "Original source reference is unavailable.", null)
            return
        }
        val requestedLimit = call.argument<Number>("maxBytes")?.toLong()
            ?: ChatMemoryDataSource.MAX_BYTES.toLong()
        if (requestedLimit <= 0 || requestedLimit > ChatMemoryDataSource.MAX_BYTES) {
            result.error("size_limit", "Original source exceeds the memory limit.", null)
            return
        }
        val epoch = generation
        val accountEpoch = sourceAccountEpoch.get()
        fun fenceFailure() = ChatOriginalSourcePolicy.fenceFailure(
            uid, FirebaseAuth.getInstance().currentUser?.uid, accountEpoch, sourceAccountEpoch.get(),
            engineAttached, epoch, generation)
        fun checkFence() {
            fenceFailure()?.let { throw SourceFenceException(it) }
        }
        io.execute {
            var value: Map<String, Any>? = null
            var errorCode: String? = null
            try {
                checkFence()
                val uri = android.net.Uri.parse(rawUri)
                if (call.method == "releaseSourcePermission") {
                    require(parsed.scheme == "content")
                    val flags = persistedSourceFlags(uri)
                    checkFence()
                    if (flags != 0) context.contentResolver.releasePersistableUriPermission(uri, flags)
                    value = mapOf("released" to (flags != 0), "sourceFlags" to persistedSourceFlags(uri))
                } else {
                    val attachment = if (parsed.scheme == "content") readUri(uri, requestedLimit.toInt()) else {
                        val file = ChatOriginalSourcePolicy.existingFile(parsed)
                        if (file.length() > requestedLimit) throw SizeLimitException()
                        val mime = android.webkit.MimeTypeMap.getSingleton()
                            .getMimeTypeFromExtension(file.extension.lowercase(java.util.Locale.ROOT))
                            ?: "application/octet-stream"
                        readStream(file.inputStream(), file.name, mime, requestedLimit.toInt())
                    }
                    value = attachment
                    val flags = if (parsed.scheme == "content") persistedSourceFlags(uri) else 0
                    value = attachment + mapOf("sourceUri" to rawUri, "sourceFlags" to flags)
                }
                checkFence()
            } catch (error: SourceFenceException) {
                errorCode = error.code
            } catch (_: SizeLimitException) {
                errorCode = "size_limit"
            } catch (_: SecurityException) {
                errorCode = "source_permission_denied"
            } catch (_: FileNotFoundException) {
                errorCode = "source_unavailable"
            } catch (_: IOException) {
                errorCode = "source_corrupt"
            } catch (_: IllegalArgumentException) {
                errorCode = "source_unavailable"
            } catch (error: Exception) {
                errorCode = "source_internal_error"
                android.util.Log.e("ChatSecureMedia", "Source operation failed: ${error.javaClass.simpleName}")
            }
            val response = value
            val failure = errorCode
            main.post {
                try {
                    val code = fenceFailure() ?: failure
                    if (code != null) {
                        val message = when (code) {
                            "account_changed" -> "Source account changed. Retry with the current account."
                            "cancelled" -> "Original source operation interrupted."
                            "source_permission_denied" -> "Original source permission denied. Select the file again."
                            "source_unavailable" -> "Original source is no longer available."
                            "size_limit" -> "Original source exceeds the memory limit."
                            "source_internal_error" -> "Original source could not be read. Please retry or report this error."
                            else -> "Original source is empty, corrupt, or unreadable."
                        }
                        result.error(code, message, null)
                    } else result.success(response)
                } finally {
                    (response?.get("bytes") as? ByteArray)?.fill(0)
                }
            }
        }
    }

    private fun startRecording(result: MethodChannel.Result) {
        if (recorder != null || recordingBusy) {
            result.error("busy", "A recording is already active.", null)
            return
        }
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        val focus = manager.requestAudioFocus(audioFocus, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        if (focus != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            result.error("interrupted", "Audio is in use by another app.", null)
            return
        }
        recordingBusy = true
        val epoch = ++recordingEpoch
        io.execute {
            var created: ChatEncryptedRecorder? = null
            try {
                created = ChatEncryptedRecorder(context)
                created.start()
                val ready = created
                main.post {
                    recordingBusy = false
                    if (!active || epoch != recordingEpoch) {
                        io.execute { ready.cancel() }
                        abandonFocus()
                        result.error("interrupted", "Recording interrupted.", null)
                    } else {
                        recorder = ready
                        result.success(null)
                    }
                }
            } catch (_: Exception) {
                var cleanupFailed = false
                try { created?.cancel() } catch (_: Exception) { cleanupFailed = true }
                main.post {
                    recordingBusy = false
                    abandonFocus()
                    val message = if (cleanupFailed) {
                        "Microphone unavailable; encrypted recording cleanup failed."
                    } else {
                        "Microphone unavailable."
                    }
                    result.error("unavailable", message, null)
                }
            }
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        val current = recorder
        if (current == null) {
            result.error("interrupted", "Recording was stopped or interrupted.", null)
            return
        }
        recorder = null
        recordingBusy = true
        val epoch = recordingEpoch
        abandonFocus()
        background(result) {
            try {
                val bytes = current.finish()
                if (epoch != recordingEpoch || !active) {
                    bytes.fill(0)
                    throw IllegalStateException()
                }
                mapOf("bytes" to bytes, "fileName" to "recording.wav", "mimeType" to "audio/wav")
            } finally { main.post { recordingBusy = false } }
        }
    }

    private fun cancelRecording(result: MethodChannel.Result? = null) {
        recordingEpoch++
        val current = recorder
        recorder = null
        abandonFocus()
        if (result != null) {
            recordingBusy = true
            background(result) {
                try { current?.cancel(); null }
                finally { main.post { recordingBusy = false } }
            }
        } else if (current != null) {
            io.execute {
                try { current.cancel() }
                catch (error: Exception) { android.util.Log.e("ChatSecureMedia", "Recording cleanup failed", error) }
            }
        }
    }

    private fun abandonFocus() {
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).abandonAudioFocus(audioFocus)
    }

    private fun capture(result: MethodChannel.Result) {
        if (camera != null || viewer != null) {
            result.error("busy", "Close the current viewer first.", null)
            return
        }
        val host = activity ?: throw IllegalStateException()
        camera = ChatMemoryCamera(host) { bytes, error ->
            camera = null
            if (error != null) result.error("unavailable", "Camera unavailable or interrupted.", null)
            else if (bytes == null) result.success(null)
            else {
                result.success(mapOf("bytes" to bytes, "fileName" to "capture.jpg", "mimeType" to "image/jpeg"))
                bytes.fill(0)
            }
        }
        camera!!.show()
    }

    private fun newDialog(): Pair<Dialog, LinearLayout> {
        val host = activity ?: throw IllegalStateException()
        val dialog = Dialog(host)
        val layout = LinearLayout(host).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            setPadding(16, 16, 16, 16)
        }
        dialog.setContentView(layout)
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        return Pair(dialog, layout)
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun showVideoPlayer(bytes: ByteArray, result: MethodChannel.Result, measureStartup: Boolean) {
        val openedAt = SystemClock.elapsedRealtime()
        val host = activity
        if (host == null || viewer != null || camera != null) {
            bytes.fill(0)
            result.error("busy", "Open media while the app is active and no viewer is open.", null)
            return
        }
        val source = ChatMemoryDataSource(bytes)
        var player: androidx.media3.exoplayer.ExoPlayer? = null
        var playerView: androidx.media3.ui.PlayerView? = null
        var replied = false
        val (dialog, layout) = newDialog()
        fun complete(error: Boolean) {
            if (replied) return
            replied = true
            if (error) result.error("unsupported", "Video is corrupt or not supported by Android.", null)
            else result.success(null)
        }
        viewer = dialog
        viewerCleanup = {
            playerView?.player = null
            try { player?.release() }
            finally { source.close(); complete(false) }
        }
        dialog.setOnDismissListener { if (viewer === dialog) releaseViewer() }
        try {
            val mediaSource = androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(
                androidx.media3.datasource.DataSource.Factory { ChatMedia3DataSource(source) }
            ).createMediaSource(androidx.media3.common.MediaItem.fromUri("chat-memory://video"))
            val playback = androidx.media3.exoplayer.ExoPlayer.Builder(host).build()
            player = playback
            val view = androidx.media3.ui.PlayerView(host).apply {
                resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                useController = true
                controllerShowTimeoutMs = 4000
                setShowBuffering(androidx.media3.ui.PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
                setShutterBackgroundColor(Color.BLACK)
                keepScreenOn = true
                this.player = playback
            }
            playerView = view
            layout.addView(view, LinearLayout.LayoutParams(-1, 0, 1f))
            layout.addView(Button(host).apply { text = "Close"; setOnClickListener { dialog.dismiss() } })
            playback.addListener(object : androidx.media3.common.Player.Listener {
                override fun onRenderedFirstFrame() {
                    if (measureStartup) {
                        android.util.Log.d("ChatMediaTiming", "stage=first-frame elapsedMs=${SystemClock.elapsedRealtime() - openedAt}")
                    }
                }
                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    if (viewer !== dialog) return
                    complete(true)
                    dialog.dismiss()
                }
            })
            playback.setMediaSource(mediaSource)
            playback.prepare()
            playback.playWhenReady = true
            dialog.show()
            dialog.window?.setLayout(-1, -1)
        } catch (error: Exception) {
            android.util.Log.e("ChatSecureMedia", "Secure video playback failed", error)
            complete(true)
            dialog.dismiss()
            releaseViewer()
        }
    }

    private fun showAudioPlayer(bytes: ByteArray, result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            bytes.fill(0)
            result.error("interrupted", "Media activity is unavailable.", null)
            return
        }
        if (viewer != null || camera != null) {
            bytes.fill(0)
            result.error("busy", "A viewer is already open.", null)
            return
        }
        val source = ChatMemoryDataSource(bytes)
        val player = MediaPlayer()
        val (dialog, layout) = newDialog()
        var prepared = false
        var finished = false
        var disposed = false
        val caption = TextView(host).apply { setTextColor(Color.WHITE); text = "Loading…" }
        val seek = SeekBar(host)
        val play = Button(host).apply { text = "Pause"; isEnabled = false }
        val tick = object : Runnable {
            override fun run() {
                if (disposed || !prepared) return
                try {
                    seek.progress = player.currentPosition
                    caption.text = "${player.currentPosition / 1000}s / ${player.duration / 1000}s"
                    main.postDelayed(this, 400)
                } catch (_: Exception) {}
            }
        }
        fun complete(error: Boolean) {
            if (finished) return
            finished = true
            if (error) result.error("unsupported", "Media is corrupt or not supported by Android.", null)
            else result.success(null)
        }
        viewer = dialog
        viewerCleanup = {
            disposed = true
            main.removeCallbacks(tick)
            try { player.release() } catch (_: Exception) {}
            source.close()
            complete(false)
        }
        dialog.setOnDismissListener { releaseViewer() }
        player.setOnErrorListener { _, _, _ ->
            complete(true)
            dialog.dismiss()
            true
        }
        player.setOnPreparedListener {
            if (!disposed) {
                prepared = true
                play.isEnabled = true
                seek.max = player.duration
                player.start()
                main.post(tick)
            }
        }
        player.setOnCompletionListener { play.text = "Play" }
        play.setOnClickListener {
            if (prepared && !disposed) {
                if (player.isPlaying) { player.pause(); play.text = "Play" }
                else { player.start(); play.text = "Pause" }
            }
        }
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser && prepared && !disposed) player.seekTo(progress)
            }
            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) {}
        })
        try {
            player.setDataSource(source)
            player.prepareAsync()
            layout.addView(caption)
            layout.addView(seek)
            layout.addView(play)
            layout.addView(Button(host).apply { text = "Close"; setOnClickListener { dialog.dismiss() } })
            dialog.show()
            dialog.window?.setLayout(-1, -2)
        } catch (_: Exception) {
            complete(true)
            releaseViewer()
            dialog.dismiss()
        }
    }

    private fun showPdf(bytes: ByteArray, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 26) {
            bytes.fill(0)
            result.error("unsupported", "Secure PDF preview requires Android 8 (API 26) or newer.", null)
            return
        }
        if (viewer != null || camera != null) {
            bytes.fill(0)
            result.error("busy", "A viewer is already open.", null)
            return
        }
        val source = ChatMemoryDataSource(bytes)
        val thread = HandlerThread("ChatMemoryPdf").apply { start() }
        var descriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var bitmap: Bitmap? = null
        var disposed = false
        var replied = false
        val (dialog, layout) = newDialog()
        val image = ImageView(activity).apply { setBackgroundColor(Color.WHITE) }
        val caption = TextView(activity).apply { setTextColor(Color.WHITE) }
        val buttons = LinearLayout(activity)
        val previous = Button(activity).apply { text = "Previous" }
        val next = Button(activity).apply { text = "Next" }
        var pageIndex = 0
        viewer = dialog
        viewerCleanup = {
            disposed = true
            image.setImageDrawable(null)
            bitmap?.recycle()
            try { renderer?.close() } catch (_: Exception) {}
            try { descriptor?.close() } catch (_: Exception) {}
            source.close()
            thread.quitSafely()
            if (!replied) { replied = true; result.success(null) }
        }
        dialog.setOnDismissListener { releaseViewer() }
        fun renderPage() {
            if (disposed) return
            try {
                val pdf = renderer ?: return
                pdf.openPage(pageIndex).use { page ->
                    // Bound the raster independently of a hostile page size.
                    val scale = minOf(1f, 1024f / maxOf(page.width, page.height))
                    val replacement = Bitmap.createBitmap(maxOf(1, (page.width * scale).toInt()),
                        maxOf(1, (page.height * scale).toInt()), Bitmap.Config.ARGB_8888)
                    replacement.eraseColor(Color.WHITE)
                    try { page.render(replacement, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY) }
                    catch (e: Exception) { replacement.recycle(); throw e }
                    image.setImageBitmap(replacement)
                    bitmap?.recycle()
                    bitmap = replacement
                    caption.text = "${pageIndex + 1} / ${pdf.pageCount}"
                    previous.isEnabled = pageIndex > 0
                    next.isEnabled = pageIndex + 1 < pdf.pageCount
                }
            } catch (_: Exception) {
                if (!replied) { replied = true; result.error("unsupported", "PDF is corrupt or unsupported.", null) }
                dialog.dismiss()
            }
        }
        try {
            val storage = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
            descriptor = storage.openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY,
                object : ProxyFileDescriptorCallback() {
                    override fun onGetSize(): Long = source.size
                    override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
                        val count = source.readAt(offset, data, 0, size)
                        return if (count < 0) 0 else count
                    }
                    override fun onWrite(offset: Long, size: Int, data: ByteArray): Int =
                        throw ErrnoException("write", OsConstants.EBADF)
                    override fun onRelease() {}
                }, Handler(thread.looper))
            renderer = PdfRenderer(descriptor)
            check(renderer.pageCount > 0)
            layout.addView(image, LinearLayout.LayoutParams(-1, 0, 1f))
            layout.addView(caption)
            buttons.addView(previous)
            buttons.addView(next)
            layout.addView(buttons)
            layout.addView(Button(activity).apply { text = "Close"; setOnClickListener { dialog.dismiss() } })
            previous.setOnClickListener { pageIndex--; renderPage() }
            next.setOnClickListener { pageIndex++; renderPage() }
            dialog.show()
            dialog.window?.setLayout(-1, -1)
            renderPage()
        } catch (_: Exception) {
            if (!replied) { replied = true; result.error("unsupported", "PDF is corrupt or unsupported.", null) }
            releaseViewer()
            dialog.dismiss()
        }
    }

    private fun releaseViewer() {
        val cleanup = viewerCleanup
        viewerCleanup = null
        viewer = null
        cleanup?.invoke()
    }

    private fun close() {
        generation++
        viewer?.dismiss()
        releaseViewer()
        camera?.close()
        camera = null
        cancelRecording()
        permissionResult?.error("interrupted", "Media interrupted.", null)
        permissionResult = null
        permissionAction = null
    }

    override fun onActivityStopped(activity: Activity) {
        if (activity == this.activity) { active = false; close() }
    }
    override fun onActivityResumed(activity: Activity) { if (activity == this.activity) active = true }
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}

    private class WipingOutput : ByteArrayOutputStream() {
        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            if (count + length > buf.size) {
                val previous = buf
                buf = previous.copyOf(maxOf(count + length, previous.size * 2))
                previous.fill(0)
            }
            super.write(bytes, offset, length)
        }
        fun wipe() { buf.fill(0); reset() }
    }
    private class SizeLimitException : Exception()
    private class SourceFenceException(val code: String) : Exception()
    companion object {
        private const val PICK_REQUEST = 48301
        private const val PERMISSION_REQUEST = 48302
    }
}
