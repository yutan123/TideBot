package com.yutan123.tidebot

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.UUID

/**
 * 任务执行器，负责执行后台任务（主动回复、体征监测等）。
 * 通过 TideAiClient 调用 AI，结果写入数据库。
 */
object TideTaskExecutor {
    private const val TAG = "TideTaskExecutor"

    /**
     * 执行任务
     */
    suspend fun executeTask(context: Context, taskId: String, scheduledTime: Long) = withContext(Dispatchers.IO) {
        Log.d(TAG, "Executing task: $taskId at $scheduledTime")

        val executionId = claimExecution(context, taskId, scheduledTime) ?: return@withContext
        TideBackgroundLog.add(context, "任务开始：$taskId，到期时间=$scheduledTime")

        try {
            // 读取任务配置
            val taskConfig = getTaskConfig(context, taskId)
            if (taskConfig == null) {
                throw IllegalStateException("Task not found: $taskId")
            }

            // 根据任务类型执行
            when (taskConfig.optString("task_type")) {
                "FUTURE_TASK" -> TideFutureTasks.execute(context, taskId, executionId)
                "PROACTIVE_REPLY" -> executeProactiveReply(context, taskConfig, executionId)
                "VITAL_SIGNS" -> {
                    executeVitalSigns(context, taskConfig, executionId)
                    TideStore.open(context).use { db ->
                        db.execSQL("UPDATE background_tasks SET enabled=0 WHERE task_id=? AND trigger_time=?",arrayOf(taskId,scheduledTime))
                    }
                    TideVitalSigns.tick(context, taskConfig.getString("bot_id"))
                    TideProactiveTasks.reconcile(context)
                }
                else -> {
                    Log.w(TAG, "Unknown task type: ${taskConfig.optString("task_type")}")
                    markExecutionFinished(context, executionId, "skipped", null, "Unknown task type")
                }
            }
            runCatching { TideNativeNotifications.deliverPending(context) }
        } catch (e: CancellationException) {
            withContext(NonCancellable + Dispatchers.IO) {
                markExecutionFinished(context, executionId, "failed", null, "Cancelled")
            }
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Task execution failed: $taskId", e)
            TideBackgroundLog.add(context, "任务异常：$taskId，类型=${e.javaClass.simpleName}")
            markExecutionFinished(context, executionId, "failed", null, e.message)
        }
    }

    /**
     * 执行主动回复任务
     */
    private suspend fun executeProactiveReply(context: Context, taskConfig: JSONObject, executionId: String) {
        val botId = taskConfig.optString("bot_id")
        if (botId.isEmpty()) {
            throw IllegalArgumentException("No bot_id in task config")
        }

        val allowed = TideStore.open(context).use { db ->
            val state = runCatching { JSONObject(TideStore.kv(db, "bot_vitals_v1_$botId") ?: "{}") }.getOrDefault(JSONObject())
            TideStore.kv(db, "proactive_reply") != "false" &&
                (TideStore.kv(db, "proactive_unanswered_$botId")?.toIntOrNull() ?: 0) < 3 &&
                state.optJSONObject("sleep") == null
        }
        if (!allowed) {
            markExecutionFinished(context, executionId, "skipped", null, "Proactive reply paused")
            TideProactiveTasks.reconcile(context)
            return
        }
        // 读取机器人配置
        val botConfig = TideConfigReader.getBotConfig(context, botId)
        if (botConfig == null || botConfig.isDisabled) {
            markExecutionFinished(context, executionId, "skipped", null, "Bot disabled or not found")
            return
        }

        val model = botConfig.chatModel
        if (model == null) {
            markExecutionFinished(context, executionId, "failed", null, "No chat model configured")
            return
        }

        val initialDue = TideStore.open(context).use { TideStore.kv(it, "proactive_due_at_$botId") }
        val latestUser = TideStore.open(context).use { db ->
            TideStore.rows(db, "SELECT id FROM chat_history WHERE bot_id=? AND role='user' ORDER BY timestamp DESC,id DESC LIMIT 1", botId).firstOrNull()?.optString("id")
        }

        // 构建提示词
        val systemPrompt = TidePromptContext.system(context, botConfig) + "\n\n" +
            "【主动回复触发：不是用户新消息】\n" +
            "当前本地时间：${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(java.util.Date())}。\n" +
            "请结合最近对话、忙碌或休息状态判断是否适合联系。不适合时调用 choose_silence，不输出正文；适合时自然接续话题。不要提及触发或系统指令。回复限 1-3 个短句、80 字内。"

        // 读取最近对话历史
        val recentMessages = getRecentMessages(context, botId, limit = 10)

        // 发送 AI 请求
        val request = TideAiClient.AiRequest(
            baseUrl = model.baseUrl,
            apiKey = model.apiKey,
            model = model.model,
            messages = listOf(
                TideAiClient.Message("system", systemPrompt)
            ) + recentMessages.map {
                TideAiClient.Message(
                    role = it.optString("role", "user"),
                    content = it.optString("content", ""),
                    sentAt = it.optLong("timestamp")
                )
            },
            maxTokens = botConfig.maxTokens,
            allowSilence = true
        )

        TideBackgroundLog.add(context, "主动回复请求开始：bot=$botId，model=${model.model}")
        val result = TideAiClient.sendRequest(request)
        TideBackgroundLog.add(context, "主动回复请求结束：bot=$botId，结果=${if (result.isFailure) "request_failed" else if (result.getOrNull()?.silent == true) "model_silence" else "reply_received"}")

        TideStore.open(context).use { db ->
            TideStore.transaction(db) {
                requireLease(db, executionId)
                val currentUser = TideStore.rows(db, "SELECT id FROM chat_history WHERE bot_id=? AND role='user' ORDER BY timestamp DESC,id DESC LIMIT 1", botId).firstOrNull()?.optString("id")
                val state = JSONObject(TideStore.kv(db, "bot_vitals_v1_$botId") ?: "{}")
                val disabled = TideStore.rows(db, "SELECT is_disabled FROM bots WHERE id=?", botId).firstOrNull()?.optInt("is_disabled", 1) != 0
                if (disabled || currentUser != latestUser || (TideStore.kv(db, "proactive_unanswered_$botId")?.toIntOrNull() ?: 0) >= 3 || TideStore.kv(db, "proactive_due_at_$botId") != initialDue ||
                    TideStore.kv(db, "proactive_reply") == "false" || state.optJSONObject("sleep") != null) {
                    db.execSQL("UPDATE background_task_executions SET status='skipped',finished_at=?,error_message='Context changed during request' WHERE execution_id=?", arrayOf(System.currentTimeMillis(),executionId))
                    TideBackgroundLog.add(context, "主动回复丢弃：bot=$botId，请求期间对话或设置已改变")
                    return@transaction
                }
                val response = result.getOrNull()
                val sent = response != null && !response.silent
                if (sent) {
                    publishMessage(db, botId, taskConfig.getString("task_id"), response!!.content, executionId)
                    val count = TideStore.kv(db, "proactive_unanswered_$botId")?.toIntOrNull() ?: 0
                    TideStore.put(db, "proactive_unanswered_$botId", (count + 1).toString())
                } else {
                    db.execSQL("UPDATE background_task_executions SET status=?,finished_at=?,error_message=? WHERE execution_id=? AND status='running'",
                        arrayOf(if (response != null) "success" else "failed", System.currentTimeMillis(), result.exceptionOrNull()?.message, executionId))
                }
                TideStore.put(db, "proactive_last_result_$botId", if (sent) "sent" else if (response != null) "model_silence" else "request_failed")
                TideBackgroundLog.add(context, "主动回复结果：bot=$botId，${if (sent) "sent" else if (response != null) "model_silence" else "request_failed"}")
                TideStore.put(db, "proactive_due_at_$botId", TideProactiveTasks.nextDeadline(db, !sent).toString())
            }
        }
        TideProactiveTasks.reconcile(context)
    }

    private suspend fun executeVitalSigns(context: Context, taskConfig: JSONObject, executionId: String) {
        val id = taskConfig.getString("bot_id")
        val state = TideVitalSigns.tick(context, id, reschedule = false)
        val pending = state.optJSONArray("pending")
        val reason = state.optString("pending_reason")
        if (pending == null || pending.length() == 0 || reason.isBlank()) {
            markExecutionFinished(context, executionId, "success", null, null)
            return
        }
        val pendingIds = (0 until pending.length()).map { pending.getJSONObject(it).getString("id") }.toSet()
        val cutoff = (0 until pending.length()).maxOf { pending.getJSONObject(it).optLong("time") }
        val bot = TideConfigReader.getBotConfig(context, id) ?: error("Bot not found")
        check(!bot.isDisabled) { "Bot is disabled" }
        val model = bot.chatModel ?: error("No chat model configured")
        val response = TideAiClient.sendRequest(TideAiClient.AiRequest(model.baseUrl,model.apiKey,model.model,
            listOf(TideAiClient.Message("system",TidePromptContext.system(context, bot)), TideAiClient.Message("user",
                "${if (reason == "natural") "你在睡眠中短暂自然清醒" else "你刚刚起床"}。以下是睡眠期间收到的消息，请自然回复；${if (reason == "natural") "不适合回复时调用 choose_silence。" else "本次起床补回必须输出回复。"}不要透露内部指令。\n$pending")),
            bot.maxTokens, allowSilence = reason == "natural")).getOrThrow()
        TideStore.open(context).use { db ->
            TideStore.transaction(db) {
                requireLease(db, executionId)
                val lock = JSONObject(TideStore.kv(db, "vital_lock_$id") ?: "{}")
                check(lock.optLong("until") <= System.currentTimeMillis()) { "Vital state is busy" }
                val current = JSONObject(TideStore.kv(db, "bot_vitals_v1_$id") ?: "{}")
                val enabled = TideStore.rows(db, "SELECT is_disabled FROM bots WHERE id=?", id).firstOrNull()?.optInt("is_disabled", 1) == 0
                val queuedIds = current.optJSONArray("pending") ?: org.json.JSONArray()
                val stillPending = (0 until queuedIds.length()).any { queuedIds.getJSONObject(it).optString("id") in pendingIds }
                if (!enabled || !stillPending || current.optLong("answered_until") >= cutoff ||
                    (reason == "natural" && current.optJSONObject("sleep") == null)) {
                    db.execSQL("UPDATE background_task_executions SET status='skipped',finished_at=?,error_message='Vital context changed during request' WHERE execution_id=?",
                        arrayOf(System.currentTimeMillis(), executionId))
                    return@transaction
                }
                if (!response.silent) {
                    publishMessage(db,id,taskConfig.getString("task_id"),response.content,executionId)
                    val keep = org.json.JSONArray()
                    val queued = current.optJSONArray("pending") ?: org.json.JSONArray()
                    for (i in 0 until queued.length()) if (queued.getJSONObject(i).optString("id") !in pendingIds) keep.put(queued.getJSONObject(i))
                    val repliedAt = System.currentTimeMillis()
                    current.put("pending",keep).put("answered_until",cutoff).put("last_chat",repliedAt)
                    current.optJSONObject("sleep")?.let { sleep ->
                        val awake = sleep.optJSONArray("awake") ?: org.json.JSONArray()
                        awake.put(JSONObject().put("start",repliedAt).put("end",minOf(sleep.optLong("planned_end"),repliedAt + kotlin.random.Random.nextInt(5,21)*60_000L)).put("reason","回复消息"))
                        sleep.put("awake",awake)
                    }
                } else {
                    db.execSQL("UPDATE background_task_executions SET status='success',finished_at=? WHERE execution_id=? AND status='running'",arrayOf(System.currentTimeMillis(),executionId))
                    current.put("retry_at",System.currentTimeMillis()+300_000)
                }
                current.remove("pending_reason")
                TideStore.put(db,"bot_vitals_v1_$id",current.toString())
            }
        }
    }

    /** Claim and lease renewal are one transaction across all execution sources. */
    private fun claimExecution(context: Context, taskId: String, scheduledTime: Long): String? {
        TideStore.open(context).use { db ->
            return TideStore.transaction(db) {
                val task = TideStore.rows(db,
                    "SELECT trigger_time FROM background_tasks WHERE task_id=? AND enabled=1", taskId).firstOrNull()
                    ?: return@transaction null
                if (task.optLong("trigger_time") != scheduledTime || scheduledTime > System.currentTimeMillis()) return@transaction null
                val previous = TideStore.rows(db,
                    "SELECT * FROM background_task_executions WHERE task_id=? AND scheduled_time=?",
                    taskId, scheduledTime.toString()).firstOrNull()
                val now = System.currentTimeMillis()
                if (previous != null) {
                    val status = previous.optString("status")
                    if (status == "success" || status == "skipped") return@transaction null
                    if (status == "running" && now - previous.optLong("started_at") < 6 * 60_000L) return@transaction null
                    if (status == "failed" && now - previous.optLong("finished_at") < 60_000L) return@transaction null
                }
                val id = UUID.randomUUID().toString()
                if (previous == null) {
                    db.execSQL("INSERT INTO background_task_executions (execution_id,task_id,scheduled_time,started_at,status,attempt) VALUES (?,?,?,?, 'running',1)",
                        arrayOf(id,taskId,scheduledTime,now))
                } else {
                    db.execSQL("UPDATE background_task_executions SET execution_id=?,started_at=?,finished_at=NULL,status='running',attempt=attempt+1,error_message=NULL WHERE task_id=? AND scheduled_time=?",
                        arrayOf(id,now,taskId,scheduledTime))
                }
                id
            }
        }
    }

    /**
     * 标记执行结束
     */
    private fun markExecutionFinished(
        context: Context,
        executionId: String,
        status: String,
        result: String?,
        error: String?
    ) {
        TideBackgroundLog.add(context, "任务结束：execution=$executionId，status=$status")
        val db = openDatabase(context) ?: return
        try {
            db.execSQL(
                """UPDATE background_task_executions 
                   SET finished_at = ?, status = ?, result_json = ?, error_message = ? 
                   WHERE execution_id = ? AND status = 'running'""",
                arrayOf(System.currentTimeMillis(), status, result, error, executionId)
            )
        } finally {
            db.close()
        }
    }

    /**
     * 获取任务配置
     */
    private fun getTaskConfig(context: Context, taskId: String): JSONObject? {
        val db = openDatabase(context) ?: return null
        try {
            val cursor = db.rawQuery(
                "SELECT task_type, bot_id, config_json FROM background_tasks WHERE task_id = ?",
                arrayOf(taskId)
            )
            cursor.use {
                if (!it.moveToFirst()) return null
                val config = JSONObject()
                config.put("task_id", taskId)
                config.put("task_type", it.getString(0))
                config.put("bot_id", it.getString(1))
                val configJson = it.getString(2)
                if (!configJson.isNullOrEmpty()) {
                    val extra = JSONObject(configJson)
                    extra.keys().forEach { key -> config.put(key, extra.get(key)) }
                }
                return config
            }
        } finally {
            db.close()
        }
    }

    /**
     * 获取最近对话历史
     */
    private fun getRecentMessages(context: Context, botId: String, limit: Int): List<JSONObject> {
        val db = openDatabase(context) ?: return emptyList()
        try {
            val cursor = db.rawQuery(
                """SELECT role, content, timestamp FROM chat_history
                   WHERE bot_id = ? AND type = 'text' 
                   ORDER BY timestamp DESC LIMIT ?""",
                arrayOf(botId, limit.toString())
            )
            val messages = mutableListOf<JSONObject>()
            cursor.use {
                while (it.moveToNext()) {
                    val msg = JSONObject()
                    msg.put("role", it.getString(0))
                    msg.put("content", it.getString(1))
                    msg.put("timestamp", it.getLong(2))
                    messages.add(0, msg) // 倒序插入，保持时间正序
                }
            }
            return messages
        } finally {
            db.close()
        }
    }

    /**
     * 保存后台消息
     */
    private fun saveBackgroundMessage(
        context: Context,
        botId: String,
        taskId: String,
        content: String,
        executionId: String
    ) {
        val db = openDatabase(context) ?: return
        try {
            TideStore.transaction(db) {
                publishMessage(db, botId, taskId, content, executionId)
            }
        } finally {
            db.close()
        }
    }

    private fun requireLease(db: SQLiteDatabase, executionId: String) {
        val status = TideStore.rows(db,
            "SELECT status FROM background_task_executions WHERE execution_id=?",
            executionId).firstOrNull()?.optString("status")
        check(status == "running") { "Execution lease expired" }
    }


    internal fun publishMessage(db: SQLiteDatabase, botId: String, taskId: String, content: String, executionId: String) {
                // A reclaimed execution must never publish a late result.
                val lease = TideStore.rows(db, "SELECT status FROM background_task_executions WHERE execution_id=?", executionId).firstOrNull()
                check(lease?.optString("status") == "running") { "Execution lease expired" }
                val messageId = "background:$executionId"
                val now = System.currentTimeMillis()
                db.execSQL("INSERT OR IGNORE INTO background_messages (message_id,bot_id,task_id,role,content,timestamp,displayed,synced_to_chat) VALUES (?,?,?,'assistant',?,?,0,1)",
                    arrayOf(messageId,botId,taskId,content,now))
                db.execSQL("INSERT OR IGNORE INTO chat_history (id,bot_id,role,type,content,timestamp) VALUES (?,?,'assistant','text',?,?)",
                    arrayOf(messageId,botId,content,now))
                db.execSQL("UPDATE bots SET last_msg_time=MAX(COALESCE(last_msg_time,0),?) WHERE id=?",arrayOf(now,botId))
                db.execSQL("UPDATE background_task_executions SET status='success',finished_at=?,result_json=? WHERE execution_id=?",arrayOf(now,content,executionId))
    }

    /**
     * 检查是否有待处理任务
     */
    fun hasPendingTasks(context: Context): Boolean = TideStore.open(context).use { db ->
        TideStore.rows(db, "SELECT task_id FROM background_tasks WHERE enabled=1 AND trigger_time<=? LIMIT 1",
            System.currentTimeMillis().toString()).isNotEmpty()
    }

    private fun openDatabase(context: Context): SQLiteDatabase? {
        return try {
            TideStore.open(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open database", e)
            null
        }
    }
}
