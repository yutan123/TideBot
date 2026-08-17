package com.yutan123.tidebot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class TideAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile var instance: TideAccessibilityService? = null
        @Volatile var lastEvent: Map<String, Any>? = null

        fun visibleText(): String {
            val root = instance?.rootInActiveWindow ?: return ""
            val parts = ArrayList<String>()
            fun collect(node: AccessibilityNodeInfo?) {
                if (node == null || parts.sumOf { it.length } >= 2000) return
                node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(parts::add)
                node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(parts::add)
                for (index in 0 until node.childCount) collect(node.getChild(index))
            }
            collect(root)
            return parts.distinct().joinToString(" ").take(2000)
        }

        fun state(): Map<String, Any> = mapOf(
            "enabled" to (instance != null),
            "packageName" to (instance?.rootInActiveWindow?.packageName?.toString() ?: ""),
            "screenText" to visibleText()
        )
    }

    override fun onServiceConnected() { instance = this }
    override fun onDestroy() { if (instance === this) instance = null; super.onDestroy() }
    override fun onInterrupt() = Unit

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.packageName?.toString() == packageName) return
        val type = when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> "app_opened"
            AccessibilityEvent.TYPE_VIEW_CLICKED -> "view_clicked"
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> "text_changed"
            else -> "screen_changed"
        }
        lastEvent = mapOf(
            "type" to type,
            "packageName" to (event.packageName?.toString() ?: ""),
            "className" to (event.className?.toString() ?: ""),
            "text" to event.text.joinToString(" ").take(300),
            "time" to System.currentTimeMillis()
        )
    }

    fun performAction(action: String, x: Int?, y: Int?, text: String?, selector: String?): Boolean {
        val root = rootInActiveWindow
        return when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            "click" -> if (x != null && y != null) tap(x, y) else false
            "input" -> root?.let { inputText(it, text.orEmpty()) } ?: false
            "click_selector" -> root?.let { clickSelector(it, selector.orEmpty()) } ?: false
            "scroll_up" -> root?.let { scroll(it, AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) } ?: false
            "scroll_down" -> root?.let { scroll(it, AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) } ?: false
            else -> false
        }
    }

    private fun tap(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        return dispatchGesture(GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 80)).build(), null, null)
    }

    private fun inputText(root: AccessibilityNodeInfo, text: String): Boolean {
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun scroll(node: AccessibilityNodeInfo, action: Int): Boolean {
        if (node.isScrollable && node.performAction(action)) return true
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            if (scroll(child, action)) return true
        }
        return false
    }

    private fun clickSelector(root: AccessibilityNodeInfo, selector: String): Boolean {
        if (selector.isBlank()) return false
        val byId = runCatching { root.findAccessibilityNodeInfosByViewId(selector) }.getOrDefault(emptyList())
        val nodes = if (byId.isNotEmpty()) byId else root.findAccessibilityNodeInfosByText(selector)
        var node: AccessibilityNodeInfo? = nodes.firstOrNull() ?: return false
        while (node != null) {
            if (node.isClickable) return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            node = node.parent
        }
        return false
    }
}