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
    ];
    final result = <String, String>{};
    for (final key in keys) {
      result[key] = await db.getKV(key) ?? '';
    }
    result['persistent_service_is_running'] =
        (await FlutterBackgroundService().isRunning()).toString();
    return result;
  }
}
