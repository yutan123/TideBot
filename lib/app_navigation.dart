import 'dart:convert';

import 'package:flutter/material.dart';

import 'db.dart';
import 'ui_chat_room.dart';

/// Root navigation used by notification callbacks that do not have a page context.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> openChatFromNotificationPayload(String? payload) async {
  final raw = payload?.trim() ?? '';
  if (raw.isEmpty) return;
  var botId = raw;
  String? messageId;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      botId = decoded['bot_id']?.toString() ?? '';
      messageId = decoded['message_id']?.toString();
    }
  } catch (_) {
    // Legacy notifications stored the bot id directly.
  }
  if (botId.isEmpty) return;

  final bot = await DBManager().getBotById(botId);
  final navigator = appNavigatorKey.currentState;
  if (bot == null || navigator == null) return;

  await navigator.push(MaterialPageRoute(
    builder: (_) => ChatRoomPage(
      botData: bot,
      initialMessageId: messageId,
    ),
  ));
}
