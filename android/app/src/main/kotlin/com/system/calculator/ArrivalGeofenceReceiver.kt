package com.system.calculator

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/**
 * Receives OS geofence enter events while the app process may be dead, and
 * queues the triggering alert ids. Chat messages need Dart and encryption, so
 * they are sent when the app next runs.
 */
class ArrivalGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) {
            return
        }
        val location = event.triggeringLocation
        val now = System.currentTimeMillis()
        for (geofence in event.triggeringGeofences.orEmpty()) {
            ArrivalQueue.add(
                context,
                geofence.requestId,
                location?.latitude,
                location?.longitude,
                now,
            )
        }
        ArrivalSendScheduler.enqueue(context)
    }
}
