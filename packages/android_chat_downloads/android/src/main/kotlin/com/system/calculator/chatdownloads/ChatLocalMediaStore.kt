package com.system.calculator.chatdownloads

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.StatFs
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Completion means durable ciphertext bytes, not payload GCM authentication; preview/import authenticates. */
internal class ChatLocalMediaStore private constructor(context: Context) : SQLiteOpenHelper(
    context, File(context.noBackupFilesDir, "chat_local_media.db").path, null, 1
) {
    private val root = context.noBackupFilesDir
    private val received = directory("chat_received_media")
    private val sent = directory("chat_sent_media")
    private val sealKey: SecretKey by lazy {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keys.getKey("chat_local_media_index_v1", null) as? SecretKey)
            ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
                init(
                    KeyGenParameterSpec.Builder(
                        "chat_local_media_index_v1",
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build()
                )
                generateKey()
            }
    }

    override fun onConfigure(db: SQLiteDatabase) {
        db.execSQL("PRAGMA synchronous=FULL")
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE media(id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        throw LocalMediaException("local_media_unavailable")
    }

    private fun directory(name: String): File = File(root, name).apply {
        if (!isDirectory) {
            if (!mkdirs()) throw LocalMediaException("local_media_unavailable")
            syncDirectory(root)
        }
    }

    private fun file(entry: JSONObject, partial: Boolean = false): File {
        val id = entry.getString("id")
        if (!id.matches(Regex("[0-9a-f]{64}"))) throw LocalMediaException("local_media_corrupt")
        val dir = when (entry.getString("direction")) {
            "received" -> received
            "sent" -> sent
            else -> throw LocalMediaException("local_media_corrupt")
        }
        return File(dir, "$id.${if (partial) "part" else "enc"}")
    }

    private fun save(entry: JSONObject) {
        val id = entry.getString("id")
        val plain = entry.toString().toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, sealKey)
            cipher.updateAAD(id.toByteArray(Charsets.UTF_8))
            val values = ContentValues().apply {
                put("id", id)
                put("payload", cipher.iv + cipher.doFinal(plain))
            }
            if (writableDatabase.insertWithOnConflict(
                    "media", null, values,
                    SQLiteDatabase.CONFLICT_REPLACE
                ) == -1L
            ) {
                throw LocalMediaException("local_media_unavailable")
            }
        } finally {
            plain.fill(0)
        }
    }

    private fun get(id: String): JSONObject? = readableDatabase.query(
        "media", arrayOf("payload"), "id=?", arrayOf(id), null, null, null
    ).use { cursor ->
        if (!cursor.moveToFirst()) return null
        val sealed = cursor.getBlob(0)
        try {
            if (sealed.size < 29) throw LocalMediaException("local_media_corrupt")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, sealKey, GCMParameterSpec(128, sealed.copyOfRange(0, 12)))
            cipher.updateAAD(id.toByteArray(Charsets.UTF_8))
            val plain = cipher.doFinal(sealed, 12, sealed.size - 12)
            try {
                JSONObject(String(plain, Charsets.UTF_8)).also {
                    if (it.getString("id") != id ||
                        ChatLocalMediaPolicy.identity(it.getString("uid"), it.getString("path")) != id
                    ) {
                        throw LocalMediaException("local_media_corrupt")
                    }
                    file(it)
                }
            } finally {
                plain.fill(0)
            }
        } catch (error: LocalMediaException) {
            throw error
        } catch (_: Exception) {
            throw LocalMediaException("local_media_corrupt")
        } finally {
            sealed.fill(0)
        }
    }

    private fun all(): List<JSONObject> {
        val ids = readableDatabase.query("media", arrayOf("id"), null, null, null, null, null)
            .use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
        return ids.map { get(it) ?: throw LocalMediaException("local_media_corrupt") }
    }

    private fun syncDirectory(dir: File) {
        val fd = Os.open(dir.path, OsConstants.O_RDONLY, 0)
        try {
            Os.fsync(fd)
        } finally {
            Os.close(fd)
        }
    }

    private fun delete(file: File) {
        if (file.exists()) {
            if (!file.delete()) throw LocalMediaException("local_media_unavailable")
            syncDirectory(file.parentFile!!)
        }
    }

    private fun valid(entry: JSONObject, partial: Boolean = false): Boolean =
        ChatLocalMediaPolicy.valid(file(entry, partial), entry.getLong("size"), entry.getString("digest"))

    private fun recover() {
        val entries = all()
        for (entry in entries) {
            when (entry.getString("state")) {
                "intent" -> {
                    val recovery = ChatLocalMediaPolicy.recovery("intent", valid(entry), valid(entry, true))
                    if (recovery == "promote") {
                        delete(file(entry))
                        ChatLocalMediaPolicy.promote(
                            file(entry, true), file(entry),
                            entry.getLong("size"), entry.getString("digest")
                        )
                        syncDirectory(file(entry).parentFile!!)
                    }
                    entry.put("state", if (recovery == "promote") "complete" else recovery)
                    save(entry)
                }

                "complete" -> {
                    // Verify full digest on read, but expose missing/truncated completed files as corruption.
                    if (!file(entry).isFile || file(entry).length() != entry.getLong("size")) {
                        entry.put("state", "invalid")
                        save(entry)
                    }
                }

                "moved", "absent", "invalid" -> delete(file(entry))
                else -> throw LocalMediaException("local_media_corrupt")
            }
            delete(file(entry, true))
        }
        for (dir in listOf(received, sent)) {
            val retained = entries.filter { it.getString("state") == "complete" }
                .map { file(it).absolutePath }.toSet()
            for (orphan in dir.listFiles() ?: throw LocalMediaException("local_media_unavailable")) {
                if (orphan.name.matches(Regex("[0-9a-f]{64}\\.(enc|part)")) &&
                    orphan.absolutePath !in retained
                ) delete(orphan)
            }
        }
    }

    fun read(uid: String, path: String, direction: String): ByteArray? {
        ChatLocalMediaPolicy.direction(direction)
        val entry = get(ChatLocalMediaPolicy.identity(uid, path)) ?: return null
        if (!ChatLocalMediaPolicy.readable(entry.getString("state"), entry.getString("direction"), direction)) {
            return null
        }
        val size = entry.getLong("size")
        if (size !in 29..ChatLocalMediaPolicy.MAX_BYTES || file(entry).length() != size) {
            throw LocalMediaException("local_media_corrupt")
        }
        val bytes = file(entry).readBytes()
        if (bytes.size.toLong() != size || ChatLocalMediaPolicy.digest(bytes) != entry.getString("digest")) {
            bytes.fill(0)
            throw LocalMediaException("local_media_corrupt")
        }
        return bytes
    }

    fun metadata(uid: String, path: String): Map<String, Any>? {
        val entry = get(ChatLocalMediaPolicy.identity(uid, path)) ?: return null
        if (entry.getString("state") == "absent") return null
        // Damaged ciphertext must not hide a sent file's independently sealed source.
        // Reads still reject invalid bytes, while explicit received repair can remove them.
        return buildMap {
            put("direction", entry.getString("direction"))
            put("moved", entry.getString("state") == "moved")
            if (entry.has("size")) put("size", entry.getLong("size"))
            if (entry.has("digest")) put("digest", entry.getString("digest"))
            for (key in listOf("sourceUri", "sourceDigest", "sourceFlags")) {
                if (entry.has(key)) put(key, entry.get(key))
            }
        }
    }

    fun put(
        uid: String, path: String, direction: String, bytes: ByteArray,
        sourceUri: String?, sourceDigest: String?, sourceFlags: Int?
    ) {
        val id = ChatLocalMediaPolicy.identity(uid, path)
        ChatLocalMediaPolicy.size(bytes.size.toLong())
        ChatLocalMediaPolicy.direction(direction)
        val old = get(id)
        ChatLocalMediaPolicy.writable(old?.getString("state"), old?.getString("direction"), direction)
        if (sourceUri != null) {
            if (direction != "sent") throw LocalMediaException("local_media_invalid_source")
            ChatLocalMediaPolicy.sourceUri(sourceUri)
        }
        if (sourceDigest != null && !sourceDigest.matches(Regex("[0-9a-fA-F]{64}"))) {
            throw LocalMediaException("local_media_invalid_source")
        }
        if (sourceFlags != null && sourceFlags < 0) throw LocalMediaException("local_media_invalid_source")
        val digest = ChatLocalMediaPolicy.digest(bytes)
        if (old != null && old.getString("state") != "absent" && old.optString("digest") != digest) {
            throw LocalMediaException("local_media_identity_conflict")
        }
        val entry = JSONObject().put("id", id).put("uid", uid).put("path", path)
            .put("direction", direction).put("size", bytes.size.toLong()).put("digest", digest)
        for (key in listOf("sourceUri", "sourceDigest", "sourceFlags")) {
            if (old?.has(key) == true) entry.put(key, old.get(key))
        }
        if (sourceUri != null) entry.put("sourceUri", sourceUri)
        if (sourceDigest != null) entry.put("sourceDigest", sourceDigest.lowercase())
        if (sourceFlags != null) entry.put("sourceFlags", sourceFlags)
        if (old?.getString("state") == "complete" && valid(old)) {
            entry.put("state", "complete")
            save(entry)
            return
        }
        val used = all().filter { it.getString("id") != id && it.getString("state") == "complete" }
            .sumOf { it.getLong("size") }
        ChatLocalMediaPolicy.reserve(used, bytes.size.toLong(), StatFs(root.path).availableBytes)
        // Persist the intent before any new bytes. Interrupted writes cannot look complete.
        entry.put("state", "intent")
        save(entry)
        delete(file(entry))
        ChatLocalMediaPolicy.writePartial(file(entry, true), bytes)
        ChatLocalMediaPolicy.promote(file(entry, true), file(entry), bytes.size.toLong(), digest)
        syncDirectory(file(entry).parentFile!!)
        entry.put("state", "complete")
        save(entry)
    }

    fun remove(uid: String, path: String, moved: Boolean = false) {
        val id = ChatLocalMediaPolicy.identity(uid, path)
        val entry = get(id) ?: if (moved) JSONObject().put("id", id).put("uid", uid)
            .put("path", path).put("direction", "received") else return
        entry.put("state", ChatLocalMediaPolicy.removalState(entry.optString("state"), moved))
        if (!ChatLocalMediaPolicy.retainSourceOnRemoval(entry.getString("direction"), moved)) {
            for (key in listOf("sourceUri", "sourceDigest", "sourceFlags")) entry.remove(key)
        }
        // Tombstone first: restart cleanup is safe even if deletion is interrupted.
        save(entry)
        delete(file(entry))
        delete(file(entry, true))
    }

    fun clear(uid: String) {
        for (entry in all().filter { it.getString("uid") == uid }) {
            remove(uid, entry.getString("path"))
            if (entry.getString("state") != "moved") {
                writableDatabase.delete("media", "id=?", arrayOf(entry.getString("id")))
            }
        }
    }

    companion object {
        private val monitor = Any()
        fun <T> locked(context: Context, action: (ChatLocalMediaStore) -> T): T = synchronized(monitor) {
            RandomAccessFile(File(context.noBackupFilesDir, "chat_local_media.lock"), "rw").use { lock ->
                lock.channel.lock().use {
                    ChatLocalMediaStore(context).use { store ->
                        store.recover()
                        action(store)
                    }
                }
            }
        }
    }
}
