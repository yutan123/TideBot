package com.yutan123.tidebot

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Small persistent diagnostic queue; never stores prompts, replies or credentials. */
object TideBackgroundLog {
    @Synchronized
    fun add(context: Context, message: String) {
        val prefs = context.getSharedPreferences("TideBackgroundLog", Context.MODE_PRIVATE)
        val rows = runCatching { JSONArray(prefs.getString("entries", "[]")) }.getOrDefault(JSONArray())
        val kept = JSONArray()
        for (i in maxOf(0, rows.length() - 199) until rows.length()) kept.put(rows.get(i))
        kept.put(JSONObject().put("time", System.currentTimeMillis()).put("message", message))
        prefs.edit().putString("entries", kept.toString()).commit()
    }

    @Synchronized
    fun drain(context: Context): String {
        val prefs = context.getSharedPreferences("TideBackgroundLog", Context.MODE_PRIVATE)
        val value = prefs.getString("entries", "[]") ?: "[]"
        prefs.edit().remove("entries").commit()
        return value
    }
}
