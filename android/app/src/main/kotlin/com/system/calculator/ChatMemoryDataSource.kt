package com.system.calculator

import android.media.MediaDataSource

/** Owned, bounded buffer. Never accepts a path or opens an external file. */
internal class ChatMemoryDataSource(private var bytes: ByteArray?) : MediaDataSource() {
    init { require(bytes != null && bytes!!.isNotEmpty() && bytes!!.size <= MAX_BYTES) }

    @Synchronized override fun getSize(): Long = bytes?.size?.toLong() ?: 0L

    @Synchronized override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        val source = bytes ?: return -1
        if (position < 0 || offset < 0 || size < 0 || offset > buffer.size - size) return -1
        if (size == 0) return 0
        if (position >= source.size) return -1
        val count = minOf(size, source.size - position.toInt())
        source.copyInto(buffer, offset, position.toInt(), position.toInt() + count)
        return count
    }

    @Synchronized override fun close() {
        bytes?.fill(0)
        bytes = null
    }

    companion object { const val MAX_BYTES = 64 * 1024 * 1024 - 1024 }
}
