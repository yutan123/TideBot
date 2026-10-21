package com.yutan123.tidebot

import android.content.Context
import org.json.JSONObject
import kotlin.random.Random

/** Registers proactive deadlines from the same KV settings used by Flutter. */
object TideProactiveTasks {
    fun reconcile(context: Context) {
        TideStore.open(context).use { db ->
            val enabled = TideStore.kv(db, "proactive_reply") != "false"
            for (bot in TideStore.rows(db, "SELECT id,is_disabled FROM bots")) {
                val id = bot.getString("id")
                val sleeping = runCatching { JSONObject(TideStore.kv(db, "bot_vitals_v1_$id") ?: "{}").optJSONObject("sleep") != null }.getOrDefault(false)
                val reason = when {
                    !enabled -> "disabled"
                    sleeping -> "sleeping"
                    bot.optInt("is_disabled") == 1 -> "bot_disabled"
                    (TideStore.kv(db, "proactive_unanswered_$id")?.toIntOrNull() ?: 0) >= 3 -> "unanswered_limit"
                    else -> null
                }
                if (reason != null) {
                    if (TideStore.kv(db, "proactive_last_result_$id") != reason) {
                        TideBackgroundLog.add(context, "主动回复暂停：bot=$id，reason=$reason")
                        TideStore.put(db, "proactive_last_result_$id", reason)
                    }
                    db.execSQL("UPDATE background_tasks SET enabled=0 WHERE task_id=?", arrayOf("proactive:$id"))
                    TideAlarmScheduler.cancel(context, "proactive:$id")
                    continue
                }
                val due = TideStore.transaction(db) {
                    val existing = TideStore.kv(db, "proactive_due_at_$id")?.toLongOrNull() ?: 0L
                    if (existing > 0) existing else {
                        val next = nextDeadline(db, false)
                        TideStore.put(db, "proactive_due_at_$id", next.toString())
                        TideBackgroundLog.add(context, "主动回复已安排：bot=$id，到期时间=$next")
                        next
                    }
                }
                TideMasterScheduler.registerTask(context, "proactive:$id", "PROACTIVE_REPLY", id, due, false,
                    JSONObject().put("title", "TideBot 主动回复"))
            }
        }
    }

    fun nextDeadline(db: android.database.sqlite.SQLiteDatabase, retry: Boolean): Long {
        val min = if (retry) 5 else (TideStore.kv(db, "proactive_min_minutes")?.toIntOrNull() ?: 60).coerceIn(1, 1440)
        val max = if (retry) 10 else (TideStore.kv(db, "proactive_max_minutes")?.toIntOrNull() ?: 90).coerceIn(min, 1440)
        return System.currentTimeMillis() + Random.nextInt(min, max + 1) * 60_000L
    }
}
