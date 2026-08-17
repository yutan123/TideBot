package com.yutan123.tidebot

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Disabled until the user explicitly enables TideBot in Android Accessibility
 * settings. Flutter still applies the selected bot, whitelist, and per-action
 * confirmation before requesting any action.
 */
class TideAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile var instance: TideAccessibilityService? = null

        fun visibleText(): String {
            val root = instance?.rootInActiveWindow ?: return ""
            val parts = ArrayList<String>()
            fun collect(node: AccessibilityNodeInfo?) {
                if (node == null || parts.joinToString(" ").length >= 800) return
                node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { parts.add(it) }
                for (index in 0 until node.childCount) collect(node.getChild(index))
            }
            collect(root)
            return parts.joinToString(" ").take(800)
        }

        fun state(): Map<String, Any> = mapOf(
            "enabled" to (instance != null),
            "packageName" to (instance?.rootInActiveWindow?.packageName?.toString() ?: "")
        )
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    fun performAction(action: String, x: Int?, y: Int?, text: String?): Boolean {
        val root = rootInActiveWindow ?: return false
        return when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "click" -> if (x != null && y != null) tap(x, y) else false
            "input" -> inputText(root, text.orEmpty())
            else -> false
        }
    }

    private fun tap(x: Int, y: Int): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 60)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun inputText(root: AccessibilityNodeInfo, text: String): Boolean {
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = android.os.Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }
}
