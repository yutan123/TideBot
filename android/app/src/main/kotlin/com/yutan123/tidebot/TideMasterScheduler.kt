package com.yutan123.tidebot

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject

/**
 * 统一调度中心，管理所有任务的注册、取消、恢复。
 * 防止 AlarmManager、WorkManager、Flutter Timer 重复调度同一任务。
 */
object TideMasterScheduler {
    private const val TAG = "TideMasterScheduler"

    /**
     * 注册任务
     */
    fun registerTask(
        context: Context,
        taskId: String,
        taskType: String,
        botId: String?,
        triggerTime: Long,
        repeating: Boolean,
        config: JSONObject? = null
    ): Boolean {
        val db = openDatabase(context) ?: return false
        
        try {
            val now = System.currentTimeMillis()
            TideStore.transaction(db) {
                db.execSQL("INSERT OR IGNORE INTO background_tasks (task_id,task_type,bot_id,trigger_time,repeating,enabled,config_json,created_at,updated_at) VALUES (?,?,?,?,?,1,?,?,?)",
                    arrayOf(taskId,taskType,botId,triggerTime,if (repeating) 1 else 0,config?.toString(),now,now))
                db.execSQL("UPDATE background_tasks SET task_type=?,bot_id=?,trigger_time=?,repeating=?,enabled=1,config_json=?,updated_at=? WHERE task_id=?",
                    arrayOf(taskType,botId,triggerTime,if (repeating) 1 else 0,config?.toString(),now,taskId))
            }

            // AlarmManager is a delivery mechanism; SQLite remains authoritative.
            val title = config?.optString("title") ?: "TideBot 任务"
            val scheduled = TideAlarmScheduler.schedule(context, taskId, triggerTime, title, repeating)
            
            Log.d(TAG, "Registered task: $taskId, type=$taskType, trigger=$triggerTime, repeating=$repeating")
            return scheduled
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register task: $taskId", e)
            return false
        } finally {
            db.close()
        }
    }

    /**
     * 取消任务
     */
    fun cancelTask(context: Context, taskId: String): Boolean {
        val db = openDatabase(context) ?: return false
        
        try {
            // 从数据库删除
            db.execSQL("DELETE FROM background_tasks WHERE task_id = ?", arrayOf(taskId))
            
            // 取消 AlarmManager
            TideAlarmScheduler.cancel(context, taskId)
            
            Log.d(TAG, "Cancelled task: $taskId")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel task: $taskId", e)
            return false
        } finally {
            db.close()
        }
    }

    /**
     * 恢复所有任务（开机时调用）
     */
    fun restoreAllTasks(context: Context) {
        val db = openDatabase(context) ?: return
        
        try {
            val cursor = db.rawQuery(
                "SELECT task_id, trigger_time, repeating, config_json FROM background_tasks WHERE enabled = 1",
                emptyArray()
            )
            
            var count = 0
            cursor.use {
                while (it.moveToNext()) {
                    val taskId = it.getString(0)
                    val triggerTime = it.getLong(1)
                    val repeating = it.getInt(2) == 1
                    val configJson = it.getString(3)
                    
                    val config = if (!configJson.isNullOrEmpty()) {
                        try { JSONObject(configJson) } catch (e: Exception) { null }
                    } else null
                    
                    val title = config?.optString("title") ?: "TideBot 任务"
                    TideAlarmScheduler.schedule(context, taskId, triggerTime, title, repeating)
                    count++
                }
            }
            
            Log.d(TAG, "Restored $count tasks")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore tasks", e)
        } finally {
            db.close()
        }
    }

    /**
     * 任务是否由 Kotlin 统一调度中心注册（否则为 Flutter 侧的普通定时任务）
     */
    fun isRegistered(context: Context, taskId: String): Boolean {
        val db = openDatabase(context) ?: return false
        return try {
            db.rawQuery(
                "SELECT 1 FROM background_tasks WHERE task_id = ? AND enabled = 1",
                arrayOf(taskId)
            ).use { it.moveToFirst() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to query task: $taskId", e)
            false
        } finally {
            db.close()
        }
    }

    /**
     * 获取所有待执行任务
     */
    fun getPendingTasks(context: Context): List<String> {
        val db = openDatabase(context) ?: return emptyList()
        
        try {
            val now = System.currentTimeMillis()
            val cursor = db.rawQuery(
                "SELECT task_id FROM background_tasks WHERE enabled = 1 AND trigger_time <= ?",
                arrayOf(now.toString())
            )
            
            val tasks = mutableListOf<String>()
            cursor.use {
                while (it.moveToNext()) {
                    tasks.add(it.getString(0))
                }
            }
            return tasks
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get pending tasks", e)
            return emptyList()
        } finally {
            db.close()
        }
    }

    private fun openDatabase(context: Context): SQLiteDatabase? = try {
        TideStore.open(context)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to open database", e)
        null
    }
}
