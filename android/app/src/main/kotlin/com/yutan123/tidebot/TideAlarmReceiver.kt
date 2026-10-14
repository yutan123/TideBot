package com.yutan123.tidebot
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class TideAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TideAlarmScheduler.taskAction) return
        try {
            val taskId = intent.getStringExtra(TideAlarmScheduler.taskIdExtra) ?: return
            val scheduledTime = intent.getLongExtra("scheduled_time", System.currentTimeMillis())
            
            Log.d("TideAlarmReceiver", "Alarm triggered: $taskId at $scheduledTime")
            
            // 如果是重复任务，重新设置下一次闹钟
            if (intent.getBooleanExtra(TideAlarmScheduler.repeatingExtra, false)) {
                TideAlarmScheduler.rearmDaily(context, intent)
            }
            
            // 启动前台服务执行任务
            TideBackgroundService.startTask(context, taskId, scheduledTime)
        } catch (error: Exception) {
            Log.e("TideAlarmReceiver", "Failed to handle alarm", error)
        }
    }
}