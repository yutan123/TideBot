package com.yutan123.tidebot

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/** Runs the same Dart request builder as foreground chat, without opening an Activity. */
object TideProactiveReplyEngine {
    suspend fun generate(context: Context, botId: String): JSONObject = withContext(Dispatchers.Main) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context.applicationContext)
        loader.ensureInitializationComplete(context.applicationContext, null)
        val engine = FlutterEngine(context.applicationContext)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "tidebot/proactive_reply")
        val native = MethodChannel(engine.dartExecutor.binaryMessenger, "tidebot.native.channel")
        val completed = CompletableDeferred<JSONObject>()
        native.setMethodCallHandler { call, result ->
            if (call.method == "deviceContext") {
                runCatching {
                    TideDeviceContext.read(context, call.argument<List<String>>("allowed")?.toSet() ?: emptySet())
                }.fold(result::success) { result.error("DEVICE_CONTEXT_FAILED", it.message, null) }
            } else {
                result.notImplemented()
            }
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                result.success(null)
                channel.invokeMethod("generate", mapOf("botId" to botId), object : MethodChannel.Result {
                    override fun success(value: Any?) {
                        if (value is Map<*, *>) completed.complete(JSONObject(value))
                        else completed.completeExceptionally(IllegalStateException("Invalid proactive response"))
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        completed.completeExceptionally(IllegalStateException("$code: $message"))
                    }
                    override fun notImplemented() {
                        completed.completeExceptionally(IllegalStateException("Proactive entry point unavailable"))
                    }
                })
            } else result.notImplemented()
        }
        try {
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "proactiveReplyMain")
            )
            withTimeout(5 * 60 * 1000L) { completed.await() }
        } finally {
            channel.setMethodCallHandler(null)
            native.setMethodCallHandler(null)
            engine.destroy()
        }
    }
}
