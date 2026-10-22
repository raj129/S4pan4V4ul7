package com.system.calculator.chatdownloads

import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.net.URISyntaxException
import java.security.MessageDigest

internal class LocalMediaException(val code: String) : Exception("Encrypted local media action failed")

internal object ChatLocalMediaPolicy {
    const val MAX_BYTES = 64L * 1024 * 1024
    const val BUDGET_BYTES = 150L * 1024 * 1024
    const val DISK_RESERVE_BYTES = 4L * 1024 * 1024

    fun identity(uid: String, path: String): String {
        attachmentPath(uid, path)
        return digest("$uid\n$path".toByteArray(Charsets.UTF_8))
    }

    fun attachmentPath(uid: String, path: String): List<String> {
        val segments = path.split('/')
        if (uid.isBlank() || uid.length > 128 || uid.any { it.isISOControl() || it == '/' } ||
            segments.size != 4 || segments[0] != "chat_media" ||
            !((segments[1].startsWith("${uid}_") && segments[1].length > uid.length + 1) ||
                    (segments[1].endsWith("_$uid") && segments[1].length > uid.length + 1)) ||
            segments.drop(1).any {
                it.length !in 1..256 || it == "." || it == ".." ||
                        it.any { c -> c.isISOControl() || c == '\\' }
            } ||
            !segments[2].matches(Regex("[A-Za-z0-9_-]{1,128}")) ||
            !segments[3].matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,251}\\.enc"))) {
            throw LocalMediaException("local_media_invalid_identity")
        }
        return segments
    }

    fun direction(value: String): String {
        if (value !in setOf("received", "sent")) throw LocalMediaException("local_media_invalid_direction")
        return value
    }

    fun sourceUri(value: String) {
        if (value.isBlank() || value.length > 8192) throw LocalMediaException("local_media_invalid_source")
        val uri = try {
            URI(value)
        } catch (_: URISyntaxException) {
            throw LocalMediaException("local_media_invalid_source")
        }
        val path = uri.path
        if (uri.isOpaque || uri.rawFragment != null || uri.rawUserInfo != null ||
            path == null || !path.startsWith("/") ||
            path.any { it == '\\' || it.isISOControl() } ||
            path.split('/').any { it == "." || it == ".." }
        ) {
            throw LocalMediaException("local_media_invalid_source")
        }
        val local = when (uri.scheme) {
            "content" -> !uri.host.isNullOrBlank() && uri.port == -1
            "file" -> uri.rawAuthority.isNullOrEmpty() && uri.rawQuery == null
            else -> false
        }
        if (!local) throw LocalMediaException("local_media_invalid_source")
    }

    fun sameDirection(existing: String?, requested: String) {
        direction(requested)
        if (existing != null && existing != requested) {
            throw LocalMediaException("local_media_direction_conflict")
        }
    }

    fun readable(state: String, existingDirection: String, requested: String): Boolean {
        direction(requested)
        if (state in setOf("moved", "absent")) return false
        if (state != "complete") throw LocalMediaException("local_media_corrupt")
        sameDirection(existingDirection, requested)
        return true
    }

    fun writable(state: String?, existingDirection: String?, requested: String) {
        if (state == "moved") throw LocalMediaException("local_media_moved")
        sameDirection(existingDirection, requested)
    }

    fun removalState(previous: String?, markingMoved: Boolean): String =
        if (markingMoved || previous == "moved") "moved" else "absent"

    fun retainSourceOnRemoval(direction: String, markingMoved: Boolean): Boolean =
        direction == "sent" && markingMoved

    fun recovery(state: String?, completeValid: Boolean, partialValid: Boolean): String = when (state) {
        "intent" -> if (completeValid) "complete" else if (partialValid) "promote" else "invalid"
        "complete" -> if (completeValid) "complete" else "invalid"
        "moved", "absent", "invalid" -> state
        // Unknown files have no sealed metadata intent and cannot establish byte-complete ciphertext.
        else -> "invalid"
    }

    fun size(bytes: Long) {
        if (bytes !in 29..MAX_BYTES) throw LocalMediaException("local_media_invalid_size")
    }

    fun reserve(used: Long, bytes: Long, available: Long) {
        size(bytes)
        if (used < 0 || used > BUDGET_BYTES - bytes ||
            available < bytes + DISK_RESERVE_BYTES
        ) {
            throw LocalMediaException("local_media_storage_full")
        }
    }

    fun digest(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))

    fun fileDigest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        try {
            file.inputStream().use { stream ->
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    hash.update(buffer, 0, count)
                }
            }
            return hex(hash.digest())
        } finally {
            buffer.fill(0)
        }
    }

    fun valid(file: File, size: Long, digest: String): Boolean =
        size in 29..MAX_BYTES && file.isFile && file.length() == size && fileDigest(file) == digest

    fun writePartial(part: File, bytes: ByteArray) {
        size(bytes.size.toLong())
        FileOutputStream(part).use { stream ->
            stream.write(bytes)
            stream.flush()
            stream.fd.sync()
        }
    }

    fun promote(part: File, complete: File, size: Long, digest: String) {
        if (!valid(part, size, digest)) throw LocalMediaException("local_media_corrupt")
        if (complete.exists() || !part.renameTo(complete)) {
            throw LocalMediaException("local_media_unavailable")
        }
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
}
