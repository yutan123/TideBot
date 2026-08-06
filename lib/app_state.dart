import 'package:flutter/widgets.dart';

/// 仅表示 TideBot 当前是否处于可见的前台状态。
/// 后台回复通知读取此值，避免用户正在聊天时收到重复系统通知。
class AppState {
  static final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);

  static void updateLifecycle(AppLifecycleState state) {
    isForeground.value = state == AppLifecycleState.resumed;
  }
}
