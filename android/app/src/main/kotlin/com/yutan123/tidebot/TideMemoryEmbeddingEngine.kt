package com.yutan123.tidebot

import android.content.Context
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.security.MessageDigest
import kotlin.math.sqrt

/** Bundled model extraction and CPU inference use one serialized worker. */
internal object TideMemoryEmbeddingEngine {
    private const val REV = "75c43b069aac4d136ba6bc1122f995fedcfd2781"
    private var session: OrtSession? = null
    private var vocab: Map<String, Int>? = null
    private val files = listOf(
        Triple("onnx/model_int8.onnx", 23903394L, "b9837c19ce154ff0726d398ee77abbc03a7faf0476c6f93016c84e531be7ebb5"),
        Triple("vocab.txt", 109540L, "45bbac6b341c319adc98a532532882e91a9cefc0329aa57bac9ae761c27b291c")
    )
    // Called only by the dedicated inference service, never by a Flutter engine.
    @Synchronized
    fun vectors(context: Context, texts: List<String>): List<List<Double>> {
        require(texts.size in 1..8) { "Embedding batch too large" }
        val dir = File(context.filesDir, "memory_embedding/$REV").apply { mkdirs() }
        installBundled(context, dir)
        load(dir)
        return texts.map { embed(it) }
    }

    @Synchronized
    fun close() {
        session?.close()
        session = null
        vocab = null
    }

    private fun installBundled(context: Context, dir: File) {
        if (session != null) return
        for ((remote, size, hash) in files) {
            val name = remote.substringAfterLast('/')
            val target = File(dir, name)
            if (valid(target, size, hash)) continue
            val part = File(dir, "$name.part")
            try {
                context.assets.open("memory_embedding/$name").use { input ->
                    part.outputStream().use { output -> input.copyTo(output, 65536) }
                }
                check(valid(part, size, hash)) { "Bundled embedding model failed verification" }
                check(part.renameTo(target)) { "Cannot install bundled embedding model" }
            } finally {
                part.delete()
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
            check(valid(File(dir, remote.substringAfterLast('/')), size, hash)) { "内置向量模型校验失败" }
        }
        val words = File(dir, "vocab.txt").readLines(Charsets.UTF_8)
        check(words.size == 21128) { "分词词表不匹配" }
        vocab = words.withIndex().associate { it.value to it.index }
        OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(1)
            options.setInterOpNumThreads(1)
            options.setCPUArenaAllocator(false)
            options.setMemoryPatternOptimization(false)
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
                // Read only CLS instead of materializing every token as Java arrays.
                val tensor = output[0] as OnnxTensor
                val shape = tensor.info.shape
                check(shape.size == 3 && shape[0] == 1L && shape[2] == 512L) { "向量维度不匹配" }
                val cls = FloatArray(512)
                checkNotNull(tensor.floatBuffer) { "模型输出类型不匹配" }.get(cls)
                val norm = sqrt(cls.fold(0.0) { acc, x -> acc + x.toDouble() * x })
                check(norm > 0 && norm.isFinite()) { "模型返回无效向量" }
                return cls.map { it / norm }
            }
        } finally { tensors.values.forEach { it.close() } }
    }
}
