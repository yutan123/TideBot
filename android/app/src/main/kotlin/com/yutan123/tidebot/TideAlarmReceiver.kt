package com.yutan123.tidebot
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.launch

class TideAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TideAlarmScheduler.taskAction) return
        val pending = goAsync()
        val power = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val handoff = power.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "TideBot:AlarmHandoff")
            .apply { setReferenceCounted(false); acquire(15_000L) }
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            try {
                val taskId = intent.getStringExtra(TideAlarmScheduler.taskIdExtra) ?: return@launch
                val scheduledTime = intent.getLongExtra("scheduled_time", System.currentTimeMillis())
                if (intent.getBooleanExtra(TideAlarmScheduler.repeatingExtra, false)) {
                    TideAlarmScheduler.rearmDaily(context, intent)
                }
                if (TideMasterScheduler.isRegistered(context, taskId)) {
                    TideTaskWork.enqueue(context, taskId, scheduledTime).result
                        .get(5, java.util.concurrent.TimeUnit.SECONDS)
                    try {
                        TideBackgroundService.startTask(context, taskId, scheduledTime)
                    } catch (error: Exception) {
                        // Android may reject foreground-service starts from an inexact alarm.
                        // The persisted Worker still executes without a Flutter engine.
                        Log.w("TideAlarmReceiver", "Service start rejected; Worker owns delivery: $taskId", error)
                    }
                } else {
                    TideServiceWake.start(context, TideAlarmScheduler.taskAction)
                }
            } catch (error: Exception) {
                Log.e("TideAlarmReceiver", "Failed to handle alarm", error)
            } finally {
                if (handoff.isHeld) handoff.release()
                pending.finish()
            }
        }
    }
}
