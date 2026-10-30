package com.yutan123.tidebot

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.util.Locale

/** OEM autostart is a settings page, not a runtime permission we can grant/query. */
object TideAutoStartSettings {
    fun open(activity: Activity): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val components = when {
            manufacturer.contains("xiaomi") -> listOf(
                "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity")
            manufacturer.contains("huawei") -> listOf(
                "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity")
            manufacturer.contains("honor") -> listOf(
                "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")
            manufacturer.contains("oppo") || manufacturer.contains("realme") || manufacturer.contains("oneplus") -> listOf(
                "com.oplus.safecenter" to "com.oplus.safecenter.startupapp.StartupAppListActivity",
                "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity")
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> listOf(
                "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")
            manufacturer.contains("asus") -> listOf(
                "com.asus.mobilemanager" to "com.asus.mobilemanager.entry.FunctionActivity")
            else -> emptyList()
        }
        val intents = components.map { (pkg, cls) ->
            Intent().setComponent(ComponentName(pkg, cls))
                .putExtra("package_name", activity.packageName)
                .putExtra("packageName", activity.packageName)
        } + Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${activity.packageName}"))
        for (intent in intents) {
            try {
                activity.startActivity(intent)
                return true
            } catch (_: android.content.ActivityNotFoundException) {
                // OEM paths vary by OS version; fall back to app settings.
            } catch (_: SecurityException) {
                // Some vendors expose an internal, non-exported activity.
            }
        }
        return false
    }
}