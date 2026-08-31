package com.yutan123.tidebot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class TideAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TideAlarmScheduler.taskAction) return
        val serviceIntent = Intent(context, id.flutter.flutter_background_service.FlutterBackgroundService::class.java)
            .setAction(TideAlarmScheduler.taskAction)
            .putExtra(
                TideAlarmScheduler.taskIdExtra,
                intent.getStringExtra(TideAlarmScheduler.taskIdExtra)
            )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (error: Exception) {
            Log.e("TideAlarm", "unable to wake background service", error)
        }
    }
}