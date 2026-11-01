package com.yutan123.tidebot

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** SAF export using a bounded buffer on a worker; never retains file bytes. */
class DataTransfer(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "tidebot.data_transfer")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private var copying = false
    companion object { const val REQUEST = 19347 }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> {
                    if (pending != null) {
                        result.error("BUSY", "正在保存数据", null)
                        return@setMethodCallHandler
                    }
                    pending = result
                    try {
                        val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                        require(file.isFile && file.path.startsWith(activity.cacheDir.canonicalPath + File.separator)) {
                            "无效的临时导出文件"
                        }
                        source = file
                        pending = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mime") ?: "application/zip"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "tidebot.zip")
                        }
                        activity.startActivityForResult(intent, REQUEST)
                    } catch (e: Exception) { finishError(e) }
                }
                "freeSpace" -> {
                    try {
                        val file = File(requireNotNull(call.argument<String>("path")))
                        result.success(StatFs(file.absolutePath).availableBytes)
                    } catch (e: Exception) { result.error("STORAGE", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        if (copying) return true
        val uri = data?.data
        val file = source
        if (code != Activity.RESULT_OK || uri == null || file == null) {
            finish(null)
            return true
        }
        copying = true
        worker.execute {
            try {
                file.inputStream().use { input ->
                    val stream = activity.contentResolver.openOutputStream(uri, "wt")
                        ?: throw java.io.IOException("无法打开所选保存位置")
                    stream.use { output -> input.copyTo(output, 64 * 1024); output.flush() }
                }
                main.post { finish(uri.toString()) }
            } catch (e: Exception) {
                // Remove incomplete output rather than leave a seemingly valid backup.
                runCatching { android.provider.DocumentsContract.deleteDocument(activity.contentResolver, uri) }
                main.post { finishError(e) }
            }
        }
        return true
    }

    private fun finish(value: String?) {
        val result = pending
        pending = null
        source = null
        copying = false
        result?.success(value)
    }

    private fun finishError(error: Exception) {
        val result = pending
        pending = null
        source = null
        copying = false
        result?.error("EXPORT_FAILED", error.message ?: "保存失败", null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        // During a copy, completion must run before Dart removes the source.
        if (!copying) finishError(IllegalStateException("保存已中断，请重试"))
        worker.shutdown()
    }
}
