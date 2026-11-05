package com.yutan123.tidebot

import android.content.Context
import android.util.AtomicFile
import android.util.Xml
import android.util.JsonReader
import android.util.JsonToken
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile

/** Replace live data only at process startup, before providers, engines or workers. */
object TideColdRestore {
    private fun root(context: Context) = File(context.noBackupFilesDir, "tide_restore")
    private fun write(file: File, text: String) {
        file.parentFile?.mkdirs()
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            stream.write(text.toByteArray(Charsets.UTF_8))
            atomic.finishWrite(stream)
        } catch (error: Throwable) {
            atomic.failWrite(stream)
            throw error
        }
    }
    private fun move(source: File, target: File) {
        target.parentFile?.mkdirs()
        check(source.renameTo(target)) { "Cannot move ${source.name}" }
    }
    private fun remove(file: File) {
        check(!file.exists() || file.deleteRecursively()) { "Cannot remove ${file.name}" }
    }
    fun stage(context: Context, input: String) {
        val source = File(input).canonicalFile
        check(source.path.startsWith(context.cacheDir.canonicalPath + File.separator)) { "Invalid restore workspace" }
        check(File(source, "tidebot.db").isFile)
        val root = root(context).apply { mkdirs() }
        RandomAccessFile(File(root, "lock"), "rw").channel.use { channel ->
            channel.lock().use {
                val ready = File(root, "ready")
                check(!ready.exists()) { "已有待恢复备份，请先重启应用" }
                val next = File(root, "next")
                remove(next)
                next.mkdirs()
                try {
                    File(source, "tidebot.db").copyTo(File(next, "database"))
                    val docs = File(source, "documents")
                    if (docs.exists()) check(docs.copyRecursively(File(next, "documents")))
                    else File(next, "documents").mkdirs()
                    preferences(File(source, "restored_preferences.json"), File(next, "preferences"))
                    next.walkTopDown().filter { it.isFile }.forEach { file ->
                        RandomAccessFile(file, "rw").use { it.fd.sync() }
                    }
                    // All content is prepared before exposing a ready marker.
                    move(next, ready)
                } catch (error: Throwable) {
                    remove(next)
                    throw error
                }
            }
        }
    }
    private fun preferences(json: File, destination: File) {
        JsonReader(json.reader()).use { values ->
        FileOutputStream(destination).use { stream ->
            val xml = Xml.newSerializer()
            xml.setOutput(stream, "utf-8")
            xml.startDocument("utf-8", true)
            xml.startTag(null, "map")
            values.beginObject()
            while (values.hasNext()) {
                val key = values.nextName()
                val value: Any = when (values.peek()) {
                    JsonToken.BOOLEAN -> values.nextBoolean()
                    JsonToken.NUMBER -> {
                        val raw = values.nextString()
                        raw.toLongOrNull() ?: raw.toDouble()
                    }
                    JsonToken.STRING -> values.nextString()
                    JsonToken.BEGIN_ARRAY -> {
                        val items = JSONArray()
                        values.beginArray()
                        while (values.hasNext()) {
                            check(values.peek() == JsonToken.STRING)
                            items.put(values.nextString())
                        }
                        values.endArray()
                        items
                    }
                    else -> error("Invalid preference: $key")
                }
                val name = "flutter.$key"
                val tag = when (value) { is Boolean -> "boolean"; is Int, is Long -> "long"; else -> "string" }
                xml.startTag(null, tag).attribute(null, "name", name)
                if (tag != "string") xml.attribute(null, "value", value.toString())
                else xml.text(when (value) {
                    is JSONArray -> "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!$value"
                    is Number -> "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu$value"
                    is String -> value
                    else -> error("Invalid preference: $key")
                })
                xml.endTag(null, tag)
            }
            values.endObject()
            check(values.peek() == JsonToken.END_DOCUMENT)
            xml.endTag(null, "map")
            xml.endDocument()
            xml.flush()
            stream.fd.sync()
        }
        }
    }
    fun applyBeforeProviders(context: Context) {
        val root = root(context)
        if (!root.exists()) return
        RandomAccessFile(File(root, "lock"), "rw").channel.use { channel ->
            channel.lock().use {
                val discarded = File(root, "discarded")
                remove(discarded)
                val applied = File(root, "applied")
                if (applied.exists()) {
                    write(File(root, "result"), "完整备份已恢复。MCP 和 HTTP Skill 的鉴权信息需重新填写并启用。")
                    remove(applied)
                }
                val ready = File(root, "ready")
                if (!ready.exists()) return
                val prefs = File(context.applicationInfo.dataDir, "shared_prefs/FlutterSharedPreferences.xml")
                val targets = listOf(
                    context.getDatabasePath("tidebot.db"),
                    File(context.applicationInfo.dataDir, "app_flutter"),
                    prefs,
                    context.getDatabasePath("tidebot.db-wal"),
                    context.getDatabasePath("tidebot.db-shm"),
                    File(prefs.path + ".bak"),
                    File(context.filesDir, "restore_credentials_pending")
                )
                val names = listOf("database", "documents", "preferences", "wal", "shm", "prefs_bak", "credential_marker")
                val rollback = File(ready, "rollback")
                val state = File(ready, "originals.json")
                fun rollback(originals: JSONArray) {
                    for (index in targets.indices.reversed()) {
                        val old = File(rollback, names[index])
                        if (old.exists()) {
                            remove(targets[index])
                            move(old, targets[index])
                        } else if (!originals.getBoolean(index)) remove(targets[index])
                    }
                }
                if (state.exists() || File(state.path + ".bak").exists()) {
                    // Interrupted swaps roll back before any database is opened.
                    rollback(JSONArray(String(AtomicFile(state).readFully(), Charsets.UTF_8)))
                    move(ready, discarded)
                    remove(discarded)
                    write(File(root, "result"), "恢复被中断，已恢复原始数据，请重新导入备份。")
                    return
                }
                val originals = JSONArray(targets.map { it.exists() })
                rollback.mkdirs()
                write(state, originals.toString())
                try {
                    for (index in targets.indices) {
                        val target = targets[index]
                        if (target.exists()) move(target, File(rollback, names[index]))
                        val replacement = File(ready, names[index])
                        if (replacement.exists()) move(replacement, target)
                    }
                    write(targets.last(), "pending")
                    // Rename commits the swap. Cleanup may be interrupted safely.
                    move(ready, applied)
                } catch (error: Throwable) {
                    // Do not start with a partly replaced database/documents tree.
                    rollback(originals)
                    move(ready, discarded)
                    remove(discarded)
                    write(File(root, "result"), "恢复失败，已保留原始数据：${error.message}")
                    return
                }
                write(File(root, "result"), "完整备份已恢复。MCP 和 HTTP Skill 的鉴权信息需重新填写并启用。")
                remove(applied)
            }
        }
    }
    fun consumeResult(context: Context): String? {
        val file = File(root(context), "result")
        if (!file.exists()) return null
        val result = file.readText()
        check(file.delete())
        return result
    }
}
