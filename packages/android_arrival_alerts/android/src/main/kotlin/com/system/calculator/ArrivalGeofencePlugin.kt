package com.system.calculator

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Registers arrival places with the OS geofencing service, so arrival alerts
 * need no continuous GPS stream. Enter events are queued by
 * [ArrivalGeofenceReceiver] and drained by a headless Dart worker. Flutter
 * registers this plugin on both the activity and Workmanager engines.
 */
class ArrivalGeofencePlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        appContext = context
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result -> handle(context, call, result) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sync" -> {
                @Suppress("UNCHECKED_CAST")
                val fences = call.argument<List<Map<String, Any>>>("fences").orEmpty()
                sync(context, fences, result)
            }
            "peekPending" -> result.success(peekPending(context))
            "ackPending" -> {
                val eids = call.argument<List<String>>("eids").orEmpty()
                ArrivalQueue.ack(context, eids)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Replaces every registered fence with [fences]. An empty list clears them. */
    private fun sync(context: Context, fences: List<Map<String, Any>>, result: MethodChannel.Result) {
        val client = LocationServices.getGeofencingClient(context)
        val intent = pendingIntent(context)
        client.removeGeofences(intent).addOnCompleteListener {
            if (fences.isEmpty()) {
                result.success(null)
                return@addOnCompleteListener
            }
            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(fences.map { toGeofence(it) })
                .build()
            addFences(client, request, intent, result)
        }
    }

    private fun addFences(
        client: GeofencingClient,
        request: GeofencingRequest,
        intent: PendingIntent,
        result: MethodChannel.Result,
    ) {
        client.addGeofences(request, intent)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error("geofence_failed", error.message, null)
            }
    }

    private fun toGeofence(fence: Map<String, Any>): Geofence {
        val radius = (fence["radius"] as Number).toFloat().coerceAtLeast(MIN_RADIUS_METERS)
        return Geofence.Builder()
            .setRequestId(fence["id"] as String)
            .setCircularRegion(
                (fence["lat"] as Number).toDouble(),
                (fence["lng"] as Number).toDouble(),
                radius,
            )
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
            .build()
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, ArrivalGeofenceReceiver::class.java)
        // Mutable so Play services can attach the transition details.
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    private fun peekPending(context: Context): List<Map<String, Any>> =
        ArrivalQueue.peek(context).map { entry ->
            val map = mutableMapOf<String, Any>(
                "eid" to entry.getString("eid"),
                "id" to entry.getString("id"),
                "ts" to entry.getLong("ts"),
            )
            if (entry.has("lat") && entry.has("lng")) {
                map["lat"] = entry.getDouble("lat")
                map["lng"] = entry.getDouble("lng")
            }
            map
        }

    companion object {
        const val CHANNEL = "photo_vault/arrival_geofence"
        private const val REQUEST_CODE = 4217
        // Android rejects geofences smaller than 100 m.
        private const val MIN_RADIUS_METERS = 100f
    }
}
