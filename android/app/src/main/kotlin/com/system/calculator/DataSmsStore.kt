package com.system.calculator

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

internal class DataSmsStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "data_sms.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE incoming (id TEXT NOT NULL, source TEXT NOT NULL, total INTEGER NOT NULL, created INTEGER NOT NULL, PRIMARY KEY(id, source))")
        db.execSQL("CREATE TABLE parts (id TEXT NOT NULL, source TEXT NOT NULL, idx INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(id, source, idx))")
        db.execSQL("CREATE TABLE outgoing (id TEXT PRIMARY KEY NOT NULL, phone TEXT NOT NULL, total INTEGER NOT NULL, created INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE segments (id TEXT NOT NULL, idx INTEGER NOT NULL, submit TEXT NOT NULL, sent TEXT NOT NULL, delivery TEXT NOT NULL, error TEXT, PRIMARY KEY(id, idx))")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    private fun expire(db: SQLiteDatabase) {
        val cutoff = (System.currentTimeMillis() - EXPIRY_MS).toString()
        db.execSQL("DELETE FROM parts WHERE EXISTS (SELECT 1 FROM incoming WHERE incoming.id=parts.id AND incoming.source=parts.source AND incoming.created < ?)", arrayOf(cutoff))
        db.delete("incoming", "created < ?", arrayOf(cutoff))
        db.execSQL("DELETE FROM segments WHERE EXISTS (SELECT 1 FROM outgoing WHERE outgoing.id=segments.id AND outgoing.created < ?)", arrayOf(cutoff))
        db.delete("outgoing", "created < ?", arrayOf(cutoff))
    }

    fun receive(source: String, part: DataSmsProtocol.Part) = synchronized(lock) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            expire(db)
            var total: Int? = null
            db.rawQuery("SELECT total FROM incoming WHERE id=? AND source=?", arrayOf(part.id, source)).use {
                if (it.moveToFirst()) total = it.getInt(0)
            }
            if (total == null) {
                db.rawQuery("SELECT count(*) FROM incoming", null).use {
                    it.moveToFirst()
                    if (it.getInt(0) >= MAX_RECORDS) return@synchronized
                }
                db.insertOrThrow("incoming", null, ContentValues().apply {
                    put("id", part.id); put("source", source); put("total", part.total)
                    put("created", System.currentTimeMillis())
                })
            } else if (total != part.total) {
                return@synchronized
            }
            db.rawQuery("SELECT payload FROM parts WHERE id=? AND source=? AND idx=?",
                arrayOf(part.id, source, part.index.toString())).use {
                if (it.moveToFirst()) {
                    // A conflicting duplicate is rejected without replacing the original.
                    return@synchronized
                }
            }
            db.insertOrThrow("parts", null, ContentValues().apply {
                put("id", part.id); put("source", source); put("idx", part.index)
                put("payload", part.payload)
            })
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun createOutgoing(id: String, phone: String, count: Int) = synchronized(lock) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            expire(db)
            db.rawQuery("SELECT count(*) FROM outgoing", null).use {
                it.moveToFirst()
                check(it.getInt(0) < MAX_RECORDS) { "Outgoing SMS queue is full" }
            }
            db.insertOrThrow("outgoing", null, ContentValues().apply {
                put("id", id); put("phone", phone); put("total", count)
                put("created", System.currentTimeMillis())
            })
            for (index in 0 until count) db.insertOrThrow("segments", null, ContentValues().apply {
                put("id", id); put("idx", index); put("submit", "not_submitted")
                put("sent", "pending"); put("delivery", "pending")
            })
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun submitState(id: String, index: Int, state: String, error: String? = null) =
        synchronized(lock) {
            writableDatabase.update("segments", ContentValues().apply {
                put("submit", state)
                if (error != null) put("error", error)
            }, "id=? AND idx=?", arrayOf(id, index.toString()))
        }

    fun callback(id: String, index: Int, kind: String, success: Boolean, code: Int) =
        synchronized(lock) {
            if (kind != "sent" && kind != "delivery") return@synchronized
            writableDatabase.update("segments", ContentValues().apply {
                put(kind, if (success) "success" else "failed")
                if (!success) put("error", "$kind result $code")
            }, "id=? AND idx=? AND $kind=?", arrayOf(id, index.toString(), "pending"))
        }

    fun acknowledge(id: String, source: String) = synchronized(lock) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            // Only completed assemblies may be acknowledged.
            val complete = db.rawQuery(
                "SELECT total=(SELECT count(*) FROM parts WHERE parts.id=incoming.id AND parts.source=incoming.source) FROM incoming WHERE id=? AND source=?",
                arrayOf(id, source)).use { it.moveToFirst() && it.getInt(0) == 1 }
            if (complete) {
                db.delete("parts", "id=? AND source=?", arrayOf(id, source))
                db.delete("incoming", "id=? AND source=?", arrayOf(id, source))
            }
            db.setTransactionSuccessful()
            complete
        } finally {
            db.endTransaction()
        }
    }

    fun acknowledgeOutgoing(id: String) = synchronized(lock) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val delivered = db.rawQuery(
                """SELECT total > 0
                    AND total = (SELECT count(*) FROM segments WHERE segments.id=outgoing.id)
                    AND NOT EXISTS (SELECT 1 FROM segments WHERE segments.id=outgoing.id
                        AND (submit='failed' OR sent='failed' OR delivery!='success'))
                    FROM outgoing WHERE id=?""",
                arrayOf(id)).use { it.moveToFirst() && it.getInt(0) == 1 }
            if (delivered) {
                db.delete("segments", "id=?", arrayOf(id))
                db.delete("outgoing", "id=?", arrayOf(id))
            }
            db.setTransactionSuccessful()
            delivered
        } finally {
            db.endTransaction()
        }
    }

    fun snapshot(): Map<String, Any> = synchronized(lock) {
        val db = writableDatabase
        expire(db)
        val incoming = mutableListOf<Map<String, Any>>()
        db.rawQuery("SELECT id, source, total FROM incoming ORDER BY created", null).use { rows ->
            while (rows.moveToNext()) {
                val id = rows.getString(0); val source = rows.getString(1); val total = rows.getInt(2)
                val chunks = mutableListOf<ByteArray>()
                db.rawQuery("SELECT payload FROM parts WHERE id=? AND source=? ORDER BY idx", arrayOf(id, source)).use {
                    while (it.moveToNext()) chunks.add(it.getBlob(0))
                }
                if (chunks.size == total) {
                    val payload = ByteArray(chunks.sumOf { it.size })
                    var offset = 0
                    chunks.forEach { it.copyInto(payload, offset); offset += it.size }
                    incoming.add(mapOf("id" to id, "phone" to source, "payload" to payload))
                }
            }
        }
        val outgoing = mutableListOf<Map<String, Any?>>()
        db.rawQuery("SELECT id, phone, created FROM outgoing ORDER BY created", null).use { rows ->
            while (rows.moveToNext()) {
                val id = rows.getString(0)
                val segments = mutableListOf<Map<String, Any?>>()
                db.rawQuery("SELECT idx, submit, sent, delivery, error FROM segments WHERE id=? ORDER BY idx", arrayOf(id)).use {
                    while (it.moveToNext()) segments.add(mapOf(
                        "index" to it.getInt(0), "submit" to it.getString(1),
                        "sent" to it.getString(2), "delivery" to it.getString(3),
                        "error" to if (it.isNull(4)) null else it.getString(4)))
                }
                val state = aggregate(segments, System.currentTimeMillis() - rows.getLong(2))
                outgoing.add(mapOf("id" to id, "phone" to rows.getString(1), "state" to state,
                    "segments" to segments, "error" to segments.firstOrNull { it["error"] != null }?.get("error")))
            }
        }
        mapOf("incoming" to incoming, "outgoing" to outgoing)
    }

    companion object {
        private val lock = Any()
        private const val MAX_RECORDS = 100
        private const val EXPIRY_MS = 7L * 24 * 60 * 60 * 1000
        private const val CALLBACK_WAIT_MS = 5L * 60 * 1000

        fun aggregate(segments: List<Map<String, Any?>>, ageMs: Long): String {
            if (segments.any { it["submit"] == "failed" || it["sent"] == "failed" }) {
                return if (segments.any { it["submit"] == "submitted" || it["sent"] == "success" }) "partial" else "failed"
            }
            if (segments.any { it["delivery"] == "failed" }) {
                return if (segments.any { it["delivery"] == "success" }) "partial" else "failed"
            }
            if (segments.all { it["delivery"] == "success" }) return "delivered"
            if (segments.all { it["sent"] == "success" }) return "unconfirmed"
            if (segments.any { it["submit"] == "submitting" } || ageMs >= CALLBACK_WAIT_MS) return "unconfirmed"
            return "sending"
        }
    }
}
