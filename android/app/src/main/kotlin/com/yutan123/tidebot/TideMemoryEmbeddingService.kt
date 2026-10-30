package com.yutan123.tidebot

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import android.util.Log
import java.util.concurrent.Executors

/** A native signal in ONNX terminates only :memory_embedding, not the chat process. */
class TideMemoryEmbeddingService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { request ->
        if (request.what == EMBED) {
            val id = request.arg1
            val reply = request.replyTo
            val texts = request.data.getStringArrayList("texts").orEmpty()
            if (reply != null) worker.execute { infer(id, texts, reply) }
        }
        true
    })

    override fun onBind(intent: Intent): IBinder = messenger.binder

    private fun infer(id: Int, texts: List<String>, reply: Messenger) {
        val data = Bundle()
        try {
            require(texts.size in 1..8 && texts.sumOf { it.length } <= 100000) {
                "Invalid embedding request"
            }
            // This entry survives in logcat even if JNI aborts before an exception can be caught.
            Log.i(TAG, "Inference start request=$id count=${texts.size} chars=${texts.sumOf { it.length }}")
            val vectors = TideMemoryEmbeddingEngine.vectors(applicationContext, texts)
            data.putInt("count", vectors.size)
            vectors.forEachIndexed { index, vector -> data.putDoubleArray("vector_$index", vector.toDoubleArray()) }
            Log.i(TAG, "Inference complete request=$id")
        } catch (error: LinkageError) {
            failure(data, "Native runtime unavailable", error)
        } catch (error: OutOfMemoryError) {
            failure(data, "Insufficient memory for local embeddings", error)
        } catch (error: Exception) {
            failure(data, error.message ?: "Local embedding failed", error)
        }
        try {
            reply.send(Message.obtain(null, EMBED, id, 0).apply { this.data = data })
        } catch (_: RemoteException) {
            // The requesting engine/process has gone away.
        }
    }

    private fun failure(data: Bundle, message: String, error: Throwable) {
        Log.e(TAG, message, error)
        data.putString("error", message)
    }

    override fun onDestroy() {
        // Never close a native session concurrently with an inference still in progress.
        worker.execute { TideMemoryEmbeddingEngine.close() }
        worker.shutdown()
        super.onDestroy()
    }

    companion object {
        const val EMBED = 1
        private const val TAG = "TideMemoryEmbedding"
    }
}
