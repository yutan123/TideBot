package com.yutan123.tidebot

import android.app.ActivityManager
import android.os.Build
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** IPC only: this object must never load ONNX/JNI into a Flutter process. */
object TideMemoryEmbedding {
    private const val EMBED = 1
    private const val TIMEOUT_MS = 60000L
    private val main = Handler(Looper.getMainLooper())
    private var unavailableReason: String? = null
    private var app: Context? = null
    private var connection: ServiceConnection? = null
    private var remote: Messenger? = null
    private var nextId = 0
    private var boundAt = 0L
    private data class Pending(val texts: List<String>, val result: MethodChannel.Result, val timeout: Runnable)
    private val pending = linkedMapOf<Int, Pending>()
    private val idle = Runnable { if (pending.isEmpty()) unbind() }
    private val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what == EMBED && pending.containsKey(message.arg1)) {
            val data = message.data
            val error = data.getString("error")
            if (error != null) {
                fail(error)
            } else {
                val request = pending.getValue(message.arg1)
                val vectors = (0 until data.getInt("count")).map { data.getDoubleArray("vector_$it") }
                if (vectors.size != request.texts.size || vectors.any { v ->
                        v == null || v.size != 512 || v.any { !it.isFinite() }
                    }) {
                    fail("Invalid embedding response")
                } else {
                    pending.remove(message.arg1)
                    main.removeCallbacks(request.timeout)
                    request.result.success(vectors.map { checkNotNull(it).toList() })
                    if (pending.isEmpty()) main.postDelayed(idle, TIMEOUT_MS)
                }
            }
        }
        true
    })

    fun register(context: Context, messenger: BinaryMessenger) {
        app = context.applicationContext
        MethodChannel(messenger, "tidebot.memory.embedding").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(unavailableReason == null)
                "embed" -> {
                    val texts = call.argument<List<String>>("texts").orEmpty()
                    if (texts.isEmpty()) result.success(emptyList<List<Double>>())
                    else if (texts.size > 8 || pending.size >= 4) {
                        result.error("MEMORY_EMBEDDING_BUSY", "Embedding request limit reached", null)
                    } else if (unavailableReason != null) {
                        result.error("MEMORY_EMBEDDING", unavailableReason, null)
                    } else {
                        // The tokenizer already accepts at most 20,000 code points. Bound IPC too.
                        val bounded = texts.map { text ->
                            text.substring(0, text.offsetByCodePoints(0, minOf(20000, text.codePointCount(0, text.length))))
                        }
                        if (bounded.sumOf { it.length } > 100000) {
                            result.error("MEMORY_EMBEDDING_SIZE", "Embedding IPC payload too large", null)
                        } else enqueue(bounded, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enqueue(texts: List<String>, result: MethodChannel.Result) {
        main.removeCallbacks(idle)
        val id = ++nextId
        val timeout = Runnable { if (pending.containsKey(id)) fail("Local embedding process timed out") }
        pending[id] = Pending(texts, result, timeout)
        main.postDelayed(timeout, TIMEOUT_MS)
        if (remote != null) send(id)
        else if (connection == null) bind()
    }

    private fun bind() {
        val context = checkNotNull(app)
        val client = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                if (connection !== this) return
                remote = Messenger(binder)
                for (id in pending.keys.toList()) {
                    if (unavailableReason != null) break
                    send(id)
                }
            }
            override fun onServiceDisconnected(name: ComponentName) {
                if (connection === this) fail("Local embedding process exited during inference")
            }
            override fun onBindingDied(name: ComponentName) {
                if (connection === this) fail("Local embedding process binding died")
            }
            override fun onNullBinding(name: ComponentName) {
                if (connection === this) fail("Local embedding process returned no binder")
            }
        }
        connection = client
        boundAt = System.currentTimeMillis()
        try {
            if (!context.bindService(Intent(context, TideMemoryEmbeddingService::class.java), client,
                    Context.BIND_AUTO_CREATE or Context.BIND_WAIVE_PRIORITY)) {
                fail("Cannot bind local embedding process")
            }
        } catch (error: Exception) {
            fail("Cannot bind local embedding process: ${error.message}")
        }
    }

    private fun send(id: Int) {
        val request = pending[id] ?: return
        try {
            checkNotNull(remote).send(Message.obtain(null, EMBED, id, 0).apply {
                replyTo = replies
                data = Bundle().apply { putStringArrayList("texts", ArrayList(request.texts)) }
            })
        } catch (error: Exception) {
            fail("Local embedding IPC failed: ${error.message}")
        }
    }

    private fun fail(reason: String) {
        // Same-UID exit history is available without the shell's DUMP permission.
        val exit = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) runCatching {
            val context = checkNotNull(app)
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getHistoricalProcessExitReasons(context.packageName, 0, 8).firstOrNull {
                it.processName == "${context.packageName}:memory_embedding" && it.timestamp >= boundAt
            }?.let { " (reason=${it.reason}, status=${it.status}, ${it.description})" }
        }.getOrNull().orEmpty() else ""
        val diagnostic = reason + exit
        unavailableReason = diagnostic
        Log.e("TideMemoryEmbedding", diagnostic)
        val requests = pending.values.toList()
        pending.clear()
        unbind()
        for (request in requests) {
            main.removeCallbacks(request.timeout)
            request.result.error("MEMORY_EMBEDDING", diagnostic, null)
        }
    }

    private fun unbind() {
        main.removeCallbacks(idle)
        val client = connection
        connection = null
        remote = null
        if (client != null) runCatching { app?.unbindService(client) }
    }
}