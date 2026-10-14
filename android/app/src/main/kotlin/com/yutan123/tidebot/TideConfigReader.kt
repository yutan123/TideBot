package com.yutan123.tidebot

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * 配置读取器，从 Flutter 保存的 SQLite 和 SharedPreferences 中读取配置。
 * 保证前台 Flutter 和后台 Kotlin 使用相同的模型配置。
 */
object TideConfigReader {
    private const val TAG = "TideConfigReader"

    data class BotConfig(
        val botId: String,
        val name: String,
        val prompt: String,
        val chatModel: ModelConfig?,
        val maxTokens: Int,
        val isDisabled: Boolean
    )

    data class ModelConfig(
        val id: String,
        val type: String,
        val name: String,
        val baseUrl: String,
        val apiKey: String,
        val model: String
    )

    /**
     * 获取机器人配置
     */
    fun getBotConfig(context: Context, botId: String): BotConfig? {
        val db = openDatabase(context) ?: return null
        
        try {
            val cursor = db.rawQuery(
                "SELECT name, prompt, chat_model, max_tokens, is_disabled FROM bots WHERE id = ?",
                arrayOf(botId)
            )
            
            cursor.use {
                if (!it.moveToFirst()) return null
                
                val name = it.getString(0) ?: ""
                val prompt = it.getString(1) ?: ""
                val chatModelId = it.getString(2)
                val maxTokens = it.getInt(3)
                val isDisabled = it.getInt(4) == 1
                
                val chatModel = if (!chatModelId.isNullOrEmpty()) {
                    getModelConfig(context, db, chatModelId)
                } else null
                
                return BotConfig(botId, name, prompt, chatModel, maxTokens, isDisabled)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get bot config: $botId", e)
            return null
        } finally {
            db.close()
        }
    }

    /**
     * 获取模型配置
     */
    private fun getModelConfig(context: Context, db: SQLiteDatabase, modelId: String): ModelConfig? {
        try {
            // 先从 kv_store 读取 user_models
            val cursor = db.rawQuery(
                "SELECT value FROM kv_store WHERE key = ?",
                arrayOf("user_models")
            )
            
            cursor.use {
                if (!it.moveToFirst()) return null
                
                val json = it.getString(0) ?: return null
                val models = JSONObject(json)
                
                if (!models.has(modelId)) return null
                
                val model = models.getJSONObject(modelId)
                return ModelConfig(
                    id = modelId,
                    type = model.optString("type", "openai"),
                    name = model.optString("name", ""),
                    baseUrl = model.optString("base_url", ""),
                    apiKey = model.optString("key", ""),
                    model = model.optString("model", "")
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get model config: $modelId", e)
            return null
        }
    }

    /**
     * 获取所有未禁用的机器人 ID
     */
    fun getEnabledBotIds(context: Context): List<String> {
        val db = openDatabase(context) ?: return emptyList()
        
        try {
            val cursor = db.rawQuery(
                "SELECT id FROM bots WHERE is_disabled = 0 OR is_disabled IS NULL",
                emptyArray()
            )
            
            val ids = mutableListOf<String>()
            cursor.use {
                while (it.moveToNext()) {
                    ids.add(it.getString(0))
                }
            }
            return ids
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get enabled bots", e)
            return emptyList()
        } finally {
            db.close()
        }
    }

    /**
     * 获取 KV 存储值
     */
    fun getKV(context: Context, key: String): String? {
        val db = openDatabase(context) ?: return null
        
        try {
            val cursor = db.rawQuery(
                "SELECT value FROM kv_store WHERE key = ?",
                arrayOf(key)
            )
            
            cursor.use {
                return if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get KV: $key", e)
            return null
        } finally {
            db.close()
        }
    }

    /**
     * 设置 KV 存储值
     */
    fun setKV(context: Context, key: String, value: String) {
        val db = openDatabase(context) ?: return
        
        try {
            db.execSQL(
                "INSERT OR REPLACE INTO kv_store (key, value) VALUES (?, ?)",
                arrayOf(key, value)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set KV: $key", e)
        } finally {
            db.close()
        }
    }

    /**
     * 打开 Flutter 的 SQLite 数据库
     */
    private fun openDatabase(context: Context): SQLiteDatabase? {
        try {
            val dbPath = File(context.getDatabasePath("tidebot.db").absolutePath)
            if (!dbPath.exists()) {
                Log.e(TAG, "Database not found: ${dbPath.absolutePath}")
                return null
            }
            return SQLiteDatabase.openDatabase(
                dbPath.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open database", e)
            return null
        }
    }
}