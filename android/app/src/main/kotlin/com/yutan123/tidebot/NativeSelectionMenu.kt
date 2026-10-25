package com.yutan123.tidebot

import android.app.Activity
import android.graphics.Rect
import android.os.Build
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Draw only the Android toolbar; Flutter keeps its text and edit callbacks. */
class NativeSelectionMenu(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "tidebot/selection_menu")
    private var mode: ActionMode? = null
    private var session = -1
    private var anchor = Rect()
    private var items: List<Map<*, *>> = emptyList()

    init {
        channel.setMethodCallHandler { call, result ->
            val id = call.argument<Int>("id") ?: -1
            when (call.method) {
                "show" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        result.success(false)
                    } else {
                        val view = activity.findViewById<View>(android.R.id.content)
                        val density = view.resources.displayMetrics.density
                        // Flutter's global origin is the Flutter view's origin,
                        // while ActionMode expects coordinates in the content view.
                        val flutterView = findFlutterView(view) ?: view
                        val contentLocation = IntArray(2)
                        val flutterLocation = IntArray(2)
                        view.getLocationOnScreen(contentLocation)
                        flutterView.getLocationOnScreen(flutterLocation)
                        val x = ((call.argument<Number>("x")?.toFloat() ?: 0f) * density).roundToInt() +
                            flutterLocation[0] - contentLocation[0]
                        val y = ((call.argument<Number>("y")?.toFloat() ?: 0f) * density).roundToInt() +
                            flutterLocation[1] - contentLocation[1]
                        anchor = Rect(x, y, x + 1, y + 1)
                        items = call.argument<List<Map<*, *>>>("items") ?: emptyList()
                        if (session == id && mode != null) {
                            mode?.invalidate()
                            mode?.invalidateContentRect()
                        } else {
                            close()
                            session = id
                            mode = view.startActionMode(object : ActionMode.Callback2() {
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
                                    val index = item.itemId - 1
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
        items.forEachIndexed { index, item ->
            menu.add(Menu.NONE, index + 1, index, item["label"]?.toString().orEmpty()).apply {
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
