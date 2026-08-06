import 'package:flutter/material.dart';

import 'db.dart';
import 'ui_chat_room.dart';

/// Root navigation used by notification callbacks that do not have a page context.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> openChatFromNotificationPayload(String? payload) async {
  final botId = payload?.trim() ?? '';
  if (botId.isEmpty) return;

  final bot = await DBManager().getBotById(botId);
  final navigator = appNavigatorKey.currentState;
  if (bot == null || navigator == null) return;

  await navigator.push(MaterialPageRoute(
    builder: (_) => ChatRoomPage(botData: bot),
  ));
}
