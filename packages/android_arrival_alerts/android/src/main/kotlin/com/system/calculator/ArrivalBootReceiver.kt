package com.system.calculator

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms OS geofences after device reboot or app update, since Android
 * clears registered GeofencingClient fences on both events.
 */
class ArrivalBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        ArrivalSendScheduler.enqueue(context)
    }
}
