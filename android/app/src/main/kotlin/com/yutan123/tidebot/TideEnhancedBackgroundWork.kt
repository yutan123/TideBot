package com.yutan123.tidebot

import android.content.Context
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * 增强版后台任务调度器，替代原有的 TideBackgroundWork。
 * 支持动态调整周期、电池状态感知、网络约束等高级特性。
 */
class TideEnhancedBackgroundWork(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "TideEnhancedBgWork"
        private const val UNIQUE_WORK_NAME = "tidebot_enhanced_background"
        private const val LEGACY_WORK_NAME = "tidebot_background_queue"
        private const val NORMAL_INTERVAL_MINUTES = 15L
        private const val LOW_POWER_INTERVAL_MINUTES = 30L

        /**
         * 确保后台任务已调度，默认使用正常频率（15 分钟）。
         */
        fun ensureScheduled(context: Context) {
            // 旧版 TideBackgroundWork 已删除，取消老安装上残留的周期任务，避免 WorkManager 实例化失败
            WorkManager.getInstance(context).cancelUniqueWork(LEGACY_WORK_NAME)
            val isLowPower = TideBatteryMonitor.isLowBattery(context)
            scheduleWork(context, isLowPower)
        }

        /**
         * 动态调整任务周期。
         * @param lowPowerMode true 时使用 30 分钟周期，false 时使用 15 分钟周期
         */
        fun adjustPeriod(context: Context, lowPowerMode: Boolean) {
            Log.d(TAG, "Adjust period: lowPowerMode=$lowPowerMode")
            scheduleWork(context, lowPowerMode)
        }

        private fun scheduleWork(context: Context, lowPowerMode: Boolean) {
            val intervalMinutes = if (lowPowerMode) {
                LOW_POWER_INTERVAL_MINUTES
            } else {
                NORMAL_INTERVAL_MINUTES
            }

            val constraints = Constraints.Builder()
                .setRequiresBatteryNotLow(!lowPowerMode) // 低功耗模式下允许低电量执行
                .build()

            val request = PeriodicWorkRequestBuilder<TideEnhancedBackgroundWork>(
                intervalMinutes,
                TimeUnit.MINUTES,
                // flex interval: 在周期的最后 5 分钟内执行，给系统更多调度灵活性
                5,
                TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    WorkRequest.MIN_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .addTag("tidebot_periodic")
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE, // 更新现有任务
                request
            )

            Log.d(TAG, "Scheduled periodic work: interval=${intervalMinutes}min, lowPower=$lowPowerMode")
        }

        /**
         * 取消后台任务调度。
         */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
            Log.d(TAG, "Cancelled periodic work")
        }
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "doWork started, attempt ${runAttemptCount + 1}")
        
        return try {
            // 检查是否需要继续执行任务
            if (!shouldExecute()) {
                Log.d(TAG, "Service disabled, skip execution")
                return Result.success()
            }

            // 唤醒 Flutter 后台服务执行实际任务
            TideServiceWake.start(
                applicationContext,
                "com.yutan123.tidebot.ACTION_PERIODIC_QUEUE_WAKE"
            )

            // 记录执行状态
            recordExecution(success = true)
            
            Log.d(TAG, "doWork completed successfully")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "doWork failed", e)
            recordExecution(success = false, error = e.message)
            
            // 失败时重试，WorkManager 会使用指数退避策略
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }

    private fun shouldExecute(): Boolean {
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        val persistentEnabled = prefs.getString("flutter.persistent_notification", null) == "true"
        val externalApiEnabled = prefs.getString("flutter.external_api_enabled", null) == "true"
        return persistentEnabled || externalApiEnabled
    }

    private fun recordExecution(success: Boolean, error: String? = null) {
        val prefs = applicationContext.getSharedPreferences("TideBotNative", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("work_last_execution", System.currentTimeMillis())
            .putBoolean("work_last_success", success)
            .putString("work_last_error", error)
            .putInt("work_run_count", prefs.getInt("work_run_count", 0) + 1)
            .apply()
    }
}