package com.yutan123.tidebot

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.*
import kotlin.random.Random

/** All state changes happen in one SQLite transaction, including sleep deadlines. */
object TideVitalSigns {
    private fun objects(a: JSONArray?): List<JSONObject> =
        (0 until (a?.length() ?: 0)).mapNotNull { a?.optJSONObject(it) }
    private fun array(items: List<JSONObject>) = JSONArray().apply { items.forEach { put(it) } }
    private fun number(s: JSONObject, key: String, fallback: Double) = s.optDouble(key, fallback)
    private fun date(t: Long) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(t))
    private fun dayStart(t: Long) = java.util.Calendar.getInstance().apply {
        timeInMillis = t; set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
        set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
    }.timeInMillis

    fun tick(context: Context, botId: String, now: Long = System.currentTimeMillis(), reschedule: Boolean = true): JSONObject {
        val state = TideStore.open(context).use { db ->
            TideStore.transaction(db) {
                val lease = runCatching { JSONObject(TideStore.kv(db, "vital_lock_$botId") ?: "{}") }.getOrDefault(JSONObject())
                check(lease.optLong("until") <= now) { "Vital state is busy" }
                val raw = TideStore.kv(db, "bot_vitals_v1_$botId")
                val s = if (raw.isNullOrBlank()) initial(db, botId) else JSONObject(raw)
                advance(db, botId, s, now)
                TideStore.put(db, "bot_vitals_v1_$botId", s.toString())
                s
            }
        }
        var next = (now / 3_600_000 + 1) * 3_600_000
        for (plan in objects(state.optJSONArray("sleep_plans"))) {
            if (!plan.optBoolean("done") && plan.optLong("start") > now) next = min(next, plan.getLong("start"))
        }
        state.optJSONObject("sleep")?.let { sleep ->
            if (sleep.optLong("planned_end") > now) next = min(next, sleep.getLong("planned_end"))
            for (n in objects(sleep.optJSONArray("natural"))) if (n.optLong("start") > now) next = min(next, n.getLong("start"))
        }
        if ((state.optJSONArray("pending")?.length() ?: 0) > 0 && state.optJSONObject("sleep") == null) {
            next = min(next, max(now + 60_000, state.optLong("retry_at")))
        }
        if (!state.optString("pending_reason").isBlank() && (state.optJSONArray("pending")?.length() ?: 0) > 0) {
            next = min(next, now)
        }
        if (reschedule) {
            val existing = TideStore.open(context).use { db -> TideStore.rows(db,
                "SELECT trigger_time FROM background_tasks WHERE task_id=? AND enabled=1", "vitals:$botId").firstOrNull() }
            // A UI refresh must not move an unprocessed alarm out of the due queue.
            if (existing == null || existing.optLong("trigger_time") > now) {
                TideMasterScheduler.registerTask(context, "vitals:$botId", "VITAL_SIGNS", botId, next, false)
            }
        }
        return state
    }

    private fun initial(db: SQLiteDatabase, id: String): JSONObject {
        val prompt = TideStore.rows(db, "SELECT prompt FROM bots WHERE id=?", id).firstOrNull()?.optString("prompt").orEmpty()
        fun explicit(units: String) = Regex("(\\d+(?:\\.\\d+)?)\\s*(?:$units)").find(prompt)?.groupValues?.get(1)?.toDoubleOrNull()
        val height = explicit("cm|厘米") ?: (160 + Random.nextInt(16)).toDouble()
        val weight = explicit("kg|公斤|千克") ?: height * height / 10000 * (20 + Random.nextDouble() * 3)
        return JSONObject().put("height", height).put("weight", weight).put("base_weight", weight)
            .put("temperature", 36.5).put("heart", 72).put("systolic", 118).put("diastolic", 78)
            .put("mood", 65).put("stress", 3).put("energy", 75).put("health", "健康").put("illness", "")
            .put("recovery", 100).put("last_hour", 0).put("last_chat", 0)
            .put("samples", JSONArray()).put("sleep_history", JSONArray()).put("plans", JSONArray())
            .put("sleep_plans", JSONArray()).put("pending", JSONArray())
    }

    private fun advance(db: SQLiteDatabase, id: String, s: JSONObject, now: Long) {
        var sleep = s.optJSONObject("sleep")
        if (sleep == null) for (p in objects(s.optJSONArray("sleep_plans"))) {
            if (p.optBoolean("done") || p.optLong("start") > now) continue
            if (p.optLong("end") > now && now - s.optLong("last_chat") < 300_000) {
                val delta = max(p.getLong("start"), now) + 1_800_000 - p.getLong("start")
                p.put("start", p.getLong("start") + delta).put("end", p.getLong("end") + delta)
                break
            }
            p.put("done", true)
            val start = p.optLong("start"); val end = p.optLong("end")
            if (end <= start) continue
            val natural = JSONArray(); val count = Random.nextInt(3)
            for (i in 0 until count) {
                val span = max(1L, (end - start - 1_800_000) / max(1, count))
                val t = start + 900_000 + i * span + Random.nextLong(max(1L, span - 600_000))
                natural.put(JSONObject().put("start", t).put("end", min(end, t + Random.nextInt(5, 11) * 60_000L))
                    .put("reason", "自然清醒").put("processed", false))
            }
            sleep = JSONObject().put("day", p.optString("day")).put("start", start).put("planned_end", end)
                .put("awake", JSONArray()).put("natural", natural)
            s.put("sleep", sleep)
            val due = TideStore.kv(db, "proactive_due_at_$id")?.toLongOrNull() ?: 0
            TideStore.put(db, "vital_pause_$id", start.toString())
            TideStore.put(db, "vital_remaining_$id", if (due > 0) max(0, due - start).toString() else "")
            break
        }
        if (sleep != null) {
            val pending = objects(s.optJSONArray("pending")).toMutableList()
            val messages = TideStore.rows(db, "SELECT * FROM chat_history WHERE bot_id=? AND role='user' AND timestamp>=? AND timestamp<? AND timestamp>? ORDER BY timestamp",
                id, sleep.getLong("start").toString(), sleep.getLong("planned_end").toString(), s.optLong("answered_until").toString())
            for (m in messages) if (pending.none { it.optString("id") == m.optString("id") }) {
                pending.add(JSONObject().put("id", m.getString("id")).put("time", m.optLong("timestamp"))
                    .put("type", m.optString("type")).put("content", m.optString("content")).put("file_path", m.optString("file_path")))
            }
            s.put("pending", array(pending))
            val awake = sleep.optJSONArray("awake") ?: JSONArray()
            for (n in objects(sleep.optJSONArray("natural"))) {
                if (!n.optBoolean("processed") && n.optLong("start") <= now) {
                    n.put("processed", true); awake.put(JSONObject(n.toString()))
                }
                if (n.optBoolean("reply_checked") != true && now >= n.optLong("start") && now < n.optLong("end") && now < sleep.getLong("planned_end")) {
                    n.put("reply_checked", true)
                    s.put("pending_reason", "natural")
                }
            }
            sleep.put("awake", awake)
            if (now >= sleep.getLong("planned_end")) {
                sleep.put("end", sleep.getLong("planned_end"))
                val settled = settle(sleep)
                s.put("sleep_history", array((objects(s.optJSONArray("sleep_history")) + settled).takeLast(90)))
                s.put("sleep_quality", settled.getInt("quality")).put("energy", (40 + settled.getInt("quality") * .55).coerceIn(0.0, 100.0))
                s.remove("sleep"); s.put("pending_reason", "morning")
                val remaining = TideStore.kv(db, "vital_remaining_$id")?.toLongOrNull()
                TideStore.put(db, "proactive_due_at_$id", remaining?.let { (sleep.getLong("planned_end") + it).toString() } ?: "")
                TideStore.put(db, "vital_pause_$id", "")
            }
        }
        val hour = now / 3_600_000
        val last = max(if (s.optLong("last_hour") == 0L) hour - 1 else s.optLong("last_hour"), hour - 720)
        val samples = objects(s.optJSONArray("samples")).toMutableList()
        val blocks = objects(s.optJSONArray("plans")).flatMap { objects(it.optJSONArray("blocks")) }
        for (h in last + 1..hour) {
            val t = h * 3_600_000; val day = date(t); val midnight = dayStart(t)
            val nights = objects(s.optJSONArray("sleep_history")) + listOfNotNull(s.optJSONObject("sleep"))
            val sleeping = nights.any { t >= it.optLong("start") && t < it.optLong("planned_end") }
            var steps = 0; var activity = "休息"
            for (b in blocks) {
                val a = b.optLong("start"); val z = b.optLong("end")
                if (t >= a && t < z) activity = b.optString("activity")
                if (z > a && a < t && z > midnight) steps += (b.optInt("steps") * (min(t, z) - max(a, midnight)).coerceIn(0L, z - a).toDouble() / (z - a)).roundToInt()
            }
            if (t == midnight && samples.isNotEmpty()) {
                val previousDay = date(t - 1)
                val previousStart = dayStart(t - 1)
                var total = 0
                for (b in blocks) {
                    val a = b.optLong("start"); val z = b.optLong("end")
                    if (z > a && a < t && z > previousStart) total += (b.optInt("steps") *
                        (min(t, z) - max(a, previousStart)).coerceIn(0L, z - a).toDouble() / (z - a)).roundToInt()
                }
                samples.lastOrNull { it.optString("day") == previousDay }?.let {
                    samples.add(JSONObject(it.toString()).put("time", t - 1).put("steps", total).put("activity", "当日步数结算"))
                }
            }
            val quality = number(s, "sleep_quality", 80.0)
            val working = Regex("工作|上班|考试|学习").containsMatchIn(activity)
            val relaxing = Regex("散步|休息|读书|游戏|运动").containsMatchIn(activity)
            val target = (if (sleeping) 2.0 else if (working) 5.5 else if (relaxing) 2.0 else 3.0) + (if (quality < 60) 1.2 else 0.0) + (if (s.optString("health") == "生病") 1 else 0)
            val stress = (number(s,"stress",3.0) + (target - number(s,"stress",3.0)) * .16 + (Random.nextDouble() - .5) * .5).coerceIn(0.0,10.0)
            val mood = (number(s,"mood",65.0) + (70 - stress * 3 + (quality - 80) * .1 - number(s,"mood",65.0)) * .15 + (Random.nextDouble() - .5) * 4).coerceIn(0.0,100.0)
            s.put("stress", stress).put("mood", mood)
            if (s.optString("health") == "健康" && t >= s.optLong("cooldown")) {
                if (Random.nextDouble() < .0005 + (if (quality < 60) .0008 else 0.0) + (if (stress > 7) .0005 else 0.0)) {
                    s.put("health","生病").put("illness",listOf("感冒","轻微肠胃不适","头痛").random())
                        .put("ill_start",t).put("ill_until",t + Random.nextInt(48,97) * 3_600_000L).put("recovery",0)
                }
            } else if (s.optString("health") != "健康") {
                val a = s.optLong("ill_start"); val z = s.optLong("ill_until")
                val recovery = if (z > a) ((t-a).toDouble()/(z-a)*100).coerceIn(0.0,100.0) else 100.0
                s.put("recovery", recovery)
                if (recovery >= 100) s.put("health","健康").put("illness","").put("cooldown",t + 7 * 24 * 3_600_000L)
                else if (recovery >= 65) s.put("health","康复中")
            }
            if (s.optString("body_day") != day) {
                val base = number(s,"base_weight",60.0); val sick = s.optString("health") == "生病"
                s.put("weight", (number(s,"weight",base) + (Random.nextDouble()-.5)*.25 + (if(sick) -.08 else 0.0) + (if(steps>8000) -.03 else 0.0)).coerceIn(base-5,base+5))
                    .put("temperature",if(sick) 37.3+Random.nextDouble()*.8 else 36.3+Random.nextDouble()*.5)
                    .put("systolic",112+Random.nextInt(15)+(if(stress>7) 5 else 0)).put("diastolic",72+Random.nextInt(10)).put("body_day",day)
            }
            // Match Dart's hourlyMeanHeartRate: continue from the saved value,
            // including manual edits, without resetting it when the day changes.
            val exertion = if (Regex("跑步|健身|运动|骑行|游泳|球").containsMatchIn(activity)) 24.0
                else if (Regex("散步|步行|逛街|通勤").containsMatchIn(activity)) 9.0 else 0.0
            val change = (if (sleeping) -1.0 else exertion / 12) +
                (if (sleeping) 0.0 else (stress.coerceIn(0.0, 10.0) - 3) * .25) +
                (if (quality < 60 && !sleeping) 1.0 else 0.0) +
                max(0.0, number(s, "temperature", 36.5) - 37) * .8 +
                (Random.nextDouble() * 4 - 2)
            s.put("heart", (number(s, "heart", 72.0) + change.coerceIn(-4.0, 4.0))
                .coerceIn(45.0, 135.0).roundToInt())
            s.put("steps",max(0,steps)).put("activity",activity)
                .put("energy",(number(s,"energy",75.0)+(if(sleeping) 4.0 else -1.5)+(if(relaxing) 1 else 0)-(if(stress>7) 1 else 0)).coerceIn(0.0,100.0))
            val sample = JSONObject().put("time",t).put("day",day)
            for (k in listOf("mood","stress","steps","weight","temperature","heart","systolic","diastolic","health","recovery","activity")) sample.put(k,s.opt(k))
            samples.add(sample)
        }
        s.put("last_hour",hour).put("samples",array(samples.takeLast(2160)))
        if (s.optJSONObject("sleep") == null && objects(s.optJSONArray("pending")).isNotEmpty() && now >= s.optLong("retry_at")) s.put("pending_reason","morning")
    }

    private fun settle(sleep: JSONObject): JSONObject {
        val start = sleep.getLong("start"); val end = sleep.getLong("planned_end")
        val awake = objects(sleep.optJSONArray("awake")).map { max(start,it.optLong("start")) to min(end,it.optLong("end")) }
            .filter { it.second > it.first }.sortedBy { it.first }
        val merged = mutableListOf<Pair<Long,Long>>()
        for (p in awake) if (merged.isNotEmpty() && p.first <= merged.last().second) {
            val last = merged.removeAt(merged.lastIndex); merged.add(last.first to max(last.second,p.second))
        } else merged.add(p)
        val segments = JSONArray(); var cursor = start
        fun segment(a: Long,b: Long,state: String) { if(b>a) segments.put(JSONObject().put("start",a).put("end",b).put("state",state)) }
        for (p in merged) { segment(cursor,p.first,"睡眠"); segment(p.first,p.second,"清醒"); cursor=p.second }
        segment(cursor,end,"睡眠")
        val awakeMinutes = merged.sumOf { it.second-it.first } / 60_000
        val minutes = (end-start)/60_000-awakeMinutes
        val score = (100-max(0L,420-minutes)/7.0-max(0L,minutes-540)/15.0-awakeMinutes*.35-merged.size*4).roundToInt().coerceIn(0,100)
        return sleep.put("minutes",minutes).put("awake_minutes",awakeMinutes).put("quality",score).put("segments",segments)
    }
}