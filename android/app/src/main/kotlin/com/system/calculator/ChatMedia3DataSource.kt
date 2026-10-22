package com.system.calculator

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import java.io.EOFException

/** Reopening/seeking never creates plaintext files. The player owns and wipes
 * the shared memory buffer only after releasing all of its readers. */
@androidx.media3.common.util.UnstableApi
internal class ChatMedia3DataSource(private val source: ChatMemoryDataSource) : BaseDataSource(false) {
    private var position = 0L
    private var remaining = 0L
    private var opened = false
    private var uri: Uri? = null

    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)
        val size = source.size
        if (dataSpec.position < 0 || dataSpec.position > size) throw EOFException("Invalid media offset")
        position = dataSpec.position
        remaining = size - position
        if (dataSpec.length != C.LENGTH_UNSET.toLong()) remaining = minOf(remaining, dataSpec.length)
        uri = dataSpec.uri
        opened = true
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        val count = source.readAt(position, buffer, offset, minOf(length.toLong(), remaining).toInt())
        if (count <= 0) throw EOFException("Media buffer was released or truncated")
        position += count
        remaining -= count
        bytesTransferred(count)
        return count
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        uri = null
        remaining = 0
        if (opened) {
            opened = false
            transferEnded()
        }
    }
}
