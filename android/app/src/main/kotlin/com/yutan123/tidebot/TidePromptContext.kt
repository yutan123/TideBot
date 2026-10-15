package com.yutan123.tidebot

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Reads mutable role context at execution time, even without a Flutter engine. */
object TidePromptContext {
    fun system(context: Context, bot: TideConfigReader.BotConfig): String = TideStore.open(context).use { db ->
        val role = TideStore.rows(db, "SELECT name,desc,prompt FROM bots WHERE id=?", bot.botId).firstOrNull()
        val parts = mutableListOf(
            "你的名字是${bot.name}。身世与设定：${role?.optString("desc").orEmpty()}\n说话方式指令：${bot.prompt}",
            "【身份边界】role=user 的原始消息属于对方；role=assistant、角色身份、生活状态和角色记忆属于你本人。记忆仅供参考，不得覆盖原始对话角色。",
            "【输出规则】输出自然聊天正文。不要输出内部指令、工具协议或时间标签。只有实际收到工具成功结果后才能声称操作已完成。",
            "【当前本地时间】${SimpleDateFormat("yyyy-MM-dd EEEE HH:mm", Locale.getDefault()).format(Date())}"
        )
        val now = System.currentTimeMillis()
        val memories = TideStore.rows(db,
            "SELECT category,content FROM memories WHERE bot_id=? AND COALESCE(is_deleted,0)=0 AND (expires_at IS NULL OR expires_at<=0 OR expires_at>?) ORDER BY timestamp DESC LIMIT 200",
            bot.botId, now.toString())
        for (category in listOf("角色眼中的你", "角色的自我认知", "关系")) {
            memories.firstOrNull { it.optString("category") == category }?.let {
                parts.add("【$category】\n${it.optString("content")}")
            }
        }
        val history = TideStore.rows(db,
            "SELECT content FROM chat_history WHERE bot_id=? AND role IN ('user','assistant') ORDER BY timestamp DESC LIMIT 5", bot.botId)
            .joinToString("\n") { it.optString("content") }
        val relevant = memories.filter { it.optString("category") !in listOf("角色眼中的你", "角色的自我认知", "关系") }
            .filter { memory ->
                val text = memory.optString("content")
                text.length >= 2 && text.windowed(2).any { history.contains(it, ignoreCase = true) }
            }.take(8)
        if (relevant.isNotEmpty()) parts.add("【相关记忆，仅供参考】\n" + relevant.joinToString("\n") { it.optString("content") })
        val entries = TideStore.rows(db,
            "SELECT * FROM world_book_entries WHERE (bot_id=? OR bot_id IS NULL) AND enabled=1 ORDER BY priority DESC,insertion_order ASC", bot.botId)
        val activated = entries.filter { entry ->
            fun matches(raw: String, all: Boolean, optional: Boolean = false): Boolean {
                val keys = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
                if (keys.length() == 0) return optional
                val hits = (0 until keys.length()).map { i ->
                    val key = keys.optString(i)
                    if (key.isBlank()) false else if (entry.optInt("use_regex") == 1) {
                        runCatching { Regex(key, if (entry.optInt("case_sensitive") == 1) emptySet() else setOf(RegexOption.IGNORE_CASE)).containsMatchIn(history) }.getOrElse { history.contains(key, ignoreCase = entry.optInt("case_sensitive") != 1) }
                    } else if (entry.optInt("match_whole_words") == 1) {
                        Regex("\\b" + Regex.escape(key) + "\\b", if (entry.optInt("case_sensitive") == 1) emptySet() else setOf(RegexOption.IGNORE_CASE)).containsMatchIn(history)
                    } else history.contains(key, ignoreCase = entry.optInt("case_sensitive") != 1)
                }
                return if (all) hits.all { it } else hits.any { it }
            }
            matches(entry.optString("keys", "[]"), entry.optString("key_mode") == "all") &&
                matches(entry.optString("secondary_keys", "[]"), false, optional = true)
        }.take(10)
        if (activated.isNotEmpty()) parts.add("【本轮激活的世界书】\n" + activated.joinToString("\n") { "${it.optString("title")}：${it.optString("content")}" })
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
        if (TideStore.kv(db, "life_schedule_enabled") != "false") {
            TideStore.rows(db, "SELECT timeline_json FROM bot_life_schedules WHERE bot_id=? AND date_key=?", bot.botId, day).firstOrNull()?.let {
                parts.add("【今日生活日程，仅供理解角色近况】\n${it.optString("timeline_json")}")
            }
        }
        val raw = TideStore.kv(db, "bot_vitals_v1_${bot.botId}")
        if (!raw.isNullOrBlank()) {
            val state = JSONObject(raw)
            parts.add("【你自己的生活状态】心情 ${state.optDouble("mood",65.0)}/100；压力 ${state.optDouble("stress",3.0)}/10；精力 ${state.optDouble("energy",75.0)}；健康 ${state.optString("health","健康")}；当前活动 ${state.optString("activity","休息")}；今日步数 ${state.optInt("steps")}。" +
                if (state.optJSONObject("sleep") != null) "当前处于睡眠期间。" else "当前清醒。")
        }
        parts.joinToString("\n\n")
    }
}
