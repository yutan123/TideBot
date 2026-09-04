import 'package:flutter_background_service/flutter_background_service.dart';

import 'db.dart';

class PersistentServiceCoordinator {
  PersistentServiceCoordinator._();

  static final instance = PersistentServiceCoordinator._();
  static const _intentKey = 'persistent_notification';

  Future<void> setEnabled(bool enabled) async {
    final db = DBManager();
    await db.setKV(_intentKey, enabled ? 'true' : 'false');
    if (!enabled) {
      FlutterBackgroundService().invoke('stopService');
      await db.setKV('persistent_service_state', 'stopped_by_user');
      await db.setKV('persistent_service_heartbeat', '');
      return;
    }
    await ensureRunning();
  }

  Future<bool> ensureRunning() async {
    final db = DBManager();
    if (await db.getKV(_intentKey) != 'true') return false;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) await service.startService();
    await db.setKV('persistent_service_state', 'starting');
    await db.setKV(
      'persistent_service_start_requested_at',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    return await service.isRunning();
  }

  Future<Map<String, String>> diagnostics() async {
    final db = DBManager();
    const keys = [
      _intentKey,
      'persistent_service_state',
      'persistent_service_started_at',
      'persistent_service_heartbeat',
      'persistent_service_last_tick_started_at',
      'persistent_service_last_tick_finished_at',
      'persistent_service_last_error',
      'persistent_service_restart_count',
      'persistent_service_task_proactive_replies_success_at',
      'persistent_service_task_proactive_replies_duration_ms',
      'proactive_last_run_at',
      'proactive_last_result',
    ];
    final result = <String, String>{};
    for (final key in keys) {
      result[key] = await db.getKV(key) ?? '';
    }
    for (final bot in await db.getAllBots()) {
      final id = bot['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      for (final suffix in const [
        'proactive_due_at_',
        'proactive_last_result_',
        'proactive_unanswered_',
      ]) {
        result['$suffix$id'] = await db.getKV('$suffix$id') ?? '';
      }
    }
    result['persistent_service_is_running'] =
        (await FlutterBackgroundService().isRunning()).toString();
    return result;
  }
}
