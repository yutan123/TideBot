package com.yutan123.tidebot
import android.content.Intent
import android.content.Context
import android.os.BatteryManager
import android.provider.Settings
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

import android.graphics.pdf.PdfRenderer
import android.provider.AlarmClock
import androidx.annotation.NonNull
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream


class MainActivity: FlutterActivity() {
    private val CHANNEL = "tidebot.native.channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarmManager" -> {
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    val message = call.argument<String>("message") ?: "TideBot 提醒"
                    
                    val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                        putExtra(AlarmClock.EXTRA_HOUR, hour)
                        putExtra(AlarmClock.EXTRA_MINUTES, minute)
                        putExtra(AlarmClock.EXTRA_MESSAGE, message)
                        putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    }
                    
                    if (intent.resolveActivity(packageManager) != null) {
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "storageInfo" -> {
                    try {
                        fun sizeOf(file: File?): Long {
                            if (file == null || !file.exists()) return 0L
                            if (file.isFile) return file.length()
                            return file.listFiles()?.sumOf { sizeOf(it) } ?: 0L
                        }
                        val stat = StatFs(filesDir.absolutePath)
                        val apk = applicationInfo.sourceDir?.let { File(it) }
                        result.success(mapOf(
                            "total" to stat.totalBytes,
                            "available" to stat.availableBytes,
                            "data" to sizeOf(File(applicationInfo.dataDir)),
                            "apk" to sizeOf(apk),
                            "cache" to sizeOf(cacheDir),
                            "files" to sizeOf(filesDir)
                        ))
                    } catch (_: Exception) { result.success(mapOf<String, Long>()) }
                }
                "vibrate" -> {
                    val duration = (call.argument<Int>("duration") ?: 24).toLong().coerceIn(1L, 500L)
                    val amplitude = (call.argument<Int>("amplitude") ?: 180).coerceIn(1, 255)
                    try {
                        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                        } else {
                            @Suppress("DEPRECATION")
                            getSystemService(VIBRATOR_SERVICE) as Vibrator
                        }
                        if (vibrator?.hasVibrator() != true) {
                            result.success(false)
                        } else {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(VibrationEffect.createOneShot(duration, amplitude))
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(duration)
                            }
                            result.success(true)
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "deviceContext" -> {
                    val allowed = call.argument<List<String>>("allowed")?.toSet() ?: emptySet()
                    val context = mutableMapOf<String, Any>()
                    if (allowed.contains("battery")) {
                        val manager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val level = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        if (level >= 0) context["battery"] = "$level%"
                    }
                    if (allowed.contains("foreground_app")) {
                        context["foreground_app"] = TideAccessibilityService.state()["packageName"] ?: ""
                    }
                    if (allowed.contains("screen_text")) {
                        context["screen_text"] = TideAccessibilityService.visibleText()
                    }
                    result.success(context)
                }
                "accessibilityState" -> result.success(TideAccessibilityService.state())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "executeAccessibilityAction" -> {
                    val action = call.argument<String>("action") ?: ""
                    val x = call.argument<Int>("x")
                    val y = call.argument<Int>("y")
                    val text = call.argument<String>("text")
                    result.success(TideAccessibilityService.instance?.performAction(action, x, y, text) == true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Missing APK path", null)
                    } else {
                        val apk = File(path)
                        if (!apk.exists()) {
                            result.error("missing_file", "APK file does not exist", null)
                        } else {
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", apk)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    }
                }
                "recognizeText" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Missing image path", null)
                    } else {
                        recognizeText(path, result)
                    }
                }
                "prepareVideo" -> {
                    val path = call.argument<String>("path")
                    val intervalMs = call.argument<Int>("intervalMs") ?: 3000
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Missing video path", null)
                    } else {
                        Thread {
                            val output = try {
                                prepareVideo(path, intervalMs)
                            } catch (e: Exception) {
                                mapOf("error" to (e.message ?: "视频预处理失败"))
                            }
                            runOnUiThread { result.success(output) }
                        }.start()
                    }
                }
                "extractPdfText" -> {
                    val path = call.argument<String>("path")
                    val maxPages = (call.argument<Int>("maxPages") ?: 3).coerceIn(1, 6)
                    val maxChars = (call.argument<Int>("maxChars") ?: 120000).coerceIn(1000, 200000)
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Missing PDF path", null)
                    } else {
                        extractPdfText(path, maxPages, maxChars, result)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun recognizeText(path: String, result: MethodChannel.Result) {
        try {
            val image = InputImage.fromFilePath(this, Uri.fromFile(File(path)))
            val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
            recognizer.process(image)
                .addOnSuccessListener { result.success(it.text) }
                .addOnFailureListener { result.error("ocr_failed", it.message, null) }
        } catch (e: Exception) {
            result.error("ocr_failed", e.message, null)
        }
    }

    private fun extractPdfText(
        path: String,
        maxPages: Int,
        maxChars: Int,
        result: MethodChannel.Result
    ) {
        Thread {
            val source = File(path)
            if (!source.exists()) {
                runOnUiThread { result.success(mapOf("error" to "PDF 文件不存在")) }
                return@Thread
            }

            var descriptor: ParcelFileDescriptor? = null
            var renderer: PdfRenderer? = null
            try {
                val openedDescriptor =
                    ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY)
                descriptor = openedDescriptor
                val openedRenderer = PdfRenderer(openedDescriptor)
                renderer = openedRenderer
                val pages = minOf(openedRenderer.pageCount, maxPages)
                val allText = StringBuilder()
                var index = 0

                fun processNextPage() {
                    if (index >= pages || allText.length >= maxChars) {
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "text" to allText.take(maxChars).toString(),
                                    "pagesProcessed" to index,
                                    "pageCount" to openedRenderer.pageCount
                                )
                            )
                        }
                        try { openedRenderer.close() } catch (_: Exception) {}
                        try { openedDescriptor.close() } catch (_: Exception) {}
                        return
                    }

                    val page = openedRenderer.openPage(index)
                    val scale = 2
                    val bitmap = Bitmap.createBitmap(
                        (page.width * scale).coerceAtLeast(1),
                        (page.height * scale).coerceAtLeast(1),
                        Bitmap.Config.ARGB_8888
                    )
                    bitmap.eraseColor(android.graphics.Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    page.close()
                    val image = InputImage.fromBitmap(bitmap, 0)
                    TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
                        .process(image)
                        .addOnSuccessListener { recognized ->
                            if (recognized.text.isNotBlank()) {
                                allText.append("\n[第 ${index + 1} 页]\n")
                                allText.append(recognized.text)
                                allText.append('\n')
                            }
                            bitmap.recycle()
                            index += 1
                            processNextPage()
                        }
                        .addOnFailureListener { error ->
                            bitmap.recycle()
                            index += 1
                            allText.append("\n[第 $index 页 OCR 失败：${error.message ?: "未知错误"}]\n")
                            processNextPage()
                        }
                }

                if (pages == 0) {
                    runOnUiThread { result.success(mapOf("text" to "", "pagesProcessed" to 0, "pageCount" to 0)) }
                    openedRenderer.close()
                    openedDescriptor.close()
                } else {
                    processNextPage()
                }
            } catch (e: Exception) {
                try { renderer?.close() } catch (_: Exception) {}
                try { descriptor?.close() } catch (_: Exception) {}
                runOnUiThread { result.success(mapOf("error" to (e.message ?: "PDF OCR 失败"))) }
            }
        }.start()
    }

    private fun prepareVideo(path: String, intervalMs: Int): Map<String, Any> {
        val source = File(path)
        require(source.exists()) { "视频文件不存在" }

        val outputDir = File(cacheDir, "tidebot_video_${System.currentTimeMillis()}")
        outputDir.mkdirs()
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L
            val frames = mutableListOf<String>()
            var timeMs = 0L
            while (timeMs <= durationMs && frames.size < 120) {
                val frame: Bitmap? = retriever.getFrameAtTime(
                    timeMs * 1000,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )
                if (frame != null) {
                    val frameFile = File(outputDir, "frame_${frames.size}.jpg")
                    FileOutputStream(frameFile).use {
                        frame.compress(Bitmap.CompressFormat.JPEG, 85, it)
                    }
                    frames.add(frameFile.absolutePath)
                }
                timeMs += intervalMs.coerceAtLeast(1000)
            }
            val audioPath = extractAudio(path, outputDir)
            return mapOf(

                "frames" to frames,
                "audioPath" to (audioPath ?: ""),
                "durationMs" to durationMs
            )
        } finally {
            retriever.release()
        }
    }
    private fun extractAudio(sourcePath: String, outputDir: File): String? {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var output: File? = null
        try {
            extractor.setDataSource(sourcePath)
            var audioTrack = -1
            var audioMime = ""
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrack = index
                    audioMime = mime
                    break
                }
            }
            if (audioTrack < 0) return null

            val webm = audioMime.contains("opus") || audioMime.contains("vorbis")
            output = File(outputDir, if (webm) "audio.webm" else "audio.m4a")
            extractor.selectTrack(audioTrack)
            val destination = output ?: return null
            muxer = MediaMuxer(
                destination.absolutePath,
                if (webm) MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM
                else MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
            )

            val muxerTrack = muxer.addTrack(extractor.getTrackFormat(audioTrack))
            muxer.start()
            val buffer = java.nio.ByteBuffer.allocate(1024 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                info.offset = 0
                info.size = extractor.readSampleData(buffer, 0)
                if (info.size < 0) break
                info.presentationTimeUs = extractor.sampleTime
                info.flags = extractor.sampleFlags
                muxer.writeSampleData(muxerTrack, buffer, info)
                extractor.advance()
            }
            return output?.absolutePath

        } catch (_: Exception) {
            output?.delete()
            return null

        } finally {
            try {
                muxer?.stop()
            } catch (_: Exception) {
            }
            muxer?.release()
            extractor.release()
        }
    }
}
