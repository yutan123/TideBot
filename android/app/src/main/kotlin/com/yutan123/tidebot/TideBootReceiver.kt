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
                // 通过 TideMasterScheduler 恢复所有任务
                TideMasterScheduler.restoreAllTasks(context)
                
                // 启动增强版后台任务调度器
                TideEnhancedBackgroundWork.ensureScheduled(context)
                
                // 注册电池监听器
                TideBatteryMonitor.register(context)
                
                Log.d("TideBootReceiver", "System restored, all tasks recovered")
            }
            Intent.ACTION_USER_PRESENT -> {
                // 用户解锁屏幕，触发补偿任务（通过 WorkManager）
                TideEnhancedBackgroundWork.ensureScheduled(context)
                Log.d("TideBootReceiver", "User present, background work scheduled")
            }
        }
    }
}