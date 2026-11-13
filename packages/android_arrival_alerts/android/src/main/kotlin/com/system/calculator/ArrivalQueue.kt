package com.system.calculator

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Durable queue shared by foreground and headless engines. Each entry stays until Dart acks it,
 * so a send that fails (offline, signed out) is retried by the next worker run.
 */
object ArrivalQueue {
    const val PREFS = "arrival_geofence"
    private const val KEY_PENDING = "pending"
    private val lock = Any()

    fun add(context: Context, alertId: String, lat: Double?, lng: Double?, timestampMs: Long) {
        synchronized(lock) {
            val entry = JSONObject()
                .put("eid", UUID.randomUUID().toString())
                .put("id", alertId)
                .put("ts", timestampMs)
            if (lat != null && lng != null) entry.put("lat", lat).put("lng", lng)
            val array = read(context)
            array.put(entry)
            write(context, array)
        }
    }

    fun peek(context: Context): List<JSONObject> = synchronized(lock) {
        val array = read(context)
        List(array.length()) { array.getJSONObject(it) }
    }

    fun ack(context: Context, eids: Collection<String>) {
        if (eids.isEmpty()) return
        synchronized(lock) {
            val array = read(context)
            val kept = JSONArray()
            for (i in 0 until array.length()) {
                val entry = array.getJSONObject(i)
                if (entry.getString("eid") !in eids) kept.put(entry)
            }
            write(context, kept)
        }
    }

    private fun read(context: Context): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PENDING, null) ?: return JSONArray()
        return JSONArray(raw)
    }

    private fun write(context: Context, array: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_PENDING, array.toString()).apply()
    }
}
