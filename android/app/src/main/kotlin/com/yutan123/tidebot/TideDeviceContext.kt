package com.yutan123.tidebot

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import androidx.core.app.ActivityCompat

object TideDeviceContext {
    fun read(appContext: Context, allowed: Set<String>): Map<String, Any> {
        val context = mutableMapOf<String, Any>()
        if (allowed.contains("battery")) {
            val manager = appContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val level = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (level >= 0) context["battery"] = "$level%"
        }
        if (allowed.contains("notifications") && TideNotificationListenerService.connected) {
            context["notifications"] = TideNotificationListenerService.snapshot()
        }
        if (allowed.contains("app_usage") && hasUsageAccess(appContext)) {
            val usage = appContext.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            context["app_usage"] = usage.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, end - 86400000L, end)
                .filter { it.totalTimeInForeground > 0 }
                .sortedByDescending { it.totalTimeInForeground }
                .take(15)
                .map { mapOf("packageName" to it.packageName, "foregroundMs" to it.totalTimeInForeground) }
        }
        if (allowed.contains("location") && ActivityCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            val lm = appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val location = lm.getProviders(true).mapNotNull { provider -> runCatching { lm.getLastKnownLocation(provider) }.getOrNull() }
                .maxByOrNull { it.time }
            if (location != null) context["location"] = mapOf("latitude" to location.latitude, "longitude" to location.longitude, "accuracy" to location.accuracy)
        }
        return context
    }

    private fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, context.applicationInfo.uid, context.packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, context.applicationInfo.uid, context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
