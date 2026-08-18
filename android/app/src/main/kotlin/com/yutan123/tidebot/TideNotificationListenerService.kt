package com.yutan123.tidebot

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.CopyOnWriteArrayList

class TideNotificationListenerService : NotificationListenerService() {
    companion object {
        @Volatile var connected = false
        private val recent = CopyOnWriteArrayList<Map<String, Any>>()
        @Volatile var lastEvent: Map<String, Any>? = null

        fun snapshot(): List<Map<String, Any>> = recent.takeLast(20)
    }

    override fun onListenerConnected() {
        connected = true
        recent.clear()
        activeNotifications?.forEach(::record)
    }

    override fun onListenerDisconnected() {
        connected = false
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn != null && sbn.packageName != packageName) record(sbn)
    }

    private fun record(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        val item = mapOf<String, Any>(
            "packageName" to sbn.packageName,
            "title" to (extras.getCharSequence("android.title")?.toString() ?: ""),
            "text" to (extras.getCharSequence("android.text")?.toString() ?: ""),
            "postedAt" to sbn.postTime
        )
        recent.add(item)
        while (recent.size > 20) recent.removeAt(0)
        lastEvent = item
    }
}
