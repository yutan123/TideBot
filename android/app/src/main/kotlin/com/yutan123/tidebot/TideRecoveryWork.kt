package com.yutan123.tidebot

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.Operation
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import java.util.concurrent.TimeUnit

/** Rebuild durable deliveries without opening the UI or starting a boot-time FGS. */
class TideRecoveryWork(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    companion object {
        private const val NAME = "tidebot_background_recovery"

        fun enqueue(context: Context, delaySeconds: Long = 2): Operation {
            val request = OneTimeWorkRequestBuilder<TideRecoveryWork>()
                .setInitialDelay(delaySeconds, TimeUnit.SECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            // All lifecycle/network/boot signals share one recovery. Never cancel
            // an in-flight recovery when another signal arrives.
            return WorkManager.getInstance(context).enqueueUniqueWork(NAME, ExistingWorkPolicy.KEEP, request)
        }
    }

    override suspend fun doWork(): Result {
        if (!applicationContext.getDatabasePath("tidebot.db").exists()) return Result.success()
        return try {
            TideEnhancedBackgroundWork.ensureScheduled(applicationContext)
            TideFutureTasks.reconcile(applicationContext)
            for (id in TideConfigReader.getEnabledBotIds(applicationContext)) {
                if (!TideMasterScheduler.isRegistered(applicationContext, "vitals:$id")) {
                    TideVitalSigns.tick(applicationContext, id)
                }
            }
            TideProactiveTasks.reconcile(applicationContext)
            // Restores both alarm delivery and unique per-deadline Workers,
            // including overdue/interrupted tasks. Execution leases deduplicate.
            TideMasterScheduler.restoreAllTasks(applicationContext)
            TideNativeNotifications.deliverPending(applicationContext)
            Log.i("TideRecovery", "Background task delivery restored")
            Result.success()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.e("TideRecovery", "Recovery deferred; will retry", error)
            Result.retry()
        }
    }
}
