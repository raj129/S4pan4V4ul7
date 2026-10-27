package com.system.calculator

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatUploadPolicyTest {
    @Test fun resumeDoesNotDisplayZeroWhileTheSdkQueriesItsSavedSession() {
        assertEquals(1_048_576L, ChatUploadPolicy.confirmedProgress(1_048_576L, 0, true))
        assertEquals(2_097_152L, ChatUploadPolicy.confirmedProgress(1_048_576L, 2_097_152L, true))
        assertEquals(0L, ChatUploadPolicy.confirmedProgress(1_048_576L, 0, false))
    }
    @Test fun onlyExpiredExistingSessionsRestartWithoutBackoff() {
        assertTrue(ChatUploadPolicy.restartExpiredSession(true, 404))
        assertTrue(ChatUploadPolicy.restartExpiredSession(true, 410))
        assertFalse(ChatUploadPolicy.restartExpiredSession(false, 404))
        assertFalse(ChatUploadPolicy.restartExpiredSession(true, 403))
        assertFalse(ChatUploadPolicy.restartExpiredSession(true, 503))
    }

    @Test fun gifsAndStickersAreValidEncryptedUploadMediaTypes() {
        for (type in listOf("image", "gif", "sticker", "video", "audio", "file")) {
            assertTrue(ChatUploadPolicy.supportsMediaType(type))
        }
        for (type in listOf("text", "liveLocation", "unknown")) {
            assertFalse(ChatUploadPolicy.supportsMediaType(type))
        }
        assertFalse(ChatUploadPolicy.supportsMediaType(null))
    }
    @Test fun allActiveStatesCanPauseAndCancel() {
        for (state in listOf("queued", "uploading", "resumed", "retrying")) {
            assertTrue(ChatUploadPolicy.runnable(state))
            assertEquals("paused", ChatUploadPolicy.transition(state, "pause", false))
            assertEquals("cancelled", ChatUploadPolicy.transition(state, "cancel", false))
        }
    }

    @Test fun terminalStatesNeverResurrectFromUnrelatedCommands() {
        for (state in listOf("completed", "cancelled")) {
            assertFalse(ChatUploadPolicy.runnable(state))
            for (command in listOf("pause", "cancel", "retry", "resume")) {
                assertEquals(state, ChatUploadPolicy.transition(state, command, false))
            }
        }
        assertEquals("failed", ChatUploadPolicy.transition("failed", "resume", false))
        assertEquals("paused", ChatUploadPolicy.transition("paused", "retry", false))
    }

    @Test fun resumeAndRetryAreExplicitRecoveryTransitions() {
        assertEquals("resumed", ChatUploadPolicy.transition("paused", "resume", false))
        assertEquals("retrying", ChatUploadPolicy.transition("failed", "retry", false))
    }

    @Test fun deliveryCommitCannotRaceUserCancellation() {
        for (command in listOf("pause", "cancel", "retry", "resume")) {
            assertEquals("uploading", ChatUploadPolicy.transition("uploading", command, true))
        }
    }
}
