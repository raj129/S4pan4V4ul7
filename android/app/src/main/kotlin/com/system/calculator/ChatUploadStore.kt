package com.system.calculator

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteOpenHelper
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only ciphertext files and Keystore-sealed journal metadata survive a crash. */
class ChatUploadStore(context: Context) : SQLiteOpenHelper(
    context, File(context.noBackupFilesDir, "chat_uploads.db").path, null, 1
) {
    val directory = File(context.noBackupFilesDir, "chat_uploads").apply { mkdirs() }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE jobs(id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) =
        throw IllegalStateException("Unsupported upload journal version")

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("chat_upload_journal_v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder("chat_upload_journal_v1",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }
    @Synchronized fun put(job: JSONObject) {
        val id = job.getString("messageId")
        require(id.matches(Regex("[A-Za-z0-9-]{1,128}")))
        val plain = job.toString().toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            cipher.updateAAD(id.toByteArray())
            val values = ContentValues().apply {
                put("id", id)
                put("payload", cipher.iv + cipher.doFinal(plain))
            }
            writableDatabase.insertWithOnConflict("jobs", null, values,
                SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
        } finally { plain.fill(0) }
    }
    @Synchronized fun get(id: String): JSONObject? =
        readableDatabase.query("jobs", arrayOf("payload"), "id=?", arrayOf(id),
            null, null, null).use { cursor ->
            if (!cursor.moveToFirst()) return null
            val bytes = cursor.getBlob(0)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.updateAAD(id.toByteArray())
            val plain = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
            try { JSONObject(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
        }
    @Synchronized fun all(): List<JSONObject> {
        val ids = readableDatabase.query("jobs", arrayOf("id"), null, null, null, null, null)
            .use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
        return ids.mapNotNull { get(it) }.sortedBy { it.optLong("sentAt") }
    }
    fun acknowledge(id: String) {
        writableDatabase.delete("jobs", "id=?", arrayOf(id))
    }
    fun blob(id: String, thumb: Boolean = false) =
        File(directory, "$id.${if (thumb) "thumb" else "media"}.enc")

    /** A committed journal owns staging files; crash-before-commit files do not. */
    fun reconcile() {
        val retained = all().filter { it.getString("state") !in listOf("completed", "cancelled") }
            .flatMap { listOf(blob(it.getString("messageId")).name, blob(it.getString("messageId"), true).name) }.toSet()
        for (file in directory.listFiles() ?: throw java.io.IOException("Upload staging directory unavailable")) {
            if (file.name != "owner.lock" &&
                (file.name.endsWith(".part") || (file.name.endsWith(".enc") && file.name !in retained))) {
                check(file.delete() || !file.exists()) { "Could not remove unused encrypted staging file" }
            }
        }
    }

    fun stage(id: String, bytes: ByteArray, thumb: Boolean = false) {
        require(bytes.size in 29 until 64 * 1024 * 1024)
        val target = blob(id, thumb)
        val part = File("${target.path}.part")
        try {
            part.outputStream().use { output -> output.write(bytes); output.flush() }
            java.io.RandomAccessFile(part, "rw").use { it.fd.sync() }
            check(part.renameTo(target)) { "Could not stage encrypted attachment" }
        } finally { if (part.exists()) part.delete() }
    }
}
