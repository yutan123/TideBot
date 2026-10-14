package com.yutan123.tidebot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log

/**
 * 电池状态监听器，根据电量和充电状态动态调整后台任务频率。
 * 低电量时延长 WorkManager 周期，充电时恢复正常频率。
 */
object TideBatteryMonitor {
    private const val TAG = "TideBatteryMonitor"
    private const val PREFS_NAME = "TideBotNative"
    private const val KEY_LOW_BATTERY = "low_battery"
    private const val KEY_IS_CHARGING = "is_charging"
    private const val KEY_BATTERY_LEVEL = "battery_level"
    
    private var receiver: BroadcastReceiver? = null

    fun register(context: Context) {
        if (receiver != null) {
            Log.w(TAG, "Already registered")
            return
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_BATTERY_LOW -> {
                        Log.d(TAG, "Battery low detected")
                        handleBatteryLow(context)
                    }
                    Intent.ACTION_BATTERY_OKAY -> {
                        Log.d(TAG, "Battery okay")
                        handleBatteryOkay(context)
                    }
                    Intent.ACTION_POWER_CONNECTED -> {
                        Log.d(TAG, "Power connected")
                        handlePowerConnected(context)
                    }
                    Intent.ACTION_POWER_DISCONNECTED -> {
                        Log.d(TAG, "Power disconnected")
                        handlePowerDisconnected(context)
                    }
                    Intent.ACTION_BATTERY_CHANGED -> {
                        updateBatteryInfo(context, intent)
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_LOW)
            addAction(Intent.ACTION_BATTERY_OKAY)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }

        context.registerReceiver(receiver, filter)
        Log.d(TAG, "Battery monitor registered")

        // 立即读取当前电池状态
        queryCurrentState(context)
    }

    fun unregister(context: Context) {
        receiver?.let {
            try {
                context.unregisterReceiver(it)
                Log.d(TAG, "Battery monitor unregistered")
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Receiver not registered", e)
            }
            receiver = null
        }
    }

    private fun queryCurrentState(context: Context) {
        val batteryStatus = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        batteryStatus?.let { updateBatteryInfo(context, it) }
    }

    private fun updateBatteryInfo(context: Context, intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
        
        val batteryPct = if (level >= 0 && scale > 0) {
            (level * 100 / scale)
        } else {
            -1
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_IS_CHARGING, isCharging)
            .putInt(KEY_BATTERY_LEVEL, batteryPct)
            .putLong("battery_update_time", System.currentTimeMillis())
            .apply()

        Log.d(TAG, "Battery: $batteryPct%, charging=$isCharging")
    }

    private fun handleBatteryLow(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_LOW_BATTERY, true)
            .putLong("battery_low_time", System.currentTimeMillis())
            .apply()

        // 延长 WorkManager 周期到 30 分钟
        TideEnhancedBackgroundWork.adjustPeriod(context, lowPowerMode = true)
    }

    private fun handleBatteryOkay(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_LOW_BATTERY, false)
            .putLong("battery_okay_time", System.currentTimeMillis())
            .apply()

        // 恢复正常 15 分钟周期
        TideEnhancedBackgroundWork.adjustPeriod(context, lowPowerMode = false)
    }

    private fun handlePowerConnected(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_IS_CHARGING, true)
            .putLong("power_connected_time", System.currentTimeMillis())
            .apply()

        // 充电时可以更积极地执行任务
        TideEnhancedBackgroundWork.adjustPeriod(context, lowPowerMode = false)
    }

    private fun handlePowerDisconnected(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isLowBattery = prefs.getBoolean(KEY_LOW_BATTERY, false)
        
        prefs.edit()
            .putBoolean(KEY_IS_CHARGING, false)
            .putLong("power_disconnected_time", System.currentTimeMillis())
            .apply()

        // 如果断电且电量低，切换到低功耗模式
        if (isLowBattery) {
            TideEnhancedBackgroundWork.adjustPeriod(context, lowPowerMode = true)
        }
    }

    fun isLowBattery(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_LOW_BATTERY, false)
    }

    fun isCharging(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_IS_CHARGING, false)
    }

    fun getBatteryLevel(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getInt(KEY_BATTERY_LEVEL, -1)
    }
}
