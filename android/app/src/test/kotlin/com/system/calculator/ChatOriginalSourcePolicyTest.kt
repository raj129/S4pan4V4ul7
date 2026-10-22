package com.system.calculator

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertNull
import org.junit.Test

class ChatOriginalSourcePolicyTest {
    @Test
    fun accountAndLifecycleFencesNeverUseFallbackPermissionErrors() {
        assertNull(ChatOriginalSourcePolicy.fenceFailure("uid", "uid", 1, 1, true, 2, 2))
        assertEquals(
            "account_changed",
            ChatOriginalSourcePolicy.fenceFailure("uid", null, 1, 1, true, 2, 2)
        )
        assertEquals(
            "account_changed",
            ChatOriginalSourcePolicy.fenceFailure("uid", "other", 1, 1, true, 2, 2)
        )
        assertEquals(
            "account_changed",
            ChatOriginalSourcePolicy.fenceFailure("uid", "uid", 1, 3, true, 2, 2)
        )
        assertEquals(
            "account_changed",
            ChatOriginalSourcePolicy.fenceFailure("uid", null, 1, 2, false, 2, 3)
        )
        assertEquals(
            "cancelled",
            ChatOriginalSourcePolicy.fenceFailure("uid", "uid", 1, 1, false, 2, 2)
        )
        assertEquals(
            "cancelled",
            ChatOriginalSourcePolicy.fenceFailure("uid", "uid", 1, 1, true, 2, 3)
        )
    }

    @Test
    fun acceptsExplicitLocalSourcesWithoutGuessingContentPaths() {
        assertEquals("content", ChatOriginalSourcePolicy.validate("content://documents/item/42").scheme)
        assertEquals(
            "/storage/emulated/0/Pictures/original.jpg",
            ChatOriginalSourcePolicy.validate("file:///storage/emulated/0/Pictures/original.jpg").path
        )
    }

    @Test
    fun rejectsNetworkRelativeOpaqueAndAmbiguousReferences() {
        for (value in listOf(
            "", "/storage/file.jpg", "https://example.com/file",
            "content:item", "content:///item", "content://user@documents/item",
            "content://documents/item#fragment", "file:relative", "file://server/share/file",
            "file:///storage/../private/file", "file:///storage/%2e%2e/private/file",
            "file:///storage/./file", "file:///storage/file?redirect=other",
            "file:///storage/a%5cb", "file:///storage/a%00b"
        )) {
            assertThrows("Reference must be rejected: $value", Exception::class.java) {
                ChatOriginalSourcePolicy.validate(value)
            }
        }
    }

    @Test
    fun missingFileCannotBeTreatedAsAnOriginal() {
        assertThrows(java.io.FileNotFoundException::class.java) {
            ChatOriginalSourcePolicy.existingFile(
                ChatOriginalSourcePolicy.validate(
                    java.io.File(
                        System.getProperty("user.dir"),
                        "__missing_original_source_policy_test__/file.jpg"
                    ).toURI().toString()
                )
            )
        }
    }
}
