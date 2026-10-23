package com.yutan123.tidebot

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

/**
 * 前台服务，承载长时间后台任务。
 * 持有有时限的 WakeLock，减少请求期间 CPU 休眠。
 */
class TideBackgroundService : Service() {
    private val binder = LocalBinder()
    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val activeTasks = java.util.concurrent.atomic.AtomicInteger(0)
    private var latestStartId = 0
    private var foregroundReady = false

    inner class LocalBinder : Binder() {
        fun getService(): TideBackgroundService = this@TideBackgroundService
    }

    companion object {
        private val requestLeases = TideRequestLeases { android.os.SystemClock.elapsedRealtime() }
        @Volatile private var running: TideBackgroundService? = null
        private val handoffLocks = mutableListOf<PowerManager.WakeLock>()
        private fun releaseHandoffs() = synchronized(handoffLocks) {
            handoffLocks.forEach { if (it.isHeld) it.release() }
            handoffLocks.clear()
        }
        private const val ACTION_PROTECT_REQUEST = "com.yutan123.tidebot.PROTECT_REQUEST"
        private val requestHandler = Handler(Looper.getMainLooper())
        private class PendingRequest(
            val complete: (String?) -> Unit,
            val timeout: Runnable,
        )
        private val pendingRequests = mutableMapOf<String, PendingRequest>()
        private const val EXTRA_REQUEST_ID = "request_id"

        // A successful startForegroundService() only queues a service start. Do
        // not let Dart send the HTTP request until onStartCommand confirms that
        // startForeground() and the wake lock have actually completed.
        fun beginRequest(context: Context, id: String, complete: (String?) -> Unit) {
            require(id.isNotBlank())
            requestLeases.begin(id)
            val timeout = Runnable {
                requestLeases.end(id)
                completeRequest(id, "前台服务启动确认超时")
                running?.stopIfIdle()
            }
            pendingRequests[id] = PendingRequest(complete, timeout)
            requestHandler.postDelayed(timeout, 8_000L)
            try {
                val intent = Intent(context, TideBackgroundService::class.java)
                    .setAction(ACTION_PROTECT_REQUEST)
                    .putExtra(EXTRA_REQUEST_ID, id)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                requestLeases.end(id)
                completeRequest(id, "${error.javaClass.simpleName}: ${error.message}")
            }
        }
        private fun completeRequest(id: String, error: String?) {
            val pending = pendingRequests.remove(id) ?: return
            requestHandler.removeCallbacks(pending.timeout)
            pending.complete(error)
        }
        fun renewRequest(context: Context, id: String, complete: (String?) -> Unit) {
            val service = running
            if (service == null || !requestLeases.contains(id)) {
                // A live Dart request can restore protection after a service loss
                // or a delayed renewal. Without renewals, leases still expire.
                beginRequest(context, id, complete)
            } else {
                requestLeases.renew(id)
                service.acquireWakeLock()
                complete(null)
            }
        }
        fun endRequest(id: String) {
            requestLeases.end(id)
            completeRequest(id, "请求保护已取消")
            running?.stopIfIdle()
        }
        private const val TAG = "TideBackgroundService"
        private const val CHANNEL_ID = "tide_bot_background"
        private const val NOTIFICATION_ID = 999
        const val ACTION_EXECUTE_TASK = "com.yutan123.tidebot.EXECUTE_TASK"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_SCHEDULED_TIME = "scheduled_time"

        fun startTask(context: Context, taskId: String, scheduledTime: Long) {
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val handoff = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TideBot:ServiceHandoff")
                .apply { setReferenceCounted(false); acquire(15_000L) }
            synchronized(handoffLocks) { handoffLocks.add(handoff) }
            val intent = Intent(context, TideBackgroundService::class.java).apply {
                action = ACTION_EXECUTE_TASK
                putExtra(EXTRA_TASK_ID, taskId)
                putExtra(EXTRA_SCHEDULED_TIME, scheduledTime)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                synchronized(handoffLocks) {
                    handoffLocks.remove(handoff)
                    if (handoff.isHeld) handoff.release()
                }
                throw error
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        try {
            createNotificationChannel()
            startForeground(NOTIFICATION_ID, buildNotification("正在准备后台请求"))
            acquireWakeLock()
            foregroundReady = true
            running = this
        } catch (error: Exception) {
            Log.e(TAG, "Request foreground promotion failed", error)
            pendingRequests.keys.toList().forEach { id ->
                requestLeases.end(id)
                completeRequest(id, "${error.javaClass.simpleName}: ${error.message}")
            }
            releaseHandoffs()
            releaseWakeLock()
            stopSelf()
            return
        }
        serviceScope.launch {
            while (isActive) {
                delay(60_000)
                withContext(Dispatchers.Main.immediate) {
                    if (activeTasks.get() > 0 || requestLeases.hasActive()) acquireWakeLock()
                    stopIfIdle()
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")
        
        latestStartId = startId
        if (!foregroundReady) {
            releaseHandoffs()
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        acquireWakeLock()
        releaseHandoffs()
        when (intent?.action) {
            ACTION_PROTECT_REQUEST -> {
                updateNotification("正在接收回复，可切换到后台")
                val id = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
                if (requestLeases.contains(id)) completeRequest(id, null)
                else completeRequest(id, "请求保护已过期")
                stopIfIdle()
            }
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
                            withContext(NonCancellable + Dispatchers.Main.immediate) {
                                activeTasks.decrementAndGet()
                                stopIfIdle()
                            }
                        }
                    }
                } else {
                    stopIfIdle()
                }
            }
            else -> stopIfIdle()
        }

        // Native deliveries are durable and deduplicated; let Android redeliver
        // an interrupted task. UI requests expire when their lease renewals stop.
        return if (activeTasks.get() > 0) START_REDELIVER_INTENT else START_NOT_STICKY
    }

    /** 没有正在执行的任务时才停止，避免并发任务被提前中断 */
    private fun stopIfIdle() {
        if (activeTasks.get() <= 0 && !requestLeases.hasActive()) {
            stopSelfResult(latestStartId)
        }
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        foregroundReady = false
        if (running === this) running = null
        serviceScope.cancel()
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        foregroundReady = false
        if (running === this) running = null
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
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$TAG::TaskLock"
        ).apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L) // 有时限保护；活跃请求定期续期
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}