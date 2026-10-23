import 'dart:async';
import 'dart:convert';
import 'app_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'chat_event_bus.dart';
import 'db.dart';

class NativeBackgroundCoordinator {
  NativeBackgroundCoordinator._();
  static const _channel = MethodChannel('tidebot.native.channel');
  static bool _started = false;
  static bool _refreshing = false;
  static Future<void>? _synchronizing;
  static bool _synchronizeAgain = false;
  static AppLifecycleListener? _lifecycleListener;

  static Future<void> synchronize() {
    if (defaultTargetPlatform != TargetPlatform.android) return Future.value();
    _synchronizeAgain = true;
    return _synchronizing ??= Future<void>.microtask(_drainSynchronization);
  }

  static Future<void> _drainSynchronization() async {
    try {
      do {
        _synchronizeAgain = false;
        await _synchronize();
      } while (_synchronizeAgain);
    } finally {
      _synchronizing = null;
    }
  }

  static Future<void> _synchronize() async {
    try {
      await _channel.invokeMethod<void>('synchronizeBackgroundTasks');
    } on MissingPluginException {
      // Worker reads committed SQLite changes even when this engine has no channel.
    } on PlatformException catch (error) {
      debugPrint('Native background synchronization failed: ${error.code}');
    }
  }

  static void start() {
    if (_started || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    _lifecycleListener ??= AppLifecycleListener(onResume: () {
      unawaited(synchronize());
      unawaited(refreshMessages());
    });
    unawaited(synchronize());
    unawaited(refreshMessages());
    Timer.periodic(const Duration(minutes: 1), (_) => unawaited(synchronize()));
    Timer.periodic(
        const Duration(seconds: 2), (_) => unawaited(refreshMessages()));
  }

  static Future<void> refreshLogs() async {
    if (!AppLogService.instance.enabled) return;
    try {
      final raw = await _channel.invokeMethod<String>('drainBackgroundLogs');
      for (final row in (jsonDecode(raw ?? '[]') as List).whereType<Map>()) {
        final message = row['message']?.toString() ?? '';
        // Discard old-version polling entries still waiting in the native queue.
        if (message.startsWith('任务开始：') ||
            message.startsWith('任务结束：') ||
            message.startsWith('主动回复已安排：') ||
            message.startsWith('主动回复暂停：')) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(row['time'] as int);
        AppLogService.instance.add(
            row['level']?.toString() ?? 'PROACTIVE_NATIVE', message,
            time: at);
      }
    } catch (error) {
      AppLogService.instance.add('ERROR', '原生后台日志读取失败：$error');
    }
  }

  static Future<void> refreshMessages() async {
    if (_refreshing ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _refreshing = true;
    try {
      await refreshLogs();
      final db = await DBManager().database;
      final rows = await db.query('background_messages',
          where: 'synced_to_chat = 1 AND displayed = 0',
          orderBy: 'timestamp',
          limit: 100);
      // Deliver before acknowledging this batch. Foreground polling can otherwise
      // consume messages before the native task reaches its notification step.
      if (rows.isNotEmpty) {
        await _channel.invokeMethod<void>('deliverPendingMessages');
      }
      for (final row in rows) {
        final id = row['message_id']?.toString() ?? '';
        final message = await DBManager().getMessageById(id);
        if (message == null) continue;
        ChatEventBus.instance.publish(ChatEvent(
            type: ChatEventType.inserted,
            botId: row['bot_id']?.toString(),
            messageId: id,
            message: message));
        await db.update('background_messages', {'displayed': 1},
            where: 'message_id = ?', whereArgs: [id]);
      }
    } catch (error) {
      debugPrint('Native message refresh failed: $error');
    } finally {
      _refreshing = false;
    }
  }
}
