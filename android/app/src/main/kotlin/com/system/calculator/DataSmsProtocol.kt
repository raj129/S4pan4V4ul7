package com.system.calculator

import java.nio.ByteBuffer
import java.util.UUID

internal object DataSmsProtocol {
    const val PORT = 42831
    const val MAX_SMS_DATA_BYTES = 120
    const val HEADER_BYTES = 21
    const val PAYLOAD_BYTES = MAX_SMS_DATA_BYTES - HEADER_BYTES
    const val MAX_SEGMENTS = 10

    data class Part(val id: String, val index: Int, val total: Int, val payload: ByteArray)

    fun split(id: String, payload: ByteArray): List<ByteArray> {
        val uuid = UUID.fromString(id)
        require(uuid.toString() == id.lowercase()) { "Invalid message UUID" }
        require(payload.isNotEmpty() && payload.size <= PAYLOAD_BYTES * MAX_SEGMENTS) {
            "Payload must occupy 1 to 10 segments"
        }
        val count = (payload.size + PAYLOAD_BYTES - 1) / PAYLOAD_BYTES
        return (0 until count).map { index ->
            val start = index * PAYLOAD_BYTES
            val length = minOf(PAYLOAD_BYTES, payload.size - start)
            ByteBuffer.allocate(HEADER_BYTES + length).apply {
                put(0x53.toByte())
                put(0x34.toByte())
                put(1.toByte())
                putLong(uuid.mostSignificantBits)
                putLong(uuid.leastSignificantBits)
                put(index.toByte())
                put(count.toByte())
                put(payload, start, length)
            }.array()
        }
    }

    fun parse(bytes: ByteArray): Part? {
        if (bytes.size <= HEADER_BYTES || bytes.size > MAX_SMS_DATA_BYTES) return null
        val buffer = ByteBuffer.wrap(bytes)
        if (buffer.get() != 0x53.toByte() || buffer.get() != 0x34.toByte() ||
            buffer.get() != 1.toByte()) return null
        val id = UUID(buffer.long, buffer.long).toString()
        val index = buffer.get().toInt() and 0xff
        val total = buffer.get().toInt() and 0xff
        if (total !in 1..MAX_SEGMENTS || index >= total) return null
        val payload = ByteArray(buffer.remaining())
        buffer.get(payload)
        // All non-final parts must be full; otherwise many encodings of the
        // same logical payload would be accepted.
        if (index < total - 1 && payload.size != PAYLOAD_BYTES) return null
        return Part(id, index, total, payload)
    }
}
