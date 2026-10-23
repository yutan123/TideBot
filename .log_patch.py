from pathlib import Path
import re
root=Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot')
k=root/'android/app/src/main/kotlin/com/yutan123/tidebot'
p=k/'TideTaskExecutor.kt'; s=p.read_text()
s=re.sub(r'^\s*TideBackgroundLog.add\(context, "任务(?:开始|结束)：[^\n]*\n','\n',s,flags=re.M)
s=s.replace('        TideBackgroundLog.add(context, "主动回复请求开始：bot=$botId，model=${model.model}")','''        val requestStarted = android.os.SystemClock.elapsedRealtime()
        val lateMs = (System.currentTimeMillis() - taskConfig.optLong("scheduled_time", System.currentTimeMillis())).coerceAtLeast(0)
        val detail = if (TideBackgroundLog.enabled(context)) {
            "\\n发往模型提供商的完整请求（已脱敏）：\\n" + JSONObject(TideAiClient.buildRequestBody(request)).toString(2)
        } else ""
        TideBackgroundLog.add(context, "主动回复到期请求：bot=$botId，execution=$executionId，model=${model.model}，延迟=${lateMs}ms$detail", "PROACTIVE_REQUEST")''')
s=re.sub(r'^\s*TideBackgroundLog.add\(context, "主动回复请求结束：[^\n]*\n','\n',s,flags=re.M)
s=s.replace('''TideBackgroundLog.add(context, "主动回复结果：bot=$botId，${if (sent) "sent" else if (response != null) "model_silence" else "request_failed"}")''','''TideBackgroundLog.add(context, "主动回复结束：bot=$botId，execution=$executionId，结果=${if (sent) "sent" else if (response != null) "model_silence" else "request_failed"}，耗时=${android.os.SystemClock.elapsedRealtime() - requestStarted}ms" +
                    (if (TideBackgroundLog.enabled(context)) "\\n响应：${response?.content.orEmpty()}\\n错误：${result.exceptionOrNull()?.message.orEmpty()}" else ""),
                    if (result.isFailure) "PROACTIVE_ERROR" else "PROACTIVE_NATIVE")''')
s=s.replace('''                config.put("bot_id", it.getString(1))''','''                config.put("bot_id", it.getString(1))''')
# Deadline comes from the claimed delivery, not a fresh query that could have been rescheduled.
s=s.replace('''"PROACTIVE_REPLY" -> executeProactiveReply(context, taskConfig, executionId)''','''"PROACTIVE_REPLY" -> executeProactiveReply(context, taskConfig.put("scheduled_time", scheduledTime), executionId)''')
p.write_text(s)
p=k/'TideAiClient.kt'; s=p.read_text().replace('private fun buildRequestBody(req: AiRequest): String','internal fun buildRequestBody(req: AiRequest): String'); p.write_text(s)
p=k/'TideProactiveTasks.kt'; s=p.read_text(); s=re.sub(r'^\s*TideBackgroundLog.add\(context, "主动回复(?:暂停|已安排)：[^\n]*\n','\n',s,flags=re.M); p.write_text(s)
p=root/'lib/main.dart'; s=p.read_text(); s=re.sub(r'^\s*AppLogService.instance.add\(\x27PROACTIVE\x27, \x27跳过设备事件触发：[^\n]*\n','\n',s,flags=re.M); p.write_text(s)
p=root/'lib/app_log_service.dart'; s=p.read_text().replace('void add(String level, String message) {','void add(String level, String message, {DateTime? time}) {').replace('AppLogEntry(DateTime.now(), level, _redact(message))','AppLogEntry(time ?? DateTime.now(), level, _redact(message))'); p.write_text(s)
p=root/'lib/native_background_coordinator.dart'; s=p.read_text()
a=s.index('        final at = DateTime.fromMillisecondsSinceEpoch'); b=s.index('\n      }',a)
s=s[:a]+'''        final message = row['message']?.toString() ?? '';
        // Discard old-version polling entries still waiting in the native queue.
        if (message.startsWith('任务开始：') ||
            message.startsWith('任务结束：') ||
            message.startsWith('主动回复已安排：') ||
            message.startsWith('主动回复暂停：')) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(row['time'] as int);
        AppLogService.instance.add(
          row['level']?.toString() ?? 'PROACTIVE_NATIVE', message, time: at);
'''.rstrip()+s[b:]; p.write_text(s)
