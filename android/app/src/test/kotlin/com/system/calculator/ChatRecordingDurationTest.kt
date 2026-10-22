package com.system.calculator

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ChatRecordingDurationTest {
    @Test
    fun durationUsesOnlyCommittedPcmSamples() {
        val bytesForTwoMinutes = ChatRecordingDuration.SAMPLE_RATE * 2 * 120

        assertEquals(120_000L, ChatRecordingDuration.millisecondsForPcmBytes(bytesForTwoMinutes))
    }

    @Test
    fun maximumPcmRepresentsExactlyFiveRecordedMinutes() {
        assertEquals(
            300_000L,
            ChatRecordingDuration.millisecondsForPcmBytes(ChatRecordingDuration.MAX_PCM_BYTES)
        )
    }

    @Test
    fun rejectsPcmBeyondTheRecordingLimit() {
        assertThrows(IllegalArgumentException::class.java) {
            ChatRecordingDuration.millisecondsForPcmBytes(ChatRecordingDuration.MAX_PCM_BYTES + 1)
        }
    }
}
