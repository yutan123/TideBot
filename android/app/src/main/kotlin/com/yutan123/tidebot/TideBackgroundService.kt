package com.yutan123.tidebot

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

/**
 * 前台服务，承载长时间后台任务。
 * 持有 WakeLock，保证 AI 请求不被系统杀死。
 */
class TideBackgroundService : Service() {
    private val binder = LocalBinder()
    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val activeTasks = java.util.concurrent.atomic.AtomicInteger(0)

    inner class LocalBinder : Binder() {
        fun getService(): TideBackgroundService = this@TideBackgroundService
    }

    companion object {
        private const val TAG = "TideBackgroundService"
        private const val CHANNEL_ID = "tide_bot_background"
        private const val NOTIFICATION_ID = 999
        const val ACTION_EXECUTE_TASK = "com.yutan123.tidebot.EXECUTE_TASK"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_SCHEDULED_TIME = "scheduled_time"

        fun startTask(context: Context, taskId: String, scheduledTime: Long) {
            val intent = Intent(context, TideBackgroundService::class.java).apply {
                action = ACTION_EXECUTE_TASK
                putExtra(EXTRA_TASK_ID, taskId)
                putExtra(EXTRA_SCHEDULED_TIME, scheduledTime)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("初始化中..."))
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")
        
        when (intent?.action) {
            ACTION_EXECUTE_TASK -> {
                val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: ""
                val scheduledTime = intent.getLongExtra(EXTRA_SCHEDULED_TIME, 0L)
                
                if (taskId.isNotEmpty()) {
                    activeTasks.incrementAndGet()
                    updateNotification("执行任务: $taskId")
                    serviceScope.launch {
                        try {
                            TideTaskExecutor.executeTask(applicationContext, taskId, scheduledTime)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            Log.e(TAG, "Task execution failed: $taskId", e)
                        } finally {
                            activeTasks.decrementAndGet()
                            stopIfIdle()
                        }
                    }
                } else {
                    stopIfIdle()
                }
            }
            else -> stopIfIdle()
        }

        // 被系统回收后不自动以空 Intent 重启，任务由闹钟/WorkManager 重新触发
        return START_NOT_STICKY
    }

    /** 没有正在执行的任务时才停止，避免并发任务被提前中断 */
    private fun stopIfIdle() {
        if (activeTasks.get() <= 0 && !TideTaskExecutor.hasPendingTasks(applicationContext)) {
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        serviceScope.cancel()
        releaseWakeLock()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TideBot 后台任务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "执行主动回复、体征监测等长时间 AI 任务"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TideBot 后台任务")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(content: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(content))
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$TAG::TaskLock"
        ).apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L) // 10 分钟，足够完成任何 AI 请求
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}