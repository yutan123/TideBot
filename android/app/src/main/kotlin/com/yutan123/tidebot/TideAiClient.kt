package com.yutan123.tidebot

import android.util.Log
import kotlinx.coroutines.*
import kotlin.coroutines.resume

import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * AI 客户端，使用 OkHttp 发送请求。
 * 支持流式/非流式响应、超时控制、重试机制。
 * 总超时 5 分钟（整个任务），不是每次重试 5 分钟。
 */
object TideAiClient {
    private const val TAG = "TideAiClient"
    private const val TOTAL_TIMEOUT_MS = 5 * 60 * 1000L // 5 分钟
    private const val CONNECT_TIMEOUT_SEC = 30L
    private const val READ_TIMEOUT_SEC = 90L
    private const val MAX_RETRIES = 2

    data class AiRequest(
        val baseUrl: String,
        val apiKey: String,
        val model: String,
        val messages: List<Message>,
        val maxTokens: Int = 2000,
        val stream: Boolean = true,
        val allowSilence: Boolean = false
    )

    data class Message(
        val role: String,
        val content: String,
        val sentAt: Long = System.currentTimeMillis()
    )

    data class AiResponse(
        val content: String,
        val finishReason: String?,
        val usage: Usage?,
        val silent: Boolean = false
    )

    data class Usage(
        val promptTokens: Int,
        val completionTokens: Int,
        val totalTokens: Int
    )

    private val client = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_SEC, TimeUnit.SECONDS)
        .readTimeout(READ_TIMEOUT_SEC, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    /**
     * 发送 AI 请求，支持重试。
     * 整个任务的总超时是 5 分钟，不是每次重试 5 分钟。
     */
    suspend fun sendRequest(request: AiRequest): Result<AiResponse> = withContext(Dispatchers.IO) {
        try {
            withTimeout(TOTAL_TIMEOUT_MS) {
                var lastError: Throwable = IOException("Request failed")
                for (attempt in 0..MAX_RETRIES) {
                    ensureActive()
                    val result = doRequest(request)
                    if (result.isSuccess) return@withTimeout result
                    lastError = result.exceptionOrNull() ?: lastError
                    if (lastError is HttpException && !lastError.retryable) break
                    if (attempt < MAX_RETRIES) delay(1000L shl attempt)
                }
                Result.failure<AiResponse>(lastError)
            }
        } catch (e: TimeoutCancellationException) {
            currentCoroutineContext().ensureActive()
            Result.failure(TimeoutException("任务总超时 5 分钟已达到"))
        }
    }

    /**
     * 执行单次请求
     */
    private suspend fun doRequest(req: AiRequest): Result<AiResponse> {
        val body = buildRequestBody(req)

        // 规范化 URL：移除尾部 /v1，然后统一添加 /v1/chat/completions
        val root = req.baseUrl.trim().trimEnd('/')
        val url = when {
            root.endsWith("/chat/completions") -> root
            root.endsWith("/v1") -> "$root/chat/completions"
            else -> "$root/v1/chat/completions"
        }

        val httpRequest = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer ${req.apiKey}")
            .addHeader("Content-Type", "application/json")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        return suspendCancellableCoroutine { continuation ->
            val call = client.newCall(httpRequest)
            continuation.invokeOnCancellation { call.cancel() }

            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resume(Result.failure(e))
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = try {
                        response.use {
                            if (!it.isSuccessful) Result.failure(HttpException(it.code))
                            else Result.success(
                                if (it.header("Content-Type").orEmpty().contains("text/event-stream", ignoreCase = true)) {
                                    parseStream(it)
                                } else parseChoice(JSONObject(it.body?.string() ?: throw IOException("Empty response")))
                            )
                        }
                    } catch (e: Exception) {
                        Result.failure<AiResponse>(e)
                    }
                    continuation.resume(result)
                }
            })
        }
    }

    /**
     * 构建请求体
     */
    private fun buildRequestBody(req: AiRequest): String {
        val json = JSONObject()
        json.put("model", req.model)
        json.put("max_tokens", req.maxTokens)
        json.put("stream", req.stream)

        val messages = JSONArray()
        req.messages.forEach { msg ->
            val msgObj = JSONObject()
            msgObj.put("role", msg.role)
            val time = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date(msg.sentAt))
            msgObj.put("content", if (msg.role == "user" || msg.role == "assistant") "[发送时间:$time]\n${msg.content}" else msg.content)
            messages.put(msgObj)
        }
        json.put("messages", messages)
        if (req.allowSilence) json.put("tools", JSONArray().put(JSONObject().put("type", "function")
            .put("function", JSONObject().put("name", "choose_silence").put("description", "不适合打扰时保持沉默")
                .put("parameters", JSONObject().put("type", "object").put("properties", JSONObject())))))

        return json.toString()
    }

    /**
     * 解析响应
     */
    private fun parseStream(response: Response): AiResponse {
        val source = response.body?.source() ?: throw IOException("Empty response")
        val content = StringBuilder()
        val names = mutableMapOf<Int, StringBuilder>()
        var finish: String? = null
        var usage: Usage? = null
        val data = StringBuilder()
        fun consume() {
            val text = data.toString().trim()
            data.setLength(0)
            if (text.isEmpty() || text == "[DONE]") return
            val json = JSONObject(text)
            if (json.has("error")) throw IOException("Provider stream error")
            json.optJSONObject("usage")?.let { usage = Usage(it.optInt("prompt_tokens"), it.optInt("completion_tokens"), it.optInt("total_tokens")) }
            val choice = json.optJSONArray("choices")?.optJSONObject(0) ?: return
            if (!choice.isNull("finish_reason")) finish = choice.optString("finish_reason")
            val delta = choice.optJSONObject("delta") ?: choice.optJSONObject("message") ?: return
            if (!delta.isNull("content")) content.append(delta.optString("content"))
            val tools = delta.optJSONArray("tool_calls") ?: JSONArray()
            for (i in 0 until tools.length()) {
                val tool = tools.getJSONObject(i)
                names.getOrPut(tool.optInt("index", i)) { StringBuilder() }
                    .append(tool.optJSONObject("function")?.optString("name").orEmpty())
            }
        }
        var done = false
        while (!done && !source.exhausted()) {
            val line = source.readUtf8Line() ?: break
            if (line.isEmpty()) {
                done = data.toString().trim() == "[DONE]"
                consume()
            }
            else if (line.startsWith("data:")) {
                if (data.isNotEmpty()) data.append('\n')
                data.append(line.substring(5).trimStart())
            }
        }
        consume()
        if (finish == null) throw IOException("Truncated stream")
        if (names.values.any { it.toString() != "choose_silence" }) throw IOException("Unsupported tool")
        val silent = names.values.any { it.toString() == "choose_silence" }
        val visible = stripMetadata(content.toString())
        if (!silent && visible.isBlank()) throw IOException("Empty reply")
        return AiResponse(if (silent) "" else visible, finish, usage, silent)
    }

    /**
     * 解析单个 choice
     */
    private fun parseChoice(json: JSONObject): AiResponse {
        val choices = json.optJSONArray("choices")
            ?: throw IOException("No choices in response")

        if (choices.length() == 0) {
            throw IOException("Empty choices array")
        }

        val choice = choices.getJSONObject(0)
        val message = choice.optJSONObject("message")
            ?: choice.optJSONObject("delta")
            ?: throw IOException("No message/delta in choice")

        val tools = message.optJSONArray("tool_calls") ?: JSONArray()
        var silent = false
        for (i in 0 until tools.length()) {
            if (tools.getJSONObject(i).optJSONObject("function")?.optString("name") != "choose_silence") throw IOException("Unsupported tool")
            silent = true
        }
        val content = if (silent || message.isNull("content")) "" else stripMetadata(message.optString("content", ""))
        if (!silent && content.isBlank()) throw IOException("Empty reply")
        val finishReason = choice.optString("finish_reason")

        val usage = json.optJSONObject("usage")?.let {
            Usage(
                promptTokens = it.optInt("prompt_tokens", 0),
                completionTokens = it.optInt("completion_tokens", 0),
                totalTokens = it.optInt("total_tokens", 0)
            )
        }

        return AiResponse(content, finishReason, usage, silent)
    }

    private fun stripMetadata(text: String): String = text.replace(
        Regex("""\[(?:(?:你|对方)发送了一个表情包，表情包类型|发送时间)\s*[:：][^\]]*(?:\]|$)"""), "").trim()

    private class HttpException(code: Int) : IOException("Provider HTTP $code") {
        val retryable = code == 408 || code == 429 || code >= 500
    }

    class TimeoutException(message: String) : IOException(message)
}