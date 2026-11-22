package com.system.calculator

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HighRefreshRateTest {
    @Test
    fun selectsHighestRefreshRateAtCurrentResolution() {
        val modes = listOf(
            DisplayModeCandidate(modeId = 1, physicalWidth = 1080, physicalHeight = 2400, refreshRate = 60f),
            DisplayModeCandidate(modeId = 2, physicalWidth = 1080, physicalHeight = 2400, refreshRate = 90f),
            DisplayModeCandidate(modeId = 3, physicalWidth = 1080, physicalHeight = 2400, refreshRate = 120f),
            DisplayModeCandidate(modeId = 4, physicalWidth = 1440, physicalHeight = 3200, refreshRate = 144f),
        )

        val selected = selectBestMode(
            currentWidth = 1080,
            currentHeight = 2400,
            modes = modes,
        )

        assertEquals(3, selected?.modeId)
        assertEquals(120f, selected?.refreshRate)
    }

    @Test
    fun returnsNullWhenNoModeMatchesCurrentResolution() {
        val modes = listOf(
            DisplayModeCandidate(modeId = 1, physicalWidth = 1440, physicalHeight = 3200, refreshRate = 120f),
        )

        val selected = selectBestMode(
            currentWidth = 1080,
            currentHeight = 2400,
            modes = modes,
        )

        assertNull(selected)
    }
}
