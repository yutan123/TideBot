package com.yutan123.tidebot

import android.content.Context
import android.content.pm.ServiceInfo
import android.util.Log
import androidx.work.*
import kotlinx.coroutines.CancellationException
import java.util.concurrent.TimeUnit

/** Durable per-deadline delivery, independent of permission to start a service from an alarm. */
class TideTaskWork(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    companion object {
        private fun tag(taskId: String) = "tidebot_task:$taskId"

        fun enqueue(context: Context, taskId: String, scheduledTime: Long): Operation {
            val request = OneTimeWorkRequestBuilder<TideTaskWork>()
                .setInputData(workDataOf("task_id" to taskId, "scheduled_time" to scheduledTime))
                .setInitialDelay((scheduledTime - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 60, TimeUnit.SECONDS)
                .addTag(tag(taskId))
                .build()
            return WorkManager.getInstance(context).enqueueUniqueWork(
                "${tag(taskId)}:$scheduledTime", ExistingWorkPolicy.KEEP, request
            )
        }

        fun cancel(context: Context, taskId: String) {
            WorkManager.getInstance(context).cancelAllWorkByTag(tag(taskId))
        }
    }

    override suspend fun doWork(): Result {
        val taskId = inputData.getString("task_id") ?: return Result.failure()
        val scheduledTime = inputData.getLong("scheduled_time", 0)
        return try {
            val current = TideStore.open(applicationContext).use { db ->
                TideStore.rows(db, "SELECT trigger_time FROM background_tasks WHERE task_id=? AND enabled=1", taskId)
                    .firstOrNull()?.optLong("trigger_time")
            }
            // A reschedule/cancel invalidates deliveries for the old deadline.
            if (current != scheduledTime) return Result.success()
            if (scheduledTime > System.currentTimeMillis()) return Result.retry()
            try {
                setForeground(ForegroundInfo(998, TideNativeNotifications.workNotification(applicationContext),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC))
            } catch (error: CancellationException) {
                throw error
            } catch (error: IllegalStateException) {
                // Android 12+/15 can reject FGS starts/quotas. A regular Worker
                // still has a wakelock and a 10-minute window for this 5-minute request.
                Log.w("TideTaskWork", "Foreground promotion unavailable; using Worker execution", error)
            }
            TideTaskExecutor.executeTask(applicationContext, taskId, scheduledTime)
            val status = TideStore.open(applicationContext).use { db ->
                TideStore.rows(db, "SELECT status FROM background_task_executions WHERE task_id=? AND scheduled_time=?",
                    taskId, scheduledTime.toString()).firstOrNull()?.optString("status")
            }
            // The alarm's service may still own the lease. Retry until it completes or expires.
            if (status == "success" || status == "skipped") Result.success() else Result.retry()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.e("TideTaskWork", "Task delivery failed: $taskId", error)
            Result.retry()
        }
    }
}
