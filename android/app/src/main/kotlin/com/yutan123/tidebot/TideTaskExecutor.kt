package com.yutan123.tidebot

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
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

        // 幂等性检查
        if (isAlreadyExecuted(context, taskId, scheduledTime)) {
            Log.d(TAG, "Task already executed, skipping: $taskId")
            return@withContext
        }

        // 标记开始执行
        val executionId = UUID.randomUUID().toString()
        markExecutionStarted(context, executionId, taskId, scheduledTime)

        try {
            // 读取任务配置
            val taskConfig = getTaskConfig(context, taskId)
            if (taskConfig == null) {
                throw IllegalStateException("Task not found: $taskId")
            }

            // 根据任务类型执行
            when (taskConfig.optString("task_type")) {
                "PROACTIVE_REPLY" -> executeProactiveReply(context, taskConfig, executionId)
                "VITAL_SIGNS" -> executeVitalSigns(context, taskConfig, executionId)
                else -> {
                    Log.w(TAG, "Unknown task type: ${taskConfig.optString("task_type")}")
                    markExecutionFinished(context, executionId, "skipped", null, "Unknown task type")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Task execution failed: $taskId", e)
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

        // 构建提示词
        val systemPrompt = botConfig.prompt + "\n\n" +
            "【主动回复触发：不是用户新消息】\n" +
            "当前本地时间：${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(java.util.Date())}。\n" +
            "请自然接续未结束话题或轻量开启新话题。回复限 1-3 个短句、80 字内。"

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
                    content = it.optString("content", "")
                )
            },
            maxTokens = botConfig.maxTokens
        )

        val result = TideAiClient.sendRequest(request)

        result.fold(
            onSuccess = { response ->
                // 保存回复到数据库
                saveBackgroundMessage(context, botId, taskConfig.optString("task_id"), response.content, executionId)
                markExecutionFinished(context, executionId, "success", response.content, null)
            },
            onFailure = { error ->
                markExecutionFinished(context, executionId, "failed", null, error.message)
            }
        )
    }

    /**
     * 执行体征监测任务（占位，后续实现）
     */
    private suspend fun executeVitalSigns(context: Context, taskConfig: JSONObject, executionId: String) {
        Log.d(TAG, "Vital signs check not yet implemented")
        markExecutionFinished(context, executionId, "skipped", null, "Not implemented")
    }

    /**
     * 检查任务是否已执行（幂等性）
     */
    private fun isAlreadyExecuted(context: Context, taskId: String, scheduledTime: Long): Boolean {
        val db = openDatabase(context) ?: return false
        try {
            val cursor = db.rawQuery(
                "SELECT 1 FROM background_task_executions WHERE task_id = ? AND scheduled_time = ?",
                arrayOf(taskId, scheduledTime.toString())
            )
            cursor.use {
                return it.moveToFirst()
            }
        } finally {
            db.close()
        }
    }

    /**
     * 标记执行开始
     */
    private fun markExecutionStarted(context: Context, executionId: String, taskId: String, scheduledTime: Long) {
        val db = openDatabase(context) ?: return
        try {
            db.execSQL(
                """INSERT INTO background_task_executions 
                   (execution_id, task_id, scheduled_time, started_at, status, attempt) 
                   VALUES (?, ?, ?, ?, 'running', 1)""",
                arrayOf(executionId, taskId, scheduledTime, System.currentTimeMillis())
            )
        } finally {
            db.close()
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
        val db = openDatabase(context) ?: return
        try {
            db.execSQL(
                """UPDATE background_task_executions 
                   SET finished_at = ?, status = ?, result_json = ?, error_message = ? 
                   WHERE execution_id = ?""",
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
                """SELECT role, content FROM chat_history 
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
            val messageId = UUID.randomUUID().toString()
            db.execSQL(
                """INSERT INTO background_messages 
                   (message_id, bot_id, task_id, role, content, timestamp, displayed, synced_to_chat) 
                   VALUES (?, ?, ?, 'assistant', ?, ?, 0, 0)""",
                arrayOf(messageId, botId, taskId, content, System.currentTimeMillis())
            )
            Log.d(TAG, "Saved background message: $messageId")
        } finally {
            db.close()
        }
    }

    /**
     * 检查是否有待处理任务
     */
    fun hasPendingTasks(context: Context): Boolean {
        // 简化实现：总是返回 false，让服务在任务完成后自动停止
        return false
    }

    private fun openDatabase(context: Context): SQLiteDatabase? {
        return try {
            val dbPath = File(context.getDatabasePath("tidebot.db").absolutePath)
            SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open database", e)
            null
        }
    }
}