package com.yutan123.tidebot

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin
import org.json.JSONObject

/** Deliver wakes through the plugin pipe; service Intent actions are ignored by the plugin. */
object TideServiceWake {
    fun start(context: Context, action: String) {
        val intent = Intent().apply {
            setClassName(context, "id.flutter.flutter_background_service.BackgroundService")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
        else context.startService(intent)
        val handler = Handler(Looper.getMainLooper())
        val deadline = android.os.SystemClock.elapsedRealtime() + 30000
        val pipe = FlutterBackgroundServicePlugin.servicePipe
        val deliver = object : Runnable {
            override fun run() {
                synchronized(pipe) {
                    if (pipe.hasListener()) {
                        pipe.invoke(JSONObject().put("method", action).put("args", JSONObject()))
                        return
                    }
                }
                if (android.os.SystemClock.elapsedRealtime() < deadline) handler.postDelayed(this, 500)
            }
        }
        handler.postDelayed(deliver, 500)
    }
}
