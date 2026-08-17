package com.yutan123.tidebot

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import kotlin.math.abs

class TideOverlayService : Service() {
    companion object {
        const val ACTION_SHOW = "com.yutan123.tidebot.overlay.SHOW"
        const val ACTION_HIDE = "com.yutan123.tidebot.overlay.HIDE"
        @Volatile var running = false
    }

    private lateinit var windowManager: WindowManager
    private var root: LinearLayout? = null
    private var panel: LinearLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var currentBotId = ""

    override fun onBind(intent: Intent?): IBinder? = null
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun rounded(color: Int, radius: Int, stroke: Int = Color.TRANSPARENT) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
            if (stroke != Color.TRANSPARENT) setStroke(dp(1), stroke)
        }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (root == null && !show(intent)) {
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        return START_STICKY
    }

    private fun setExpanded(expanded: Boolean, input: EditText? = null) {
        panel?.visibility = if (expanded) View.VISIBLE else View.GONE
        val layout = params ?: return
        layout.flags = if (expanded) WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        else WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        layout.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        root?.let { runCatching { windowManager.updateViewLayout(it, layout) } }
        if (expanded && input != null) {
            input.requestFocus()
            (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                .showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun actionButton(icon: Int, label: String, action: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(8), dp(8), dp(6))
            background = rounded(0x182F6FFF, 14, 0x284D8DFF)
            setOnClickListener { action() }
            addView(ImageView(this@TideOverlayService).apply {
                setImageResource(icon)
                setColorFilter(Color.WHITE)
            }, LinearLayout.LayoutParams(dp(26), dp(26)))
            addView(TextView(this@TideOverlayService).apply {
                text = label
                setTextColor(0xFFEFF3FF.toInt())
                textSize = 11f
                gravity = Gravity.CENTER
            })
        }
    }

    private fun openApp(prompt: String = "") {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.putExtra("botId", currentBotId)
            if (prompt.isNotEmpty()) it.putExtra("overlay_prompt", prompt)
            startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        }
    }

    private fun show(intent: Intent?): Boolean {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        currentBotId = intent?.getStringExtra("botId").orEmpty()
        val botName = intent?.getStringExtra("botName").orEmpty().ifBlank { "TideBot" }
        val avatarPath = intent?.getStringExtra("avatarPath").orEmpty()
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
            setPadding(dp(6), dp(6), dp(6), dp(6))
        }
        val input = EditText(this).apply {
            hint = "给 $botName 发消息"
            setHintTextColor(0xFF98A2BD.toInt())
            setTextColor(Color.WHITE)
            maxLines = 3
            textSize = 14f
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = rounded(0xFF20283A.toInt(), 16, 0x334D8DFF)
        }
        val quick = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = rounded(0xF2222939.toInt(), 22, 0x554D8DFF)
            elevation = dp(12).toFloat()
        }
        panel = quick
        quick.addView(TextView(this).apply {
            text = botName
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(dp(2), 0, 0, dp(10))
        })
        val actions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        actions.addView(actionButton(android.R.drawable.ic_menu_view, "打开") { openApp() },
            LinearLayout.LayoutParams(0, dp(68), 1f).apply { marginEnd = dp(6) })
        actions.addView(actionButton(android.R.drawable.ic_btn_speak_now, "语音") { openApp() },
            LinearLayout.LayoutParams(0, dp(68), 1f).apply { marginEnd = dp(6) })
        actions.addView(actionButton(android.R.drawable.ic_menu_close_clear_cancel, "关闭") {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                .putBoolean("flutter.assistant_overlay_enabled", false).apply()
            stopSelf()
        }, LinearLayout.LayoutParams(0, dp(68), 1f))
        quick.addView(actions, LinearLayout.LayoutParams(dp(250), dp(68)))
        quick.addView(input, LinearLayout.LayoutParams(dp(250), WindowManager.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(8) })
        quick.addView(TextView(this).apply {
            text = "发送给机器人"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 14f
            background = rounded(0xFF4D8DFF.toInt(), 15)
            setOnClickListener {
                val text = input.text.toString().trim()
                if (text.isNotEmpty()) {
                    openApp(text)
                    input.setText("")
                    setExpanded(false)
                }
            }
        }, LinearLayout.LayoutParams(dp(250), dp(44)).apply { topMargin = dp(8) })

        val avatarFrame = FrameLayout(this).apply {
            background = rounded(0xFF4D8DFF.toInt(), 36, Color.WHITE)
            elevation = dp(10).toFloat()
        }
        val avatar = ImageButton(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = rounded(0xFF4D8DFF.toInt(), 34)
            contentDescription = "$botName 悬浮助手"
            if (avatarPath.isNotBlank() && File(avatarPath).exists()) setImageURI(Uri.fromFile(File(avatarPath)))
            else {
                setImageResource(android.R.drawable.sym_def_app_icon)
                setColorFilter(Color.WHITE)
            }
        }
        avatarFrame.addView(avatar, FrameLayout.LayoutParams(dp(58), dp(58), Gravity.CENTER))
        var downX = 0f
        var downY = 0f
        var originX = 0
        var originY = 0
        avatar.setOnTouchListener { _, event ->
            val layout = params ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX; downY = event.rawY
                    originX = layout.x; originY = layout.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layout.x = originX + (downX - event.rawX).toInt()
                    layout.y = originY + (event.rawY - downY).toInt()
                    root?.let { windowManager.updateViewLayout(it, layout) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (abs(event.rawX - downX) < dp(8) && abs(event.rawY - downY) < dp(8))
                        setExpanded(panel?.visibility != View.VISIBLE, input)
                    true
                }
                else -> false
            }
        }
        container.addView(quick)
        container.addView(avatarFrame, LinearLayout.LayoutParams(dp(68), dp(68)).apply {
            gravity = Gravity.END
            topMargin = dp(6)
        })
        root = container
        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dp(12)
            y = dp(180)
        }
        return runCatching {
            windowManager.addView(container, params)
            true
        }.getOrElse {
            root = null; panel = null; params = null
            false
        }
    }

    override fun onDestroy() {
        root?.let { if (::windowManager.isInitialized) runCatching { windowManager.removeView(it) } }
        running = false
        root = null
        panel = null
        params = null
        super.onDestroy()
    }
}