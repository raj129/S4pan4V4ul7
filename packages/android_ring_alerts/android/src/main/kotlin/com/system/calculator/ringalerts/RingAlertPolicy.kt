package com.system.calculator.ringalerts

internal enum class RingAlertSource {
    SYSTEM,
    CUSTOM,
}

internal enum class SystemRingerMode {
    NORMAL,
    VIBRATE,
    SILENT,
    UNKNOWN,
}

internal enum class RingAlertOutput {
    RING_AND_VIBRATE,
    RING,
    VIBRATE,
    SILENT,
}

internal enum class RingVibrationUsage {
    NOTIFICATION,
    ALARM,
    RINGTONE,
}

internal object RingAlertPolicy {
    fun vibrationRepeatIndex(repeat: Boolean): Int = if (repeat) 0 else -1

    fun vibrationUsage(
        source: RingAlertSource,
        notificationAudioUsage: Boolean,
    ): RingVibrationUsage = when {
        source == RingAlertSource.CUSTOM -> RingVibrationUsage.ALARM
        notificationAudioUsage -> RingVibrationUsage.NOTIFICATION
        else -> RingVibrationUsage.RINGTONE
    }

    fun resolve(
        source: RingAlertSource,
        ringSoundEnabled: Boolean,
        vibrationEnabled: Boolean,
        systemMode: SystemRingerMode,
        systemVibratesWhenRinging: Boolean,
        doNotDisturb: Boolean = false,
    ): RingAlertOutput {
        if (doNotDisturb) return RingAlertOutput.SILENT

        if (source == RingAlertSource.CUSTOM) {
            return when {
                ringSoundEnabled && vibrationEnabled ->
                    RingAlertOutput.RING_AND_VIBRATE
                ringSoundEnabled -> RingAlertOutput.RING
                vibrationEnabled -> RingAlertOutput.VIBRATE
                else -> RingAlertOutput.SILENT
            }
        }

        if (systemMode == SystemRingerMode.SILENT ||
            systemMode == SystemRingerMode.UNKNOWN
        ) {
            return RingAlertOutput.SILENT
        }

        return when (systemMode) {
            SystemRingerMode.NORMAL -> if (systemVibratesWhenRinging) {
                RingAlertOutput.RING_AND_VIBRATE
            } else {
                RingAlertOutput.RING
            }
            SystemRingerMode.VIBRATE -> RingAlertOutput.VIBRATE
            SystemRingerMode.SILENT,
            SystemRingerMode.UNKNOWN -> RingAlertOutput.SILENT
        }
    }

    fun flashlightEnabled(
        source: RingAlertSource,
        appFlashlightEnabled: Boolean,
        systemFlashlightEnabled: Boolean,
        doNotDisturb: Boolean,
    ): Boolean = !doNotDisturb &&
        if (source == RingAlertSource.SYSTEM) {
            systemFlashlightEnabled
        } else {
            appFlashlightEnabled
        }

    fun parseSource(value: String?): RingAlertSource =
        if (value == "custom") RingAlertSource.CUSTOM else RingAlertSource.SYSTEM

}
