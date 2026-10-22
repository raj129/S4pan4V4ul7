package com.system.calculator.chatdownloads

import org.junit.Assert.*
import org.junit.Test

class ChatDownloadPolicyTest {
    @Test
    fun transportChecksumsRejectChangedOrTruncatedCiphertext() {
        assertTrue(ChatDownloadPolicy.checksumsMatch("ABC", "abc", "same", "same"))
        assertTrue(ChatDownloadPolicy.checksumsMatch(null, "abc", null, "same"))
        assertFalse(ChatDownloadPolicy.checksumsMatch("abc", "bad", "same", "same"))
        assertFalse(ChatDownloadPolicy.checksumsMatch("abc", "abc", "same", "bad"))
    }

    @Test
    fun sentOrUnclassifiedJobsCannotAcquireAttachmentBytes() {
        assertTrue(ChatDownloadPolicy.receivedSender("alice", "bob", "alice_bob"))
        assertFalse(ChatDownloadPolicy.receivedSender("alice", "alice", "alice_bob"))
        assertFalse(ChatDownloadPolicy.receivedSender("alice", "", "alice_bob"))
        assertFalse(ChatDownloadPolicy.receivedSender("alice", "mallory", "alice_bob"))
    }

    @Test
    fun validatesRangeOffsetAndObjectSize() {
        assertEquals(
            ChatDownloadPolicy.Range(100, 199, 200),
            ChatDownloadPolicy.range("bytes 100-199/200", 100, 200)
        )
        for (header in listOf("bytes 0-199/200", "bytes 100-200/200", "bytes 100-199/201", "invalid")) {
            try {
                ChatDownloadPolicy.range(header, 100, 200); fail("Accepted mismatched range")
            } catch (_: java.io.IOException) {
            }
        }
    }

    @Test
    fun restoresOnlyCheckpointedDurableBytes() {
        assertEquals(50L, ChatDownloadPolicy.recoveredOffset(50, 100, 200))
        assertEquals(25L, ChatDownloadPolicy.recoveredOffset(50, 25, 200))
        assertEquals(200L, ChatDownloadPolicy.recoveredOffset(250, 250, 200))
    }

    @Test
    fun serverIgnoringRangeRestartsRatherThanAppending() {
        assertEquals(
            ChatDownloadPolicy.Response(0, 200),
            ChatDownloadPolicy.response(200, null, 100, 200, 200)
        )
        assertEquals(
            ChatDownloadPolicy.Response(100, 100),
            ChatDownloadPolicy.response(206, "bytes 100-199/200", 100, 200, 100)
        )
    }

    @Test
    fun malformedOrTruncatedResponsesAreNotAccepted() {
        for (code in listOf(200, 206)) {
            try {
                ChatDownloadPolicy.response(code, "bytes 100-199/200", 100, 200, 99)
                fail("Accepted truncated response")
            } catch (_: java.io.IOException) {
            }
        }
        try {
            ChatDownloadPolicy.response(416, "bytes */200", 100, 200, 0)
            fail("Accepted an invalid range as downloaded bytes")
        } catch (_: java.io.IOException) {
        }
    }

    @Test
    fun pausedQueueNeverAutomaticallyResumes() {
        assertFalse(ChatDownloadPolicy.runnable("paused"))
        assertEquals("paused", ChatDownloadPolicy.transition("paused", "retry"))
        assertEquals("resumed", ChatDownloadPolicy.transition("paused", "resume"))
    }

    @Test
    fun cancelCanInvalidateUnauthenticatedCompletedBytes() {
        assertEquals("cancelled", ChatDownloadPolicy.transition("completed", "cancel"))
        assertEquals("retrying", ChatDownloadPolicy.transition("cancelled", "retry"))
        assertEquals("retrying", ChatDownloadPolicy.transition("failed", "retry"))
    }
}
