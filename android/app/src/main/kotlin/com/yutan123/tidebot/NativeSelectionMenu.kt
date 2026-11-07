package com.yutan123.tidebot

import android.app.Activity
import android.graphics.Rect
import android.os.Build
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.MotionEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Android owns toolbar labels; Flutter retains text and editing callbacks. */
class NativeSelectionMenu(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "tidebot/selection_menu")
    private var mode: ActionMode? = null
    private var session = -1
    private var anchor = Rect()
    private var items: List<Map<*, *>> = emptyList()
    private val actionIndices = mutableMapOf<Int, Int>()
    private var handleGesture = false

    /** Suspend before Flutter receives DOWN; a channel round trip is too late
     * when Android dismisses its action mode as the handle is touched.
     * Never consume the event: Flutter must own the complete handle gesture.
     * Toolbar buttons live in their own window and do not pass through here.
     */
    fun beforeTouchEvent(event: MotionEvent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (mode == null) return
                handleGesture = true
                channel.invokeMethod("interaction", mapOf("id" to session, "active" to true))
                mode?.hide(Long.MAX_VALUE)
            }
            MotionEvent.ACTION_MOVE -> {
                if (handleGesture) mode?.hide(Long.MAX_VALUE)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (!handleGesture) return
                handleGesture = false
                channel.invokeMethod("interaction", mapOf("id" to session, "active" to false))
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            val id = call.argument<Int>("id") ?: -1
            when (call.method) {
                "show" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        result.success(false)
                    } else {
                        val root = activity.findViewById<View>(android.R.id.content)
                        val host = findFlutterView(root) ?: root
                        val density = host.resources.displayMetrics.density
                        // Flutter sends logical coordinates. ActionMode expects the
                        // content rect relative to the view that owns the action mode.
                        val x = ((call.argument<Number>("x")?.toFloat() ?: 0f) * density)
                            .roundToInt()
                        val y = ((call.argument<Number>("y")?.toFloat() ?: 0f) * density)
                            .roundToInt()
                        anchor = Rect(x, y, x + 1, y + 1)
                        items = call.argument<List<Map<*, *>>>("items") ?: emptyList()
                        if (handleGesture && session == id) {
                            // A pending Flutter rebuild must not reopen the window
                            // between DOWN and UP while a handle is moving.
                            mode?.hide(Long.MAX_VALUE)
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (session == id && mode != null) {
                            mode?.hide(0)
                            mode?.invalidate()
                            mode?.invalidateContentRect()
                        } else {
                            close()
                            session = id
                            mode = host.startActionMode(object : ActionMode.Callback2() {
                                override fun onCreateActionMode(actionMode: ActionMode, menu: Menu): Boolean {
                                    fill(menu)
                                    return true
                                }
                                override fun onPrepareActionMode(actionMode: ActionMode, menu: Menu): Boolean {
                                    menu.clear()
                                    fill(menu)
                                    return true
                                }
                                override fun onGetContentRect(actionMode: ActionMode, view: View, outRect: Rect) {
                                    outRect.set(anchor)
                                }
                                override fun onActionItemClicked(actionMode: ActionMode, item: MenuItem): Boolean {
                                    if (mode !== actionMode) return false
                                    val selectedSession = id
                                    val index = actionIndices[item.itemId] ?: return false
                                    close()
                                    channel.invokeMethod("action", mapOf("id" to selectedSession, "index" to index))
                                    return true
                                }
                                override fun onDestroyActionMode(actionMode: ActionMode) {
                                    if (mode === actionMode) {
                                        mode = null
                                        channel.invokeMethod("dismissed", mapOf("id" to id))
                                    }
                                }
                            }, ActionMode.TYPE_FLOATING)
                        }
                        result.success(mode != null)
                    }
                }
                "suspend" -> {
                    // Hide only the toolbar window. Finishing ActionMode here would
                    // dismiss Flutter's menu while a selection handle is being dragged.
                    if (session == id) mode?.hide(Long.MAX_VALUE)
                    result.success(null)
                }
                "hide" -> {
                    if (session == id) close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun findFlutterView(view: View): View? {
        if (view is io.flutter.embedding.android.FlutterView) return view
        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                findFlutterView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun fill(menu: Menu) {
        actionIndices.clear()
        items.forEachIndexed { index, item ->
            val label = when (item["type"]) {
                "cut" -> activity.getText(android.R.string.cut)
                "copy" -> activity.getText(android.R.string.copy)
                "paste" -> activity.getText(android.R.string.paste)
                "selectAll" -> activity.getText(android.R.string.selectAll)
                "share" -> {
                    // shareText is an internal framework string, not a public R.string field.
                    // Resolve it at runtime and retain Flutter's localized label as a fallback.
                    val resourceId = activity.resources.getIdentifier("shareText", "string", "android")
                    if (resourceId != 0) activity.getText(resourceId) else item["label"]?.toString()
                }
                else -> item["label"]?.toString()
            }
            if (label.isNullOrBlank()) return@forEachIndexed
            val actionId = when (item["type"]) {
                "cut" -> android.R.id.cut
                "copy" -> android.R.id.copy
                "paste" -> android.R.id.paste
                "selectAll" -> android.R.id.selectAll
                "share" -> android.R.id.shareText
                else -> index + 1
            }
            actionIndices[actionId] = index
            menu.add(Menu.NONE, actionId, index, label).apply {
                isEnabled = item["enabled"] != false
                setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
            }
        }
    }

    private fun close() {
        val previous = mode
        mode = null
        previous?.finish()
    }

    fun dispose() {
        close()
        channel.setMethodCallHandler(null)
    }
}
