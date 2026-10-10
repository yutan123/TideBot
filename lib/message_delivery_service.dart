import 'dart:async';

import 'app_state.dart';
import 'chat_event_bus.dart';
import 'db.dart';
import 'ops.dart';
import 'photo_memory_service.dart';

/// Single entry point for messages that become visible outside the caller.
class MessageDeliveryService {
  MessageDeliveryService._();
  static final MessageDeliveryService instance = MessageDeliveryService._();

  final DBManager _db = DBManager();

  Future<void> insert(
    Map<String, dynamic> message, {
    bool notify = true,
    String? notificationTitle,
  }) async {
    await _db.insertChatMessage(message, publishEvent: false);
    final botId = message['bot_id']?.toString();
    final messageId = message['id']?.toString();
    ChatEventBus.instance.publish(ChatEvent(
      type: ChatEventType.inserted,
      botId: botId,
      messageId: messageId,
      message: Map<String, dynamic>.from(message),
    ));

    // 照片消息自动记录并生成描述
    final role = message['role']?.toString();
    final type = message['type']?.toString();
    final filePath = message['file_path']?.toString();
    if (botId != null &&
        filePath != null &&
        filePath.isNotEmpty &&
        type == 'image' &&
        (role == 'user' || role == 'assistant')) {
      unawaited(PhotoMemoryService.instance.handleChatPhoto(
        botId: botId,
        imagePath: filePath,
        sender: role == 'user' ? 'user' : 'bot',
        messageId: messageId,
        timestamp: (message['timestamp'] as num?)?.toInt(),
      ));
    }

    if (notify &&
        message['role'] == 'assistant' &&
        botId != null &&
        !AppState.isForeground.value &&
        await _db.getKV('unread_notifications') != 'false') {
      await OpsManager().showSystemNotification(
        id: messageId.hashCode,
        title: notificationTitle ?? 'TideBot',
        body: message['content']?.toString().trim().isEmpty == false
            ? message['content'].toString()
            : 'TideBot 有一条新消息',
        botId: botId,
        messageId: messageId,
      );
    }
  }

  Future<void> markRead(String botId) async {
    await _db.markBotRead(botId);
  }
}
