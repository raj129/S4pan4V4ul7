package com.system.calculator

import org.junit.Assert.assertEquals
import org.junit.Test

class DataSmsStatusTest {
    private fun segment(submit: String, sent: String, delivery: String): Map<String, Any?> =
        mapOf("submit" to submit, "sent" to sent, "delivery" to delivery)

    @Test fun aggregatesWithoutClaimingDelivery() {
        val waiting = segment("submitted", "pending", "pending")
        val accepted = segment("submitted", "success", "pending")
        val delivered = segment("submitted", "success", "success")
        val failed = segment("failed", "pending", "pending")
        assertEquals("sending", DataSmsStore.aggregate(listOf(waiting), 0))
        assertEquals("unconfirmed", DataSmsStore.aggregate(listOf(waiting), 300_000))
        assertEquals("unconfirmed", DataSmsStore.aggregate(listOf(accepted), 0))
        assertEquals("delivered", DataSmsStore.aggregate(listOf(delivered, delivered), 0))
        assertEquals("partial", DataSmsStore.aggregate(listOf(accepted, failed), 0))
        assertEquals("unconfirmed", DataSmsStore.aggregate(
            listOf(segment("submitting", "pending", "pending")), 0))
    }
}
