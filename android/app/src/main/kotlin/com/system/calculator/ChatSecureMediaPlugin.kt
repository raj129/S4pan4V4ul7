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
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.ColorDrawable
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaMetadataRetriever
import android.os.*
import android.os.storage.StorageManager
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
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
                "extractVideoMetadata" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                    background(result) {
                        extractVideoMetadata(bytes)
                    }
                }
                "compressVideo" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                    val targetHeight = call.argument<Number>("targetHeight")?.toInt() ?: 720
                    val targetBitrate = call.argument<Number>("targetBitrate")?.toInt() ?: 1200000
                    background(result) {
                        compressVideo(bytes, targetHeight, targetBitrate)
                    }
                }
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

    private fun extractVideoMetadata(bytes: ByteArray): Map<String, Any?> {
        val source = ChatMemoryDataSource(bytes)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(source)
            val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val rawW = widthStr?.toIntOrNull() ?: 0
            val rawH = heightStr?.toIntOrNull() ?: 0
            val rotation = rotationStr?.toIntOrNull() ?: 0
            val durationMs = durationStr?.toIntOrNull() ?: 0
            val isRotated = rotation == 90 || rotation == 270
            val width = if (isRotated) rawH else rawW
            val height = if (isRotated) rawW else rawH

            val frame = retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0)
            var thumbBytes: ByteArray? = null
            if (frame != null) {
                val maxDim = 320
                val fw = frame.width
                val fh = frame.height
                val scale = minOf(1.0f, maxDim.toFloat() / maxOf(fw, fh))
                val targetW = maxOf(1, (fw * scale).toInt())
                val targetH = maxOf(1, (fh * scale).toInt())
                val scaled = Bitmap.createScaledBitmap(frame, targetW, targetH, true)
                val out = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 70, out)
                thumbBytes = out.toByteArray()
                if (scaled !== frame) scaled.recycle()
                frame.recycle()
            }
            return mapOf(
                "width" to width,
                "height" to height,
                "durationMs" to durationMs,
                "thumbnail" to thumbBytes
            )
        } catch (_: Exception) {
            return mapOf("width" to 0, "height" to 0, "durationMs" to 0, "thumbnail" to null)
        } finally {
            try { retriever.release() } catch (_: Exception) {}
            source.close()
        }
    }

    private fun compressVideo(bytes: ByteArray, targetHeight: Int, targetBitrate: Int): Map<String, Any?> {
        val meta = extractVideoMetadata(bytes)
        val origW = (meta["width"] as? Number)?.toInt() ?: 0
        val origH = (meta["height"] as? Number)?.toInt() ?: 0
        if (origH <= targetHeight && bytes.size < 8 * 1024 * 1024) {
            return meta + mapOf("bytes" to bytes)
        }

        val inputFile = java.io.File.createTempFile("chat_vid_in", ".mp4", context.cacheDir)
        val outputFile = java.io.File.createTempFile("chat_vid_out", ".mp4", context.cacheDir)
        try {
            inputFile.writeBytes(bytes)
            val latch = java.util.concurrent.CountDownLatch(1)
            var errorOccurred: Throwable? = null

            val scale = minOf(1.0f, targetHeight.toFloat() / maxOf(1, origH))
            val targetWidth = (maxOf(2, (origW * scale).toInt()) / 2) * 2
            val actualTargetHeight = (maxOf(2, (origH * scale).toInt()) / 2) * 2

            main.post {
                try {
                    val mediaItem = androidx.media3.common.MediaItem.fromUri(android.net.Uri.fromFile(inputFile))
                    val editedItem = androidx.media3.transformer.EditedMediaItem.Builder(mediaItem)
                        .setEffects(androidx.media3.transformer.Effects(
                            emptyList(),
                            listOf(androidx.media3.effect.Presentation.createForWidthAndHeight(
                                targetWidth, actualTargetHeight, androidx.media3.effect.Presentation.LAYOUT_SCALE_TO_FIT
                            ))
                        ))
                        .build()

                    val transformer = androidx.media3.transformer.Transformer.Builder(context)
                        .setVideoMimeType(androidx.media3.common.MimeTypes.VIDEO_H264)
                        .addListener(object : androidx.media3.transformer.Transformer.Listener {
                            override fun onCompleted(composition: androidx.media3.transformer.Composition, result: androidx.media3.transformer.ExportResult) {
                                latch.countDown()
                            }
                            override fun onError(composition: androidx.media3.transformer.Composition, result: androidx.media3.transformer.ExportResult, exception: androidx.media3.transformer.ExportException) {
                                errorOccurred = exception
                                latch.countDown()
                            }
                        })
                        .build()

                    outputFile.delete()
                    transformer.start(editedItem, outputFile.absolutePath)
                } catch (t: Throwable) {
                    errorOccurred = t
                    latch.countDown()
                }
            }

            val completed = latch.await(60, java.util.concurrent.TimeUnit.SECONDS)
            if (completed && errorOccurred == null && outputFile.exists() && outputFile.length() > 0 && outputFile.length() < bytes.size) {
                val compressedBytes = outputFile.readBytes()
                val updatedMeta = extractVideoMetadata(compressedBytes)
                return updatedMeta + mapOf("bytes" to compressedBytes)
            }
        } catch (_: Exception) {
            // Fallback to original bytes
        } finally {
            if (inputFile.exists()) inputFile.delete()
            if (outputFile.exists()) outputFile.delete()
        }

        return meta + mapOf("bytes" to bytes)
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

        val dialog = Dialog(host, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

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

        val root = FrameLayout(host).apply {
            setBackgroundColor(Color.BLACK)
        }
        dialog.setContentView(root)

        val density = host.resources.displayMetrics.density
        fun dp(v: Float) = (v * density).toInt()

        try {
            val mediaSource = androidx.media3.exoplayer.source.ProgressiveMediaSource.Factory(
                androidx.media3.datasource.DataSource.Factory { ChatMedia3DataSource(source) }
            ).createMediaSource(androidx.media3.common.MediaItem.fromUri("chat-memory://video"))
            val playback = androidx.media3.exoplayer.ExoPlayer.Builder(host).build()
            player = playback
            val view = androidx.media3.ui.PlayerView(host).apply {
                resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                useController = true
                controllerShowTimeoutMs = 3500
                setShowBuffering(androidx.media3.ui.PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
                setShutterBackgroundColor(Color.BLACK)
                keepScreenOn = true
                this.player = playback
            }
            playerView = view
            root.addView(view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

            val topBar = LinearLayout(host).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16f), dp(16f), dp(16f), dp(16f))
                val topGrad = GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    intArrayOf(0xCC000000.toInt(), 0x00000000)
                )
                background = topGrad
            }

            val backBtn = TextView(host).apply {
                text = "←"
                textSize = 24f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                val backBg = GradientDrawable().apply {
                    setColor(0x44000000)
                    cornerRadius = dp(20f).toFloat()
                }
                background = backBg
                setOnClickListener { dialog.dismiss() }
            }
            val backParams = LinearLayout.LayoutParams(dp(40f), dp(40f))

            val videoTitle = TextView(host).apply {
                text = "Video"
                textSize = 17f
                setTextColor(Color.WHITE)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                setPadding(dp(16f), 0, 0, 0)
            }
            val titleParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

            topBar.addView(backBtn, backParams)
            topBar.addView(videoTitle, titleParams)

            val topBarParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
            root.addView(topBar, topBarParams)

            view.setControllerVisibilityListener(androidx.media3.ui.PlayerView.ControllerVisibilityListener { visibility ->
                topBar.visibility = visibility
            })

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
        val dialog = Dialog(host)
        dialog.window?.apply {
            addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setDimAmount(0.6f)
            setGravity(Gravity.BOTTOM)
        }

        val density = host.resources.displayMetrics.density
        fun dp(v: Float) = (v * density).toInt()

        val cardBg = GradientDrawable().apply {
            setColor(0xFF1E1F2B.toInt())
            cornerRadii = floatArrayOf(
                dp(28f).toFloat(), dp(28f).toFloat(),
                dp(28f).toFloat(), dp(28f).toFloat(),
                0f, 0f, 0f, 0f
            )
        }

        val layout = LinearLayout(host).apply {
            orientation = LinearLayout.VERTICAL
            background = cardBg
            setPadding(dp(20f), dp(16f), dp(20f), dp(24f))
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }
        dialog.setContentView(layout)

        var prepared = false
        var finished = false
        var disposed = false
        var speedIndex = 0
        val speeds = floatArrayOf(1.0f, 1.5f, 2.0f)

        val dragHandle = View(host).apply {
            val bg = GradientDrawable().apply {
                setColor(0x33FFFFFF)
                cornerRadius = dp(2f).toFloat()
            }
            background = bg
        }
        val handleParams = LinearLayout.LayoutParams(dp(36f), dp(4f)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            bottomMargin = dp(12f)
        }
        layout.addView(dragHandle, handleParams)

        val headerRow = LinearLayout(host).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val titleView = TextView(host).apply {
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            text = "Voice Message"
        }
        val closeBtn = TextView(host).apply {
            text = "✕"
            textSize = 16f
            setTextColor(0xFFB0B5C6.toInt())
            gravity = Gravity.CENTER
            val btnBg = GradientDrawable().apply {
                setColor(0xFF2B2C3D.toInt())
                cornerRadius = dp(16f).toFloat()
            }
            background = btnBg
            setOnClickListener { dialog.dismiss() }
        }
        val titleParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        val closeParams = LinearLayout.LayoutParams(dp(32f), dp(32f))
        headerRow.addView(titleView, titleParams)
        headerRow.addView(closeBtn, closeParams)
        layout.addView(headerRow)

        val seek = SeekBar(host).apply {
            progressTintList = android.content.res.ColorStateList.valueOf(0xFF7C4DFF.toInt())
            thumbTintList = android.content.res.ColorStateList.valueOf(0xFF7C4DFF.toInt())
        }
        val seekParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(14f)
        }
        layout.addView(seek, seekParams)

        val timeRow = LinearLayout(host).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val elapsedText = TextView(host).apply {
            setTextColor(0xFFA5ADCB.toInt())
            textSize = 12f
            text = "0:00"
        }
        val durationText = TextView(host).apply {
            setTextColor(0xFFA5ADCB.toInt())
            textSize = 12f
            text = "--:--"
            gravity = Gravity.END
        }
        timeRow.addView(elapsedText, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        timeRow.addView(durationText, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        layout.addView(timeRow)

        val controlsRow = LinearLayout(host).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val speedBtn = TextView(host).apply {
            text = "1.0x"
            textSize = 13f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            val sBg = GradientDrawable().apply {
                setColor(0xFF2B2C3D.toInt())
                cornerRadius = dp(14f).toFloat()
            }
            background = sBg
        }
        val speedParams = LinearLayout.LayoutParams(dp(54f), dp(32f))

        val playFab = ImageButton(host).apply {
            setImageResource(android.R.drawable.ic_media_play)
            setColorFilter(Color.WHITE)
            val fabBg = GradientDrawable().apply {
                setColor(0xFF6366F1.toInt())
                shape = GradientDrawable.OVAL
            }
            background = fabBg
            isEnabled = false
            elevation = dp(4f).toFloat()
        }
        val playParams = LinearLayout.LayoutParams(dp(56f), dp(56f)).apply {
            leftMargin = dp(16f)
        }

        speedBtn.setOnClickListener {
            if (prepared && !disposed && Build.VERSION.SDK_INT >= 23) {
                speedIndex = (speedIndex + 1) % speeds.size
                val s = speeds[speedIndex]
                speedBtn.text = "${s}x"
                try {
                    player.playbackParams = player.playbackParams.setSpeed(s)
                } catch (_: Exception) {}
            }
        }

        fun formatTime(ms: Int): String {
            val totalSec = ms / 1000
            val min = totalSec / 60
            val sec = totalSec % 60
            return "%d:%02d".format(min, sec)
        }

        val tick = object : Runnable {
            override fun run() {
                if (disposed || !prepared) return
                try {
                    seek.progress = player.currentPosition
                    elapsedText.text = formatTime(player.currentPosition)
                    durationText.text = formatTime(player.duration)
                    main.postDelayed(this, 300)
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
                playFab.isEnabled = true
                playFab.setImageResource(android.R.drawable.ic_media_pause)
                seek.max = player.duration
                durationText.text = formatTime(player.duration)
                player.start()
                main.post(tick)
            }
        }

        player.setOnCompletionListener {
            playFab.setImageResource(android.R.drawable.ic_media_play)
        }

        playFab.setOnClickListener {
            if (prepared && !disposed) {
                if (player.isPlaying) {
                    player.pause()
                    playFab.setImageResource(android.R.drawable.ic_media_play)
                } else {
                    player.start()
                    playFab.setImageResource(android.R.drawable.ic_media_pause)
                }
            }
        }

        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser && prepared && !disposed) {
                    player.seekTo(progress)
                    elapsedText.text = formatTime(progress)
                }
            }
            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) {}
        })

        controlsRow.addView(speedBtn, speedParams)
        controlsRow.addView(playFab, playParams)
        val controlsParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = dp(16f)
        }
        layout.addView(controlsRow, controlsParams)

        try {
            player.setDataSource(source)
            player.prepareAsync()
            dialog.show()
            dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
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
