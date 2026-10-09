package com.yutan123.tidebot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class TideAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TideAlarmScheduler.taskAction) return
        try {
            if (intent.getBooleanExtra(TideAlarmScheduler.repeatingExtra, false)) {
                TideAlarmScheduler.rearmDaily(context, intent)
            }
            TideServiceWake.start(context, TideAlarmScheduler.taskAction)
        } catch (error: Exception) {
            Log.e("TideAlarm", "unable to wake background service", error)
        }
    }
}