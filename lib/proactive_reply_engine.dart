import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ai.dart';
import 'db.dart';
import 'proactive_request_gate.dart';
import 'app_log_service.dart';

/// Android retains ownership of the execution lease and the final transaction.
/// Use the ordinary chat pipeline to assemble context, run tools and split text.
void startProactiveReplyEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tidebot/proactive_reply');
  AICancellationToken? activeToken;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'cancel') {
      activeToken?.cancel();
      return null;
    }
    if (call.method != 'generate') throw MissingPluginException();
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    final botId = args['botId'] as String;
    final generation = args['generation'] as String;
    final due = args['due'] as String?;
    final db = await DBManager().database;
    final token = AICancellationToken(beforeRequest: () async {
      final allowed = await db.transaction(
          (txn) => ProactiveRequestGate.allowed(txn, botId, generation, due));
      if (!allowed) activeToken?.cancel();
    });
    activeToken = token;
    try {
      await token.checkRequestAllowed();
      await AppLogService.instance.restoreFromPreferences();
      final response = await AIManager().sendMessage(
        botId: botId,
        cancellationToken: token,
        text: '【主动联系时机】主动联系时间已到，请结合当前上下文判断是否适合联系。',
        task: AIRequestTask.proactiveChat,
        persistResponse: false,
      );
      await token.checkRequestAllowed();
      return {
        ...response,
        if (AppLogService.instance.enabled)
          'request_logs':
              AppLogService.instance.entries.map((e) => e.toJson()).toList(),
      };
    } finally {
      activeToken = null;
    }
  });
  channel.invokeMethod<void>('ready');
}
