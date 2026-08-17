package com.yutan123.tidebot

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class TideOverlayService : Service() {
    companion object {
        const val ACTION_SHOW = "com.yutan123.tidebot.overlay.SHOW"
        const val ACTION_HIDE = "com.yutan123.tidebot.overlay.HIDE"
    }

    private lateinit var windowManager: WindowManager
    private var root: LinearLayout? = null
    private var panel: LinearLayout? = null
    private var reply: TextView? = null

    override fun onBind(intent: Intent?): IBinder? = null

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
        return START_STICKY
    }

    private fun show(intent: Intent?): Boolean {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val botName = intent?.getStringExtra("botName").orEmpty().ifBlank { "TideBot" }
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(12, 12, 12, 12)
            setBackgroundColor(0xDDFFFFFF.toInt())
        }
        val avatar = Button(this).apply {
            text = botName.take(2)
            setOnClickListener {
                panel?.visibility = if (panel?.visibility == View.VISIBLE) View.GONE else View.VISIBLE
            }
        }
        val quick = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }
        panel = quick
        val input = EditText(this).apply { hint = "给 $botName 发消息" }
        val response = TextView(this).apply {
            visibility = View.GONE
            setPadding(8, 8, 8, 8)
        }
        reply = response
        quick.addView(Button(this).apply {
            text = "关闭悬浮窗"
            setOnClickListener { stopSelf() }
        })
        quick.addView(Button(this).apply {
            text = "打开 TideBot"
            setOnClickListener {
                packageManager.getLaunchIntentForPackage(packageName)?.let {
                    startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        })
        quick.addView(Button(this).apply {
            text = "发送语音"
            setOnClickListener {
                response.text = "请在 TideBot 中按住语音按钮录音"
                response.visibility = View.VISIBLE
            }
        })
        quick.addView(input)
        quick.addView(Button(this).apply {
            text = "发送"
            setOnClickListener {
                val text = input.text.toString().trim()
                if (text.isNotEmpty) {
                    response.text = "已收到：$text\n正在后台请求机器人，请在 TideBot 查看完整回复。"
                    response.visibility = View.VISIBLE
                    packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
                        launch.putExtra("overlay_prompt", text)
                        launch.putExtra("botId", intent?.getStringExtra("botId"))
                        startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                    }
                    input.setText("")
                }
            }
        })
        quick.addView(response)
        container.addView(avatar)
        container.addView(quick)
        root = container
        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            0,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 24
            y = 220
        }
        return runCatching {
            windowManager.addView(container, params)
            true
        }.getOrElse {
            root = null
            panel = null
            reply = null
            false
        }
    }

    override fun onDestroy() {
        root?.let { view ->
            if (::windowManager.isInitialized) {
                runCatching { windowManager.removeView(view) }
            }
        }
        root = null
        panel = null
        reply = null
        super.onDestroy()
    }
}
