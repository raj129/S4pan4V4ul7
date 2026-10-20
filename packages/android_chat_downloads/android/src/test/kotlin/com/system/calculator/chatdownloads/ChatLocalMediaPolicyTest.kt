package com.system.calculator.chatdownloads

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class ChatLocalMediaPolicyTest {
    private fun rejects(code: String, action: () -> Unit) {
        try {
            action(); fail("Accepted invalid local media operation")
        } catch (error: LocalMediaException) {
            assertEquals(code, error.code)
        }
    }

    @Test
    fun accountQualifiedIdentitySupportsLegacyAndDeterministicNames() {
        val path = "chat_media/alice_bob/message/media.enc"
        assertEquals(64, ChatLocalMediaPolicy.identity("alice", path).length)
        assertNotEquals(
            ChatLocalMediaPolicy.identity("alice", path),
            ChatLocalMediaPolicy.identity("bob", path)
        )
        assertNotEquals(
            ChatLocalMediaPolicy.identity("alice", path),
            ChatLocalMediaPolicy.identity("alice", "chat_media/alice_bob/message/photo_123.jpg.enc")
        )
        assertEquals(64, ChatLocalMediaPolicy.identity("alice", "chat_media/bob_alice/message/thumb.enc").length)
    }

    @Test
    fun unsupportedLayoutsRemainRejected() {
        for (path in listOf(
            "chat_media/bob_carol/photo.jpg.enc", "chat_media/malice_bob/photo.jpg.enc",
            "chat_media/alice_bob/..", "chat_media/alice_bob/", "chat_media/alice_bob",
            "other/alice_bob/photo.enc", "chat_media/alice_bob/photo_123.jpg.enc",
            "chat_media/alice_bob/message/extra/media.enc"
        )) {
            rejects("local_media_invalid_identity") { ChatLocalMediaPolicy.identity("alice", path) }
        }
    }

    @Test
    fun acceptsSafeEncryptedLeafNamesInRepositoryLayout() {
        for (filename in listOf(
            "media.enc", "thumb.enc", "photo_123.jpg.enc",
            "video-123.mp4.enc", "file-123.bin.enc", "photo-123.thumb.enc",
            "a72b-1234.jpg.enc", "source.txt.enc", "arbitrary.enc"
        )) {
            assertEquals(
                "alice_bob", ChatLocalMediaPolicy.attachmentPath(
                    "alice", "chat_media/alice_bob/message/$filename"
                )[1]
            )
            assertEquals(
                "alice_bob", ChatLocalMediaPolicy.attachmentPath(
                    "alice", "chat_media/alice_bob/forwarded_123/$filename"
                )[1]
            )
        }
        for (filename in listOf(
            "photo.jpg", "index.html", "photo.jpg.enc.html", ".jpg.enc",
            "photo.jpg.ENC", "unsafe leaf.enc", "a\\b.enc", "..", "a\u0000.enc"
        )) {
            for (prefix in listOf("chat_media/alice_bob", "chat_media/alice_bob/message")) {
                rejects("local_media_invalid_identity") {
                    ChatLocalMediaPolicy.attachmentPath("alice", "$prefix/$filename")
                }
            }
        }
        rejects("local_media_invalid_identity") {
            ChatLocalMediaPolicy.attachmentPath("alice", "chat_media/alice_/message/media.enc")
        }
    }

    @Test
    fun rejectsUnscopedOrAmbiguousPaths() {
        for (path in listOf(
            "chat_media/malice_bob/id/media.enc", "chat_media/bob_carol/id/media.enc",
            "chat_media/alice_bob/../media.enc", "chat_media/alice_bob/id/../../media.enc",
            "chat_media/alice_bob/id/a\\b", "chat_media/alice_bob/id/"
        )) {
            rejects("local_media_invalid_identity") { ChatLocalMediaPolicy.identity("alice", path) }
        }
    }

    @Test
    fun nonceCipherTagBoundsAreEnforced() {
        ChatLocalMediaPolicy.size(29)
        ChatLocalMediaPolicy.size(ChatLocalMediaPolicy.MAX_BYTES)
        for (size in listOf(0L, 28L, ChatLocalMediaPolicy.MAX_BYTES + 1)) {
            rejects("local_media_invalid_size") { ChatLocalMediaPolicy.size(size) }
        }
    }

    @Test
    fun sourceReferencesAcceptLocalContentAndAbsoluteFileUrisOnly() {
        for (uri in listOf(
            "content://fixture/document/1", "content://fixture/document/a%20b?token=local",
            "file:///storage/emulated/0/Download/photo.jpg", "file:///data/user/0/app/cache/shared%20file.jpg"
        )) {
            ChatLocalMediaPolicy.sourceUri(uri)
        }
        for (uri in listOf(
            "https://server/media.jpg", "file://server/media.jpg", "file:relative.jpg",
            "content:opaque", "content://user:password@fixture/document/1",
            "content://fixture/document/1#fragment", "file:///storage/file.jpg#fragment",
            "file:///storage/file.jpg?query=1", "file:///storage/../private.jpg",
            "file:///storage/%2e%2e/private.jpg", "content://fixture/document/../private",
            "content://fixture/document/%2E%2E/private", "file:///storage/a%5Cb.jpg",
            "file:///storage/a%00b.jpg", "/storage/photo.jpg", "content:///document/1"
        )) {
            rejects("local_media_invalid_source") { ChatLocalMediaPolicy.sourceUri(uri) }
        }
    }

    @Test
    fun sharedBudgetAndPhysicalReserveNeverEvictCompletedFiles() {
        val bytes = 29L
        ChatLocalMediaPolicy.reserve(
            ChatLocalMediaPolicy.BUDGET_BYTES - bytes, bytes,
            ChatLocalMediaPolicy.DISK_RESERVE_BYTES + bytes
        )
        rejects("local_media_storage_full") {
            ChatLocalMediaPolicy.reserve(ChatLocalMediaPolicy.BUDGET_BYTES - bytes + 1, bytes, Long.MAX_VALUE)
        }
        rejects("local_media_storage_full") {
            ChatLocalMediaPolicy.reserve(0, bytes, ChatLocalMediaPolicy.DISK_RESERVE_BYTES + bytes - 1)
        }
    }

    @Test
    fun directionIsImmutable() {
        ChatLocalMediaPolicy.sameDirection(null, "received")
        ChatLocalMediaPolicy.sameDirection("sent", "sent")
        rejects("local_media_direction_conflict") { ChatLocalMediaPolicy.sameDirection("sent", "received") }
        rejects("local_media_invalid_direction") { ChatLocalMediaPolicy.direction("unknown") }
        rejects("local_media_direction_conflict") {
            ChatLocalMediaPolicy.writable("absent", "sent", "received")
        }
    }

    @Test
    fun movedMarkersCannotResurrectEvenWhenDirectionIsUnknown() {
        assertFalse(ChatLocalMediaPolicy.readable("moved", "received", "sent"))
        assertFalse(ChatLocalMediaPolicy.readable("absent", "received", "received"))
        rejects("local_media_moved") { ChatLocalMediaPolicy.writable("moved", "received", "received") }
        rejects("local_media_moved") { ChatLocalMediaPolicy.writable("moved", "received", "sent") }
        rejects("local_media_corrupt") { ChatLocalMediaPolicy.readable("invalid", "sent", "sent") }
        rejects("local_media_corrupt") { ChatLocalMediaPolicy.readable("intent", "received", "received") }
        rejects("local_media_direction_conflict") {
            ChatLocalMediaPolicy.readable("complete", "received", "sent")
        }
    }

    @Test
    fun sentMovesRetainSourceButExplicitRemovalClearsSourceWithoutLosingMarker() {
        assertTrue(ChatLocalMediaPolicy.retainSourceOnRemoval("sent", true))
        assertFalse(ChatLocalMediaPolicy.retainSourceOnRemoval("received", true))
        assertFalse(ChatLocalMediaPolicy.retainSourceOnRemoval("sent", false))
        assertFalse(ChatLocalMediaPolicy.retainSourceOnRemoval("received", false))
        assertEquals("moved", ChatLocalMediaPolicy.removalState("complete", true))
        assertEquals("moved", ChatLocalMediaPolicy.removalState(null, true))
        assertEquals("moved", ChatLocalMediaPolicy.removalState("moved", false))
        assertEquals("absent", ChatLocalMediaPolicy.removalState("complete", false))
        assertFalse(ChatLocalMediaPolicy.readable("moved", "sent", "sent"))
        rejects("local_media_moved") { ChatLocalMediaPolicy.writable("moved", "received", "received") }
    }

    @Test
    fun recoveryRequiresSealedIntentAndNeverTrustsUnknownPartials() {
        assertEquals("invalid", ChatLocalMediaPolicy.recovery(null, true, true))
        assertEquals("invalid", ChatLocalMediaPolicy.recovery("unknown", true, true))
        assertEquals("promote", ChatLocalMediaPolicy.recovery("intent", false, true))
        assertEquals("complete", ChatLocalMediaPolicy.recovery("intent", true, false))
        assertEquals("invalid", ChatLocalMediaPolicy.recovery("intent", false, false))
        assertEquals("invalid", ChatLocalMediaPolicy.recovery("complete", false, true))
        assertEquals("moved", ChatLocalMediaPolicy.recovery("moved", true, true))
        assertEquals("absent", ChatLocalMediaPolicy.recovery("absent", true, true))
    }

    @Test
    fun promotionRequiresCompleteDigestAndDoesNotOverwrite() {
        val dir = File("build", "local-media-policy-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val bytes = ByteArray(29) { it.toByte() }
            val digest = ChatLocalMediaPolicy.digest(bytes)
            val part = File(dir, "attachment.part")
            val complete = File(dir, "attachment.enc")
            ChatLocalMediaPolicy.writePartial(part, bytes)
            rejects("local_media_corrupt") { ChatLocalMediaPolicy.promote(part, complete, 30, digest) }
            rejects("local_media_corrupt") { ChatLocalMediaPolicy.promote(part, complete, 29, "bad") }
            assertFalse(complete.exists())
            ChatLocalMediaPolicy.promote(part, complete, 29, digest)
            assertFalse(part.exists())
            assertTrue(ChatLocalMediaPolicy.valid(complete, 29, digest))
            ChatLocalMediaPolicy.writePartial(part, bytes)
            rejects("local_media_unavailable") { ChatLocalMediaPolicy.promote(part, complete, 29, digest) }
            complete.writeBytes(ByteArray(29))
            assertFalse(ChatLocalMediaPolicy.valid(complete, 29, digest))
        } finally {
            dir.deleteRecursively()
        }
    }
}
