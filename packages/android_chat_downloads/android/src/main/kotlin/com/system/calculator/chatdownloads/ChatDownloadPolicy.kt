package com.system.calculator.chatdownloads

internal object ChatDownloadPolicy {
    const val MAX_BYTES = 64L * 1024 * 1024
    fun receivedSender(uid: String, sender: String, thread: String): Boolean {
        val participants = thread.split('_')
        return sender.isNotEmpty() && sender != uid &&
                participants.contains(uid) && participants.contains(sender)
    }

    fun checksumsMatch(
        expectedSha: String?, actualSha: String,
        expectedMd5: String?, actualMd5: String
    ): Boolean =
        (expectedSha == null || expectedSha.equals(actualSha, ignoreCase = true)) &&
                (expectedMd5 == null || expectedMd5 == actualMd5)

    fun runnable(state: String) = state in setOf("queued", "uploading", "resumed", "retrying")
    fun transition(state: String, action: String): String = when (action) {
        "pause" -> if (runnable(state)) "paused" else state
        "resume" -> if (state == "paused") "resumed" else state
        "retry" -> if (state in setOf("failed", "cancelled")) "retrying" else state
        "cancel" -> "cancelled"
        else -> throw IllegalArgumentException("Unknown download action")
    }

    data class Range(val start: Long, val end: Long, val total: Long)
    data class Response(val start: Long, val bytes: Long)

    fun response(
        code: Int, header: String?, offset: Long, total: Long,
        contentLength: Long
    ): Response {
        require(total in 29..MAX_BYTES && offset in 0 until total)
        val result = when (code) {
            200 -> Response(0, total)
            206 -> range(header, offset, total).let { Response(it.start, it.end - it.start + 1) }
            else -> throw java.io.IOException("Download request failed")
        }
        if (contentLength >= 0 && contentLength != result.bytes) {
            throw java.io.IOException("Download length mismatch")
        }
        return result
    }

    fun range(value: String?, offset: Long, total: Long): Range {
        val match = Regex("^bytes (\\d+)-(\\d+)/(\\d+)$").matchEntire(value ?: "")
            ?: throw java.io.IOException("Invalid download range response")
        val values = match.groupValues.drop(1).map { it.toLong() }
        val range = Range(values[0], values[1], values[2])
        require(total in 29..MAX_BYTES && offset in 0 until total)
        if (range.start != offset || range.total != total ||
            range.end < range.start || range.end >= total
        ) {
            throw java.io.IOException("Download range does not match the requested object")
        }
        return range
    }

    fun recoveredOffset(checkpoint: Long, fileLength: Long, total: Long): Long {
        require(checkpoint >= 0 && fileLength >= 0 && total in 0..MAX_BYTES)
        return minOf(checkpoint, fileLength, if (total == 0L) MAX_BYTES else total)
    }
}
