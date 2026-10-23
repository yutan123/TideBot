import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shared visibility policy for message alerts and read receipts.
class AppState {
  static final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);
  static final RouteObserver<ModalRoute<dynamic>> chatRouteObserver =
      RouteObserver<ModalRoute<dynamic>>();
  static const _nativeChannel = MethodChannel('tidebot.native.channel');
  static String? _visibleChatBotId;
  static Object? _visibleChatOwner;

  static bool isViewingChat(String? botId) =>
      isForeground.value &&
      botId != null &&
      botId.isNotEmpty &&
      botId == _visibleChatBotId;

  static void showChat(String botId, Object owner) {
    _visibleChatOwner = owner;
    _visibleChatBotId = botId;
    unawaited(_syncVisibleChat());
  }

  static void hideChat(Object owner) {
    // A popped room must not clear the room revealed underneath it.
    if (!identical(_visibleChatOwner, owner)) return;
    _visibleChatOwner = null;
    _visibleChatBotId = null;
    unawaited(_syncVisibleChat());
  }

  static Future<void> _syncVisibleChat() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _nativeChannel.invokeMethod<void>('setVisibleChat', {
        'botId': _visibleChatBotId,
      });
    } on MissingPluginException {
      // Tests and engines without an Activity have no visible native chat.
    } on PlatformException catch (error) {
      debugPrint('Unable to update native chat visibility: ${error.code}');
    }
  }

  static void updateLifecycle(AppLifecycleState state) {
    isForeground.value = state == AppLifecycleState.resumed;
  }
}
