package com.yutan123.tidebot

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class TideBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val pending = goAsync()
        val app = context.applicationContext
        Thread {
            fun restoreStep(name: String, action: () -> Unit) {
                runCatching(action).onFailure { Log.e("TideBootReceiver", "$name restore failed", it) }
            }
            try {
                restoreStep("Worker") { TideEnhancedBackgroundWork.ensureScheduled(app) }
                restoreStep("Future tasks") { TideFutureTasks.reconcile(app) }
                restoreStep("Vital signs") {
                    for (id in TideConfigReader.getEnabledBotIds(app)) {
                        restoreStep("Vital signs: $id") { TideVitalSigns.tick(app, id) }
                    }
                }
                restoreStep("Proactive replies") { TideProactiveTasks.reconcile(app) }
                restoreStep("Registered tasks") { TideMasterScheduler.restoreAllTasks(app) }
            } finally {
                pending.finish()
            }
        }.start()
    }
}