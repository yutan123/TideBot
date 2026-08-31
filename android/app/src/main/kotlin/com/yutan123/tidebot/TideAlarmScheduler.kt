package com.yutan123.tidebot

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject

object TideAlarmScheduler {
    private const val PREFS = "tidebot_alarms"
    private const val KEY_TASKS = "tasks"
    private const val ACTION_TASK = "com.yutan123.tidebot.ACTION_TASK_ALARM"
    private const val EXTRA_ID = "task_id"
    private const val EXTRA_TITLE = "title"

    fun schedule(context: Context, taskId: String, triggerAt: Long, title: String): Boolean {
        if (taskId.isBlank() || triggerAt <= 0L) return false
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        val intent = Intent(context, TideAlarmReceiver::class.java).apply {
            action = ACTION_TASK
            putExtra(EXTRA_ID, taskId)
            putExtra(EXTRA_TITLE, title)
        }
        val pending = PendingIntent.getBroadcast(
            context, taskId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            }
        } catch (error: SecurityException) {
            Log.w("TideAlarm", "exact alarm unavailable", error)
            return false
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val values = prefs.getStringSet(KEY_TASKS, emptySet()).orEmpty().toMutableSet()
        values.removeAll { decode(it)?.optString("id") == taskId }
        values.add(JSONObject().apply {
            put("id", taskId)
            put("at", triggerAt)
            put("title", title)
        }.toString())
        prefs.edit().putStringSet(KEY_TASKS, values).apply()
        return true
    }

    fun cancel(context: Context, taskId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, TideAlarmReceiver::class.java).apply { action = ACTION_TASK }
        val pending = PendingIntent.getBroadcast(
            context, taskId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
        alarmManager.cancel(pending)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putStringSet(KEY_TASKS, prefs.getStringSet(KEY_TASKS, emptySet()).orEmpty()
            .filterNot { decode(it)?.optString("id") == taskId }.toSet()).apply()
    }

    fun restore(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val entries = prefs.getStringSet(KEY_TASKS, emptySet()).orEmpty().toList()
        val now = System.currentTimeMillis()
        entries.forEach { entry ->
            val value = decode(entry) ?: return@forEach
            val id = value.optString("id")
            val at = value.optLong("at", 0L)
            if (id.isNotBlank() && at > now) schedule(context, id, at, value.optString("title"))
        }
    }

    private fun decode(value: String): JSONObject? = runCatching { JSONObject(value) }.getOrNull()
    private fun immutableFlag() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
        PendingIntent.FLAG_IMMUTABLE else 0
    const val taskAction: String = ACTION_TASK
    const val taskIdExtra: String = EXTRA_ID
    const val titleExtra: String = EXTRA_TITLE
}