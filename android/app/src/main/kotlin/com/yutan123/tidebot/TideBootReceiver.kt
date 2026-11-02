package com.yutan123.tidebot

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.concurrent.TimeUnit

class TideBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        // Keep the receiver alive until the durable enqueue is committed.
        // Recovery itself runs in WorkManager, outside the broadcast window.
        val pending = goAsync()
        val app = context.applicationContext
        Thread {
            try {
                TideEnhancedBackgroundWork.ensureScheduled(app)
                TideRecoveryWork.enqueue(app).result.get(8, TimeUnit.SECONDS)
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                Log.e("TideBootReceiver", "Recovery registration interrupted", error)
            } catch (error: Exception) {
                Log.e("TideBootReceiver", "Cannot enqueue background recovery", error)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
