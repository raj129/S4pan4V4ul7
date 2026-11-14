package com.system.calculator

import org.junit.Assert.*
import org.junit.Test

class DataSmsProtocolTest {
    private val id = "13fbe12b-0e81-46d3-aef3-900357eac932"

    @Test fun boundariesAndRoundTrip() {
        for (size in listOf(1, 112, 113, 1120)) {
            val payload = ByteArray(size) { it.toByte() }
            val chunks = DataSmsProtocol.split(id, payload)
            assertEquals((size + 111) / 112, chunks.size)
            assertTrue(chunks.all { it.size <= 133 })
            val parts = chunks.map { DataSmsProtocol.parse(it)!! }
            assertTrue(parts.all { it.id == id && it.total == chunks.size })
            assertArrayEquals(payload, parts.flatMap { it.payload.asList() }.toByteArray())
            assertEquals(parts.indices.toList(), parts.map { it.index })
        }
    }

    @Test fun rejectsInvalidOrOversizedPayloadsAndSegments() {
        for (size in listOf(0, 1121)) {
            try {
                DataSmsProtocol.split(id, ByteArray(size))
                fail("Expected invalid payload rejection")
            } catch (_: IllegalArgumentException) { }
        }
        val valid = DataSmsProtocol.split(id, ByteArray(113))
        assertNull(DataSmsProtocol.parse(valid[0].copyOf(134)))
        assertNull(DataSmsProtocol.parse(valid[0].copyOf(22)))
        assertNull(DataSmsProtocol.parse(valid[0].clone().apply { this[0] = 0 }))
        assertNull(DataSmsProtocol.parse(valid[0].clone().apply { this[2] = 2 }))
        assertNull(DataSmsProtocol.parse(valid[0].clone().apply { this[19] = 2 }))
        assertNull(DataSmsProtocol.parse(valid[0].clone().apply { this[20] = 11 }))
    }
}
