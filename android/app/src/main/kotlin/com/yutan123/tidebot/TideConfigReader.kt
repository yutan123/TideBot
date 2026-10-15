package com.yutan123.tidebot

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject

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
                val maxTokens = (if (it.isNull(3) || it.getInt(3) <= 0) 10000 else it.getInt(3)).coerceIn(1000, 128000)
                val isDisabled = it.getInt(4) == 1

                val chatModel = getModelConfig(context, db, chatModelId.orEmpty())

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
     *
     * Flutter 把模型配置存在 kv_store 的 provider_list 键中，格式：
     * [{"id":"...","name":"...","url":"...","key":"...","model":"..."},...]
     */
    private fun getModelConfig(context: Context, db: SQLiteDatabase, modelId: String): ModelConfig? {
        try {
            val cursor = db.rawQuery(
                "SELECT value FROM kv_store WHERE key = ?",
                arrayOf("provider_list")
            )

            cursor.use {
                if (!it.moveToFirst()) return null

                val json = it.getString(0) ?: return null
                val array = org.json.JSONArray(json)

                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val name = item.optString("name", "")
                    val url = item.optString("url", "")
                    val rawModel = item.optString("model", "")
                    val id = item.optString("id", "").ifBlank { "legacy_p_${name}_${url}_${rawModel}" }

                    if (id == modelId || (modelId.isBlank() && i == 0)) {
                        return ModelConfig(
                            id = id,
                            type = "chat",
                            name = item.optString("name", ""),
                            baseUrl = item.optString("url", ""),
                            apiKey = item.optString("key", ""),
                            model = rawModel.ifBlank { name }.substringBefore(",").trim()
                        )
                    }
                }

                return null
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
return TideStore.open(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open database", e)
            return null
        }
    }
}