import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ai.dart';
import 'app_log_service.dart';

/// Android retains ownership of the execution lease and the final transaction.
/// Use the ordinary chat pipeline to assemble context, run tools and split text.
void startProactiveReplyEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot/proactive_reply');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'generate') throw MissingPluginException();
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    await AppLogService.instance.restoreFromPreferences();
    final response = await AIManager().sendMessage(
      botId: args['botId'] as String,
      text: '【主动联系时机】主动联系时间已到，请结合当前上下文判断是否适合联系。',
      task: AIRequestTask.proactiveChat,
      persistResponse: false,
    );
    return {
      ...response,
      if (AppLogService.instance.enabled)
        'request_logs':
            AppLogService.instance.entries.map((e) => e.toJson()).toList(),
    };
  });
  channel.invokeMethod<void>('ready');
}
