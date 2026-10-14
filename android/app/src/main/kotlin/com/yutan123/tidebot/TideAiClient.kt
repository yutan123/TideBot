package com.yutan123.tidebot

import android.util.Log
import kotlinx.coroutines.*
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
        val stream: Boolean = false
    )

    data class Message(
        val role: String,
        val content: String
    )

    data class AiResponse(
        val content: String,
        val finishReason: String?,
        val usage: Usage?
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
        val startTime = System.currentTimeMillis()
        var lastError: Exception? = null

        for (attempt in 1..MAX_RETRIES + 1) {
            val elapsedTime = System.currentTimeMillis() - startTime
            if (elapsedTime >= TOTAL_TIMEOUT_MS) {
                Log.w(TAG, "Total timeout exceeded: ${elapsedTime}ms")
                return@withContext Result.failure(
                    TimeoutException("任务总超时 5 分钟已达到")
                )
            }

            val remainingTime = TOTAL_TIMEOUT_MS - elapsedTime
            Log.d(TAG, "Attempt $attempt/${MAX_RETRIES + 1}, remaining time: ${remainingTime}ms")

            try {
                return@withContext withTimeout(remainingTime) {
                    doRequest(request)
                }
            } catch (e: Exception) {
                lastError = e
                Log.w(TAG, "Attempt $attempt failed", e)

                if (attempt <= MAX_RETRIES) {
                    val backoffMs = minOf(1000L * (1 shl (attempt - 1)), 10000L)
                    Log.d(TAG, "Retrying after ${backoffMs}ms...")
                    delay(backoffMs)
                } else {
                    Log.e(TAG, "All attempts failed", e)
                }
            }
        }

        Result.failure(lastError ?: IOException("Unknown error"))
    }

    /**
     * 执行单次请求
     */
    private suspend fun doRequest(req: AiRequest): Result<AiResponse> {
        val body = buildRequestBody(req)
        val httpRequest = Request.Builder()
            .url(req.baseUrl.trimEnd('/') + "/v1/chat/completions")
            .addHeader("Authorization", "Bearer ${req.apiKey}")
            .addHeader("Content-Type", "application/json")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        return suspendCancellableCoroutine { continuation ->
            val call = client.newCall(httpRequest)
            continuation.invokeOnCancellation { call.cancel() }

            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWith(Result.failure(e))
                }

                override fun onResponse(call: Call, response: Response) {
                    try {
                        if (!response.isSuccessful) {
                            val error = response.body?.string() ?: "HTTP ${response.code}"
                            continuation.resumeWith(
                                Result.failure(IOException("API error: $error"))
                            )
                            return
                        }

                        val responseBody = response.body?.string()
                            ?: throw IOException("Empty response body")

                        val result = parseResponse(responseBody, req.stream)
                        continuation.resumeWith(Result.success(result))
                    } catch (e: Exception) {
                        continuation.resumeWith(Result.failure(e))
                    } finally {
                        response.close()
                    }
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
            msgObj.put("content", msg.content)
            messages.put(msgObj)
        }
        json.put("messages", messages)

        return json.toString()
    }

    /**
     * 解析响应
     */
    private fun parseResponse(body: String, isStream: Boolean): AiResponse {
        if (isStream) {
            // 流式响应：解析最后一个 data: 块
            val lines = body.lines().filter { it.startsWith("data: ") }
            val lastData = lines.lastOrNull { !it.contains("[DONE]") }
                ?: throw IOException("No valid data in stream")

            val json = JSONObject(lastData.substring(6))
            return parseChoice(json)
        } else {
            // 非流式响应
            val json = JSONObject(body)
            return parseChoice(json)
        }
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

        val content = message.optString("content", "")
        val finishReason = choice.optString("finish_reason")

        val usage = json.optJSONObject("usage")?.let {
            Usage(
                promptTokens = it.optInt("prompt_tokens", 0),
                completionTokens = it.optInt("completion_tokens", 0),
                totalTokens = it.optInt("total_tokens", 0)
            )
        }

        return AiResponse(content, finishReason, usage)
    }

    class TimeoutException(message: String) : IOException(message)
}