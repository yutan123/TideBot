package com.yutan123.tidebot

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Periodically wakes the existing Flutter background isolate so it can consume
 * the SQLite-backed best-effort queue. Exact user reminders remain AlarmManager
 * work and are not represented by this periodic request.
 */
class TideBackgroundWork(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val serviceIntent = Intent(
            applicationContext,
            id.flutter.flutter_background_service.BackgroundService::class.java,
        ).setAction(ACTION_PERIODIC_WAKE)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(serviceIntent)
            } else {
                applicationContext.startService(serviceIntent)
            }
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    companion object {
        private const val UNIQUE_WORK_NAME = "tidebot_background_queue"
        const val ACTION_PERIODIC_WAKE = "com.yutan123.tidebot.ACTION_PERIODIC_QUEUE_WAKE"

        fun ensureScheduled(context: Context) {
            val request = PeriodicWorkRequestBuilder<TideBackgroundWork>(
                15,
                TimeUnit.MINUTES,
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }
}
