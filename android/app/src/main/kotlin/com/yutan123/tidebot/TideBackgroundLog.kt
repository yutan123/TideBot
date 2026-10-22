package com.yutan123.tidebot
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
/** Persistent request diagnostics. Full payloads require enabled live logging. */
object TideBackgroundLog {
    fun enabled(context: Context): Boolean = context
        .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getBoolean("flutter.dev_log_enabled", false)

    @Synchronized
    fun add(context: Context, message: String, level: String = "PROACTIVE_NATIVE") {
        val prefs = context.getSharedPreferences("TideBackgroundLog", Context.MODE_PRIVATE)
        val rows = runCatching { JSONArray(prefs.getString("entries", "[]")) }.getOrDefault(JSONArray())
        val entry = JSONObject().put("time", System.currentTimeMillis())
            .put("level", level).put("message", redact(message))
        // Evict whole old entries; never truncate the current request/context.
        var bytes = entry.toString().toByteArray(Charsets.UTF_8).size
        val retained = mutableListOf<JSONObject>()
        for (i in rows.length() - 1 downTo 0) {
            val row = rows.optJSONObject(i) ?: continue
            bytes += row.toString().toByteArray(Charsets.UTF_8).size
            if (retained.size >= 199 || bytes > 2 * 1024 * 1024) break
            retained.add(row)
        }
        val kept = JSONArray()
        retained.asReversed().forEach { kept.put(it) }
        kept.put(entry)
        prefs.edit().putString("entries", kept.toString()).commit()
    }
    private fun redact(value: String): String = value
        .replace(Regex("Bearer\\s+[^\\s,}]+", RegexOption.IGNORE_CASE), "Bearer [REDACTED]")
        .replace(Regex("\"(?:api_key|apiKey|authorization)\"\\s*:\\s*\"[^\"]*\"", RegexOption.IGNORE_CASE), "\"credential\":\"[REDACTED]\"")

    @Synchronized
    fun drain(context: Context): String {
        val prefs = context.getSharedPreferences("TideBackgroundLog", Context.MODE_PRIVATE)
        val value = prefs.getString("entries", "[]") ?: "[]"
        prefs.edit().remove("entries").commit()
        return value
    }
}
