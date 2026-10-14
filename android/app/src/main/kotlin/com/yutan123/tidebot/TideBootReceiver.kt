package com.yutan123.tidebot
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class TideBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("TideBootReceiver", "Received action: $action")
        
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // 恢复 Flutter 侧普通定时任务的闹钟
                TideAlarmScheduler.restore(context)
                // 恢复 Kotlin 统一调度中心注册的后台任务
                TideMasterScheduler.restoreAllTasks(context)
                
                // 启动增强版后台任务调度器
                TideEnhancedBackgroundWork.ensureScheduled(context)
                
                Log.d("TideBootReceiver", "System restored, all tasks recovered")
            }
        }
    }
}