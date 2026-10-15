import 'package:flutter/services.dart';

class FutureTaskScheduler {
  FutureTaskScheduler._();

  static const MethodChannel _channel = MethodChannel('tidebot.native.channel');

  static Future<bool> schedule(Map<String, dynamic> task) async {
    final id = task['id']?.toString() ?? '';
    final runAt = _toInt(task['run_at'] ?? task['time']);
    if (id.isEmpty || runAt <= 0) return false;
    try {
      return await _channel.invokeMethod<bool>('scheduleFutureTask', {
            'taskId': id,
            'triggerAt': runAt,
            'title': task['title']?.toString() ?? 'TideBot 提醒',
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // 后台 isolate 的引擎未注册 tidebot.native.channel；
      // SQLite 仍是任务来源，由 WorkManager 周期唤醒兜底执行。
      return false;
    }
  }

  static Future<void> cancel(String taskId) async {
    if (taskId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('cancelFutureTask', {'taskId': taskId});
    } on PlatformException {
      // SQLite remains authoritative when native scheduling is unavailable.
    } on MissingPluginException {
      // 后台 isolate 中无原生通道，同上。
    }
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
}
