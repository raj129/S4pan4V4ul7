package com.system.calculator.ringalerts

import org.junit.Assert.assertEquals
import org.junit.Test

class RingAlertPolicyTest {
    @Test
    fun customRingAndVibrateOverridesPhoneVibrateMode() {
        assertEquals(
            RingAlertOutput.RING_AND_VIBRATE,
            RingAlertPolicy.resolve(
                source = RingAlertSource.CUSTOM,
                ringSoundEnabled = true,
                vibrationEnabled = true,
                systemMode = SystemRingerMode.VIBRATE,
                systemVibratesWhenRinging = true,
            ),
        )
    }

    @Test
    fun customRingOnlyOverridesPhoneVibrateMode() {
        assertEquals(
            RingAlertOutput.RING,
            RingAlertPolicy.resolve(
                source = RingAlertSource.CUSTOM,
                ringSoundEnabled = true,
                vibrationEnabled = false,
                systemMode = SystemRingerMode.VIBRATE,
                systemVibratesWhenRinging = false,
            ),
        )
    }

    @Test
    fun customVibrateDoesNotRingWhenSystemIsInNormalMode() {
        assertEquals(
            RingAlertOutput.VIBRATE,
            RingAlertPolicy.resolve(
                source = RingAlertSource.CUSTOM,
                ringSoundEnabled = false,
                vibrationEnabled = true,
                systemMode = SystemRingerMode.NORMAL,
                systemVibratesWhenRinging = false,
            ),
        )
    }

    @Test
    fun customOutputOverridesSilentRingerModeButDndStillSuppresses() {
        for (source in RingAlertSource.values()) {
            for (ringSoundEnabled in listOf(false, true)) {
                for (vibrationEnabled in listOf(false, true)) {
                    assertEquals(
                        if (source == RingAlertSource.CUSTOM &&
                            (ringSoundEnabled || vibrationEnabled)
                        ) {
                            when {
                                ringSoundEnabled && vibrationEnabled ->
                                    RingAlertOutput.RING_AND_VIBRATE
                                ringSoundEnabled -> RingAlertOutput.RING
                                else -> RingAlertOutput.VIBRATE
                            }
                        } else {
                            RingAlertOutput.SILENT
                        },
                        RingAlertPolicy.resolve(
                            source = source,
                            ringSoundEnabled = ringSoundEnabled,
                            vibrationEnabled = vibrationEnabled,
                            systemMode = SystemRingerMode.SILENT,
                            systemVibratesWhenRinging = true,
                        ),
                    )
                    assertEquals(
                        RingAlertOutput.SILENT,
                        RingAlertPolicy.resolve(
                            source = source,
                            ringSoundEnabled = ringSoundEnabled,
                            vibrationEnabled = vibrationEnabled,
                            systemMode = SystemRingerMode.NORMAL,
                            systemVibratesWhenRinging = true,
                            doNotDisturb = true,
                        ),
                    )
                }
            }
        }
    }

    @Test
    fun followSystemUsesRingerAndVibrateWhenRingingState() {
        assertEquals(
            RingAlertOutput.RING,
            RingAlertPolicy.resolve(
                source = RingAlertSource.SYSTEM,
                ringSoundEnabled = false,
                vibrationEnabled = false,
                systemMode = SystemRingerMode.NORMAL,
                systemVibratesWhenRinging = false,
            ),
        )
        assertEquals(
            RingAlertOutput.RING_AND_VIBRATE,
            RingAlertPolicy.resolve(
                source = RingAlertSource.SYSTEM,
                ringSoundEnabled = false,
                vibrationEnabled = false,
                systemMode = SystemRingerMode.NORMAL,
                systemVibratesWhenRinging = true,
            ),
        )
    }

    @Test
    fun customCombinedModeUsesSelectedOutputsRegardlessOfSystemVibrateSetting() {
        assertEquals(
            RingAlertOutput.RING_AND_VIBRATE,
            RingAlertPolicy.resolve(
                source = RingAlertSource.CUSTOM,
                ringSoundEnabled = true,
                vibrationEnabled = true,
                systemMode = SystemRingerMode.NORMAL,
                systemVibratesWhenRinging = false,
            ),
        )
    }

    @Test
    fun allCustomOutputsOffProducesSilence() {
        assertEquals(
            RingAlertOutput.SILENT,
            RingAlertPolicy.resolve(
                source = RingAlertSource.CUSTOM,
                ringSoundEnabled = false,
                vibrationEnabled = false,
                systemMode = SystemRingerMode.NORMAL,
                systemVibratesWhenRinging = true,
            ),
        )
    }

    @Test
    fun followSystemFlashUsesAndroidSettingOnlyAndIsDndAware() {
        assertEquals(
            true,
            RingAlertPolicy.flashlightEnabled(
                source = RingAlertSource.SYSTEM,
                appFlashlightEnabled = false,
                systemFlashlightEnabled = true,
                doNotDisturb = false,
            ),
        )
        assertEquals(
            false,
            RingAlertPolicy.flashlightEnabled(
                source = RingAlertSource.SYSTEM,
                appFlashlightEnabled = true,
                systemFlashlightEnabled = false,
                doNotDisturb = false,
            ),
        )
        assertEquals(
            false,
            RingAlertPolicy.flashlightEnabled(
                source = RingAlertSource.CUSTOM,
                appFlashlightEnabled = true,
                systemFlashlightEnabled = false,
                doNotDisturb = true,
            ),
        )
    }
}
