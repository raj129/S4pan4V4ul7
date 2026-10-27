package com.system.calculator

/** One transition policy for Flutter controls and notification actions. */
object ChatUploadPolicy {
    private val runnable = setOf("queued", "uploading", "retrying", "resumed")
    val supportedMediaTypes = setOf("image", "gif", "sticker", "video", "audio", "file")

    fun runnable(state: String) = state in runnable

    fun supportsMediaType(mediaType: String?) =
        mediaType != null && mediaType in supportedMediaTypes

    fun restartExpiredSession(hasSession: Boolean, httpCode: Int) =
        hasSession && httpCode in setOf(404, 410)

    fun confirmedProgress(saved: Long, snapshot: Long, sameSession: Boolean): Long {
        require(saved >= 0 && snapshot >= 0)
        return if (sameSession) maxOf(saved, snapshot) else snapshot
    }

    fun transition(state: String, command: String, delivering: Boolean): String {
        if (delivering) return state
        return when (command) {
            "pause" -> if (runnable(state)) "paused" else state
            "resume" -> if (state == "paused") "resumed" else state
            "retry" -> if (state == "failed") "retrying" else state
            "cancel" -> if (state in runnable || state in setOf("paused", "failed")) "cancelled" else state
            else -> throw IllegalArgumentException("Unknown upload command")
        }
    }
}
