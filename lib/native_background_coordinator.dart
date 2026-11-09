import 'dart:async';
import 'dart:convert';
import 'app_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'chat_event_bus.dart';
import 'db.dart';
import 'global_notice.dart';
import 'app_navigation.dart';
import 'voice_call_state_service.dart';
import 'media_storage_service.dart';

class NativeBackgroundCoordinator {
  NativeBackgroundCoordinator._();
  static const _channel = MethodChannel('tidebot.native.channel');
  static bool _started = false;
  static bool _refreshing = false;
  static Future<void>? _synchronizing;
  static bool _synchronizeAgain = false;
  static AppLifecycleListener? _lifecycleListener;

  static Future<void> interruptProactiveReply(String botId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel
          .invokeMethod<void>('interruptProactiveReply', {'botId': botId});
    } on MissingPluginException {
      // Headless engines and workers still enforce the persisted generation.
    } on PlatformException catch (error) {
      AppLogService.instance
          .add('PROACTIVE_GATE', '主动回复取消通知失败，使用持久化版本拦截：${error.code}');
    }
  }

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
      try {
        if (appNavigatorKey.currentState != null) {
          final restored =
              await _channel.invokeMethod<String>('consumeRestoreResult');
          if (restored != null) GlobalNotice.show(restored);
          final payload = await _channel
              .invokeMapMethod<String, dynamic>('consumeMessageNotification');
          if (payload != null)
            unawaited(openChatFromNotificationPayload(jsonEncode(payload)));
        }
      } on MissingPluginException {
        // The coordinator also runs in engines without an Activity.
      } on PlatformException catch (error) {
        debugPrint('Native notification/restore result: $error');
      }
      await refreshLogs();
      final db = await DBManager().database;
      final events = await db.query('foreground_message_events', limit: 100);
      for (final event in events) {
        final id = event['message_id']?.toString() ?? '';
        final message = await DBManager().getMessageById(id);
        if (message != null) {
          ChatEventBus.instance.publish(ChatEvent(
              type: ChatEventType.inserted,
              botId: message['bot_id']?.toString(),
              messageId: id,
              message: message));
        }
        await db.delete('foreground_message_events',
            where: 'message_id = ?', whereArgs: [id]);
      }
      await VoiceCallStateService.instance.synchronize();
      MediaStorageService.instance.kick();
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
        if (message == null) {
          await db.delete('background_messages',
              where: 'message_id = ?', whereArgs: [id]);
          continue;
        }
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
