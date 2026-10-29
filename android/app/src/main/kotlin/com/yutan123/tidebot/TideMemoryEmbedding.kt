package com.yutan123.tidebot

import android.content.Context
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

/** All downloads and CPU inference run on their own serialized worker. No text leaves the device. */
object TideMemoryEmbedding {
    private const val REV = "75c43b069aac4d136ba6bc1122f995fedcfd2781"
    private const val BASE = "https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/$REV/"
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder().connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS).callTimeout(8, TimeUnit.MINUTES).build()
    @Volatile private var installing = false
    private var session: OrtSession? = null
    private var vocab: Map<String, Int>? = null
    private val files = listOf(
        Triple("onnx/model_int8.onnx", 23903394L, "b9837c19ce154ff0726d398ee77abbc03a7faf0476c6f93016c84e531be7ebb5"),
        Triple("vocab.txt", 109540L, "45bbac6b341c319adc98a532532882e91a9cefc0329aa57bac9ae761c27b291c")
    )
    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "tidebot.memory.embedding").setMethodCallHandler { call, result ->
            if (call.method == "status" && installing) {
                result.success(false)
                return@setMethodCallHandler
            }
            if (call.method == "download") installing = true
            worker.execute {
                try {
                    val dir = File(app.filesDir, "memory_embedding/$REV").apply { mkdirs() }
                    val value: Any? = when (call.method) {
                        "status" -> runCatching { load(dir); true }.getOrDefault(false)
                        "download" -> {
                            for ((remote, size, hash) in files) {
                                val target = File(dir, remote.substringAfterLast('/'))
                                if (!valid(target, size, hash)) {
                                    val part = File(dir, target.name + ".part")
                                    try {
                                        client.newCall(Request.Builder().url(BASE + remote).build()).execute().use { response ->
                                            check(response.isSuccessful) { "模型下载 HTTP ${response.code}" }
                                            val body = checkNotNull(response.body)
                                            body.byteStream().use { input -> part.outputStream().use { output ->
                                                val buffer = ByteArray(65536)
                                                var total = 0L
                                                while (true) {
                                                    val n = input.read(buffer)
                                                    if (n < 0) break
                                                    total += n
                                                    check(total <= size) { "模型文件大小异常" }
                                                    output.write(buffer, 0, n)
                                                }
                                            } }
                                        }
                                        check(valid(part, size, hash)) { "模型校验失败，请重新下载" }
                                        check(part.renameTo(target)) { "模型保存失败" }
                                    } finally { part.delete() }
                                }
                            }
                            // Initialize now so a broken model cannot be shown as ready.
                            load(dir)
                            true
                        }
                        "embed" -> {
                            load(dir)
                            val texts = call.argument<List<String>>("texts").orEmpty()
                            require(texts.size <= 16) { "Embedding batch too large" }
                            texts.map { embed(it) }
                        }
                        else -> throw IllegalArgumentException("Unknown embedding method")
                    }
                    main.post { result.success(value) }
                } catch (error: Exception) {
                    main.post { result.error("MEMORY_EMBEDDING", error.message, null) }
                } finally {
                    if (call.method == "download") installing = false
                }
            }
        }
    }
    private fun valid(file: File, size: Long, hash: String): Boolean {
        if (!file.isFile || file.length() != size) return false
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) } == hash
    }
    private fun load(dir: File) {
        if (session != null) return
        for ((remote, size, hash) in files) {
            check(valid(File(dir, remote.substringAfterLast('/')), size, hash)) { "本地向量模型未下载或校验失败" }
        }
        val words = File(dir, "vocab.txt").readLines(Charsets.UTF_8)
        check(words.size == 21128) { "分词词表不匹配" }
        vocab = words.withIndex().associate { it.value to it.index }
        OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            session = OrtEnvironment.getEnvironment().createSession(File(dir, "model_int8.onnx").absolutePath, options)
        }
    }
    private fun chinese(cp: Int): Boolean = cp in 0x4E00..0x9FFF || cp in 0x3400..0x4DBF ||
        cp in 0x20000..0x2A6DF || cp in 0x2A700..0x2B73F || cp in 0x2B740..0x2B81F ||
        cp in 0x2B820..0x2CEAF || cp in 0x2F800..0x2FA1F || cp in 0xF900..0xFAFF
    private fun punctuation(cp: Int): Boolean {
        val kind = Character.getType(cp)
        return cp in 33..47 || cp in 58..64 || cp in 91..96 || cp in 123..126 ||
            kind in listOf(Character.CONNECTOR_PUNCTUATION.toInt(), Character.DASH_PUNCTUATION.toInt(),
                Character.START_PUNCTUATION.toInt(), Character.END_PUNCTUATION.toInt(),
                Character.INITIAL_QUOTE_PUNCTUATION.toInt(), Character.FINAL_QUOTE_PUNCTUATION.toInt(),
                Character.OTHER_PUNCTUATION.toInt())
    }
    // BertTokenizer: case is preserved, accents are preserved, Chinese characters and punctuation split.
    private fun tokenize(text: String): LongArray {
        val v = checkNotNull(vocab)
        val basic = mutableListOf<String>()
        val word = StringBuilder()
        fun flush() { if (word.isNotEmpty()) { basic.add(word.toString()); word.setLength(0) } }
        val specialTokens = listOf("[CLS]", "[SEP]", "[PAD]", "[UNK]", "[MASK]")
        var offset = 0
        var processed = 0
        while (offset < text.length && processed++ < 20000) {
            val special = specialTokens.firstOrNull { text.startsWith(it, offset) }
            if (special != null) {
                flush(); basic.add(special); offset += special.length
                continue
            }
            val cp = text.codePointAt(offset)
            offset += Character.charCount(cp)
            val type = Character.getType(cp)
            when {
                cp == 32 || cp == 9 || cp == 10 || cp == 13 || type == Character.SPACE_SEPARATOR.toInt() -> flush()
                cp == 0 || cp == 0xFFFD || type in listOf(Character.CONTROL.toInt(), Character.FORMAT.toInt(),
                    Character.PRIVATE_USE.toInt(), Character.SURROGATE.toInt(), Character.UNASSIGNED.toInt()) -> Unit
                chinese(cp) || punctuation(cp) -> { flush(); basic.add(String(Character.toChars(cp))) }
                else -> word.appendCodePoint(cp)
            }
        }
        flush()
        val ids = mutableListOf(v.getValue("[CLS]").toLong())
        for (token in basic) {
            if (ids.size >= 511) break
            val pieces = mutableListOf<Int>()
            var start = 0
            if (token.codePointCount(0, token.length) > 100) pieces.add(v.getValue("[UNK]"))
            else while (start < token.length) {
                var end = token.length
                var found: Int? = null
                while (end > start) {
                    found = v[(if (start > 0) "##" else "") + token.substring(start, end)]
                    if (found != null) break
                    end = token.offsetByCodePoints(end, -1)
                }
                if (found == null) { pieces.clear(); pieces.add(v.getValue("[UNK]")); break }
                pieces.add(found)
                start = end
            }
            for (id in pieces) { if (ids.size >= 511) break; ids.add(id.toLong()) }
        }
        ids.add(v.getValue("[SEP]").toLong())
        return ids.toLongArray()
    }
    private fun embed(text: String): List<Double> {
        val ids = tokenize(text)
        val env = OrtEnvironment.getEnvironment()
        val tensors = mutableMapOf<String, OnnxTensor>()
        try {
            tensors["input_ids"] = OnnxTensor.createTensor(env, arrayOf(ids))
            tensors["attention_mask"] = OnnxTensor.createTensor(env, arrayOf(LongArray(ids.size) { 1L }))
            if (checkNotNull(session).inputNames.contains("token_type_ids")) {
                tensors["token_type_ids"] = OnnxTensor.createTensor(env, arrayOf(LongArray(ids.size)))
            }
            checkNotNull(session).run(tensors).use { output ->
                // BGE sentence embedding uses the first (CLS) token, followed by L2 normalization.
                @Suppress("UNCHECKED_CAST")
                val hidden = output[0].value as Array<Array<FloatArray>>
                val cls = hidden[0][0]
                check(cls.size == 512) { "向量维度不匹配" }
                val norm = sqrt(cls.fold(0.0) { acc, x -> acc + x.toDouble() * x })
                check(norm > 0 && norm.isFinite()) { "模型返回无效向量" }
                return cls.map { it / norm }
            }
        } finally { tensors.values.forEach { it.close() } }
    }
}
