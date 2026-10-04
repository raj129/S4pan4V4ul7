package com.system.calculator

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** PCM is encoded as WAV only in memory at finalization. Each disk chunk is
 * authenticated independently; sequence AAD prevents reorder/truncation. */
internal class ChatEncryptedRecorder(context: Context) {
    private val dir = File(context.noBackupFilesDir, "chat_recordings").apply { mkdirs() }
    private val file = File(dir, "spool-${java.util.UUID.randomUUID()}")
    private val key: SecretKey = loadKey()
    private val running = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val pauseGate = Object()
    @Volatile private var paused = false
    @Volatile private var revision = 0
    private var audio: AudioRecord? = null
    private var worker: Thread? = null
    @Volatile private var error: Throwable? = null
    @Volatile private var pcmBytes = 0

    fun start() {
        val minimum = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Microphone unavailable" }
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum, CHUNK * 2)
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            error("Microphone unavailable")
        }
        audio = recorder
        try {
            recorder.startRecording()
            check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            running.set(true)
            worker = Thread({
                val buffer = ByteArray(CHUNK)
                try {
                    DataOutputStream(FileOutputStream(file)).use { output ->
                        var sequence = 0
                        while (running.get() && pcmBytes < MAX_PCM) {
                            val readRevision = synchronized(pauseGate) {
                                while (paused && running.get()) pauseGate.wait()
                                revision
                            }
                            if (!running.get()) break
                            val count = recorder.read(buffer, 0, minOf(buffer.size, MAX_PCM - pcmBytes))
                            if (!running.get()) break
                            val committed = synchronized(pauseGate) {
                                if (paused || revision != readRevision) {
                                    false
                                } else {
                                    check(count > 0 && count % 2 == 0) { "Recording interrupted" }
                                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                    cipher.init(Cipher.ENCRYPT_MODE, key)
                                    cipher.updateAAD(aad(sequence++))
                                    val encrypted = cipher.doFinal(buffer, 0, count)
                                    try {
                                        output.writeInt(encrypted.size)
                                        output.write(cipher.iv)
                                        output.write(encrypted)
                                        pcmBytes += count
                                    } finally {
                                        encrypted.fill(0)
                                    }
                                    true
                                }
                            }
                            buffer.fill(0)
                            if (!committed) continue
                        }
                        if (!cancelled.get()) {
                            // Authenticated terminal record makes truncated spools invalid.
                            val terminal = Cipher.getInstance("AES/GCM/NoPadding")
                            terminal.init(Cipher.ENCRYPT_MODE, key)
                            terminal.updateAAD(aad(sequence))
                            val tag = terminal.doFinal(ByteArray(0))
                            try {
                                output.writeInt(tag.size)
                                output.write(terminal.iv)
                                output.write(tag)
                            } finally {
                                tag.fill(0)
                            }
                        }
                        output.flush()
                    }
                } catch (e: Throwable) {
                    error = e
                } finally {
                    running.set(false)
                    buffer.fill(0)
                    try { recorder.stop() } catch (_: Exception) {}
                    if (cancelled.get()) {
                        try { deleteSpool() } catch (cleanupError: Throwable) {
                            error = cleanupError
                        }
                    }
                }
            }, "ChatEncryptedRecorder").apply { start() }
        } catch (e: Throwable) {
            cancel()
            throw e
        }
    }

    private fun halt() {
        running.set(false)
        synchronized(pauseGate) { pauseGate.notifyAll() }
        try { audio?.stop() } catch (_: Exception) {}
        val currentWorker = worker
        currentWorker?.join(3000)
        val stillRunning = currentWorker?.isAlive == true
        try {
            audio?.release()
        } finally {
            audio = null
            if (!stillRunning) worker = null
        }
        check(!stillRunning) { "Recorder did not stop" }
    }

    fun pause() {
        check(running.get() && error == null && !paused) { "Recording is not active" }
        synchronized(pauseGate) {
            paused = true
            revision++
        }
        try {
            audio?.stop()
        } catch (e: Exception) {
            synchronized(pauseGate) {
                paused = false
                revision++
                pauseGate.notifyAll()
            }
            throw e
        }
    }

    fun status(): String = when {
        error != null -> "failed"
        pcmBytes >= MAX_PCM -> "completed"
        !running.get() -> "interrupted"
        paused -> "paused"
        else -> "recording"
    }

    fun resume() {
        check(running.get() && error == null && paused) { "Recording is not paused" }
        val recorder = audio ?: error("Microphone unavailable")
        recorder.startRecording()
        check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING)
        synchronized(pauseGate) {
            paused = false
            pauseGate.notifyAll()
        }
    }

    fun finish(): ByteArray {
        var wav: ByteArray? = null
        try {
            halt()
            check(error == null && pcmBytes > 0 && pcmBytes <= MAX_PCM) { "Recording interrupted" }
            wav = ByteArray(44 + pcmBytes)
            val header = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray(Charsets.US_ASCII)).putInt(36 + pcmBytes)
            header.put("WAVEfmt ".toByteArray(Charsets.US_ASCII)).putInt(16)
            header.putShort(1).putShort(1).putInt(RATE).putInt(RATE * 2)
            header.putShort(2).putShort(16)
            header.put("data".toByteArray(Charsets.US_ASCII)).putInt(pcmBytes)
            DataInputStream(FileInputStream(file)).use { input ->
                var position = 44
                var sequence = 0
                while (true) {
                    val length = input.readInt()
                    check(length in 16..(CHUNK + 16))
                    val iv = ByteArray(12)
                    input.readFully(iv)
                    val encrypted = ByteArray(length)
                    input.readFully(encrypted)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
                    cipher.updateAAD(aad(sequence++))
                    val plain = try { cipher.doFinal(encrypted) } finally { encrypted.fill(0) }
                    try {
                        if (plain.isEmpty()) {
                            check(position == wav.size && input.read() == -1)
                            break
                        }
                        check(position + plain.size <= wav.size)
                        plain.copyInto(wav, position)
                        position += plain.size
                    } finally { plain.fill(0) }
                }
            }
            return wav
        } catch (e: Throwable) {
            wav?.fill(0)
            throw e
        } finally { deleteSpool() }
    }

    fun cancel() {
        cancelled.set(true)
        try {
            halt()
        } finally {
            if (worker?.isAlive != true) deleteSpool()
        }
    }

    private fun deleteSpool() {
        check(!file.exists() || file.delete()) { "Recording spool cleanup failed" }
    }

    private fun aad(sequence: Int): ByteArray =
        (file.name + ":" + sequence).toByteArray(Charsets.UTF_8)

    private fun loadKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    companion object {
        private const val KEY_ALIAS = "chat_recording_spool_v1"
        private const val RATE = ChatRecordingDuration.SAMPLE_RATE
        private const val CHUNK = 8192
        private const val MAX_PCM = ChatRecordingDuration.MAX_PCM_BYTES

        fun cleanAbandoned(context: Context) {
            val failedDeletes = File(context.noBackupFilesDir, "chat_recordings").listFiles()
                ?.filter { it.name.startsWith("spool-") && it.isFile }
                ?.filterNot { it.delete() }
                .orEmpty()
            check(failedDeletes.isEmpty()) { "Recording spool cleanup failed" }
        }
    }

}

internal object ChatRecordingDuration {
    const val SAMPLE_RATE = 16000
    private const val CHANNELS = 1
    private const val BYTES_PER_SAMPLE = 2
    const val MAX_SECONDS = 300
    const val MAX_PCM_BYTES = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * MAX_SECONDS

    fun millisecondsForPcmBytes(pcmBytes: Int): Long {
        require(pcmBytes in 0..MAX_PCM_BYTES)
        return pcmBytes.toLong() * 1000 / (SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE)
    }
}
