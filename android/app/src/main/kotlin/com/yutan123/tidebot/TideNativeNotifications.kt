package com.yutan123.tidebot

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

object TideNativeNotifications {
    @Volatile var activityVisible = false
    private fun channel(context: Context, id: String, title: String, importance: Int): NotificationManager {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(id, title, importance))
        return manager
    }

    fun workNotification(context: Context): Notification {
        channel(context, "tide_bot_background", "TideBot 后台任务", NotificationManager.IMPORTANCE_LOW)
        return NotificationCompat.Builder(context, "tide_bot_background")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("TideBot 后台任务")
            .setContentText("正在处理到期任务").setOngoing(true).build()
    }

    @Synchronized
    fun deliverPending(context: Context) {
        if (activityVisible) return
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        TideStore.open(context).use { db ->
            if (TideStore.kv(db, "unread_notifications") == "false") return
            for (row in TideStore.rows(db, "SELECT m.*,b.name FROM background_messages m JOIN bots b ON b.id=m.bot_id WHERE m.displayed=0 AND m.synced_to_chat=1 AND NOT EXISTS (SELECT 1 FROM kv_store k WHERE k.key='native_notified_' || m.message_id AND k.value='true') ORDER BY m.timestamp LIMIT 100")) {
                val id = row.getString("message_id")
                if (TideStore.kv(db, "native_notified_$id") == "true") continue
                val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                val pending = PendingIntent.getActivity(context, id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val manager = channel(context,"tide_native_messages","机器人消息",NotificationManager.IMPORTANCE_DEFAULT)
                manager.notify(id, 1, NotificationCompat.Builder(context,"tide_native_messages")
                    .setSmallIcon(android.R.drawable.ic_dialog_email).setContentTitle(row.optString("name","TideBot"))
                    .setContentText(row.getString("content")).setStyle(NotificationCompat.BigTextStyle().bigText(row.getString("content")))
                    .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build())
                TideStore.put(db, "native_notified_$id", "true")
            }
        }
    }
}
