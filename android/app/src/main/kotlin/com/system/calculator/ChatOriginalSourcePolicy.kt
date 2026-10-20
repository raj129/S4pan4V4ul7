package com.system.calculator

import java.io.File
import java.net.URI

/** Only explicit local source references are accepted; content paths are never inferred. */
internal object ChatOriginalSourcePolicy {
    fun fenceFailure(
        requestedUid: String?,
        currentUid: String?,
        expectedAccountEpoch: Int,
        accountEpoch: Int,
        engineAttached: Boolean,
        expectedGeneration: Int,
        generation: Int,
    ): String? = when {
        requestedUid.isNullOrBlank() || currentUid != requestedUid ||
                expectedAccountEpoch != accountEpoch -> "account_changed"

        !engineAttached || expectedGeneration != generation -> "cancelled"
        else -> null
    }

    fun validate(value: String): URI {
        require(value.isNotBlank() && value.length <= 8192)
        val uri = URI(value)
        require(!uri.isOpaque && uri.rawFragment == null && uri.rawUserInfo == null)
        when (uri.scheme) {
            "content" -> require(!uri.rawAuthority.isNullOrBlank() && uri.host != "")
            "file" -> {
                require(uri.rawAuthority.isNullOrEmpty() && uri.rawQuery == null)
                val path = uri.path ?: throw IllegalArgumentException()
                require(path.startsWith("/") && !path.contains('\\') && !path.contains('\u0000'))
                require(path.split('/').none { it == "." || it == ".." })
            }

            else -> throw IllegalArgumentException()
        }
        return uri
    }

    fun existingFile(uri: URI): File {
        require(uri.scheme == "file")
        val reference = File(uri)
        require(reference.isAbsolute)
        val file = reference.canonicalFile
        if (!file.isFile) throw java.io.FileNotFoundException()
        if (!file.canRead()) throw SecurityException()
        return file
    }
}
