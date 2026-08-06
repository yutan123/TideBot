package com.yutan123.tidebot
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
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
                "executeAccessibilityAction" -> {
                    result.success("Action Received")
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
