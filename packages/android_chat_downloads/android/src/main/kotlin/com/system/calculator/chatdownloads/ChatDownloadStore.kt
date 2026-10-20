package com.system.calculator.chatdownloads

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class ChatDownloadStore(context: Context) : SQLiteOpenHelper(
    context, File(context.noBackupFilesDir, "chat_downloads.db").path, null, 1
) {
    val directory = File(context.noBackupFilesDir, "chat_downloads").apply {
        check(isDirectory || mkdirs()) { "Download storage unavailable" }
    }
    private val sealKey: SecretKey by lazy {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("chat_download_journal_v1", null) as? SecretKey)
            ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
                init(
                    KeyGenParameterSpec.Builder(
                        "chat_download_journal_v1",
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build()
                )
                generateKey()
            }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE jobs(id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) =
        throw IllegalStateException("Unsupported download journal version")

    fun id(uid: String, path: String) = MessageDigest.getInstance("SHA-256")
        .digest("$uid\n$path".toByteArray()).joinToString("") { "%02x".format(it) }

    fun blob(id: String): File {
        require(id.matches(Regex("[0-9a-f]{64}")))
        return File(directory, "$id.enc")
    }

    fun put(job: JSONObject) {
        val id = job.getString("id")
        blob(id)
        val plain = job.toString().toByteArray()
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, sealKey)
            cipher.updateAAD(id.toByteArray())
            val values = ContentValues().apply {
                put("id", id)
                put("payload", cipher.iv + cipher.doFinal(plain))
            }
            check(
                writableDatabase.insertWithOnConflict(
                    "jobs", null, values,
                    SQLiteDatabase.CONFLICT_REPLACE
                ) != -1L
            ) { "Download journal write failed" }
        } finally {
            plain.fill(0)
        }
    }

    fun get(id: String): JSONObject? = readableDatabase.query(
        "jobs", arrayOf("payload"), "id=?", arrayOf(id), null, null, null
    ).use { cursor ->
        if (!cursor.moveToFirst()) return null
        val sealed = cursor.getBlob(0)
        check(sealed.size >= 28) { "Download journal is corrupted" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, sealKey, GCMParameterSpec(128, sealed.copyOfRange(0, 12)))
        cipher.updateAAD(id.toByteArray())
        val plain = cipher.doFinal(sealed, 12, sealed.size - 12)
        try {
            JSONObject(String(plain))
        } finally {
            plain.fill(0)
        }
    }

    fun all(): List<JSONObject> {
        val ids = readableDatabase.query("jobs", arrayOf("id"), null, null, null, null, null)
            .use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
        return ids.mapNotNull { get(it) }.sortedBy { it.optLong("createdAt") }
    }

    fun remove(id: String) {
        deleteBlob(id)
        writableDatabase.delete("jobs", "id=?", arrayOf(id))
    }

    fun deleteBlob(id: String) {
        val file = blob(id)
        check(!file.exists() || file.delete()) { "Download cleanup failed" }
    }

    fun reserve(bytes: Long, id: String) {
        pruneAcknowledged()
        val used = directory.listFiles()?.filter { it.extension == "enc" && it.nameWithoutExtension != id }
            ?.sumOf { it.length() } ?: throw java.io.IOException("Download storage unavailable")
        check(bytes in 29..ChatDownloadPolicy.MAX_BYTES && used + bytes <= 192L * 1024 * 1024) {
            "Encrypted download storage is full; cancel older downloads"
        }
        val available = android.os.StatFs(directory.path).availableBytes
        check(available >= maxOf(0, bytes - blob(id).length()) + 4L * 1024 * 1024) {
            "Device storage is full; free space and retry"
        }
    }

    fun pruneAcknowledged(): Long? {
        val now = System.currentTimeMillis()
        var next: Long? = null
        for (job in all()) {
            val acknowledged = job.optLong("acknowledgedAt")
            if (acknowledged == 0L) continue
            val remaining = acknowledged + 120_000L - now
            if (remaining <= 0) remove(job.getString("id"))
            else next = minOf(next ?: remaining, remaining)
        }
        return next
    }

    fun reconcile() {
        val now = System.currentTimeMillis()
        for (job in all()) {
            val id = job.getString("id")
            val acknowledged = job.optLong("acknowledgedAt")
            if ((acknowledged > 0 && now - acknowledged > 120_000) ||
                now - job.optLong("updatedAt", now) > 7L * 24 * 60 * 60 * 1000
            ) {
                remove(id)
                continue
            }
            val file = blob(id)
            val offset = ChatDownloadPolicy.recoveredOffset(
                job.optLong("processedBytes"), file.length(), job.optLong("totalBytes")
            )
            if (file.exists()) RandomAccessFile(file, "rw").use { it.setLength(offset) }
            job.put("processedBytes", offset)
            if (job.getString("state") == "uploading") job.put("state", "queued")
            if (job.getString("state") == "completed" && offset != job.optLong("totalBytes")) {
                job.put("state", "retrying")
            }
            put(job)
        }
        val retained = all().map { "${it.getString("id")}.enc" }.toSet()
        for (file in directory.listFiles() ?: throw java.io.IOException("Download storage unavailable")) {
            if (file.extension == "enc" && file.name !in retained) {
                check(file.delete()) { "Orphan download cleanup failed" }
            }
        }
    }
}
