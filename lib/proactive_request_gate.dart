import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'proactive_request_state.dart';

/// SQLite is shared by foreground Flutter and the native proactive worker.
/// Expiring leases recover after a killed engine; requests release only themselves.
class ProactiveRequestGate {
  static final _random = Random.secure();
  static String _id() =>
      base64UrlEncode(List<int>.generate(24, (_) => _random.nextInt(256)));
  static const leaseMs = 10 * 60 * 1000;
  static String key(String botId) => 'chat_proactive_gate_$botId';

  static Future<ProactiveRequestState> _read(
      DatabaseExecutor db, String botId) async {
    final rows = await db.query('kv_store',
        columns: ['value'], where: 'key = ?', whereArgs: [key(botId)]);
    return ProactiveRequestState.decode(
        rows.isEmpty ? null : rows.first['value'] as String?);
  }

  static Future<void> _put(DatabaseExecutor db, String key, String value) => db
      .insert('kv_store', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  static Future<void> _reschedule(DatabaseExecutor db, String botId) async {
    Future<int> setting(String key, int fallback) async {
      final rows = await db.query('kv_store',
          columns: ['value'], where: 'key = ?', whereArgs: [key]);
      return rows.isEmpty
          ? fallback
          : int.tryParse('${rows.first['value']}') ?? fallback;
    }

    final min = (await setting('proactive_min_minutes', 60)).clamp(1, 1440);
    final max = (await setting('proactive_max_minutes', 90)).clamp(min, 1440);
    final due = DateTime.now().millisecondsSinceEpoch +
        (min + _random.nextInt(max - min + 1)) * 60000;
    await _put(db, 'proactive_due_at_$botId', '$due');
  }

  /// Run in the user-message transaction so no worker can observe new history
  /// without the invalidation of its previous request generation.
  static Future<void> userActivity(DatabaseExecutor db, String botId) async {
    final state = await _read(db, botId);
    state.userActivity(DateTime.now().millisecondsSinceEpoch, _id(), leaseMs);
    await _put(db, key(botId), state.encode());
    await _put(db, 'proactive_unanswered_$botId', '0');
    await _put(db, 'proactive_last_result_$botId', 'user_interrupted');
    await _reschedule(db, botId);
  }

  static Future<bool> allowed(
      DatabaseExecutor db, String botId, String generation, String? due) async {
    final state = await _read(db, botId);
    final rows = await db.query('kv_store',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['proactive_due_at_$botId']);
    return state.allows(DateTime.now().millisecondsSinceEpoch, generation) &&
        (rows.isEmpty ? null : rows.first['value']) == due;
  }

  static Future<ChatRequestActivity> begin(Database db, String botId) async {
    final id = _id();
    final generation = _id();
    await db.transaction((txn) async {
      await userActivity(txn, botId);
      final state = await _read(txn, botId);
      state.begin(
          DateTime.now().millisecondsSinceEpoch, id, generation, leaseMs);
      await _put(txn, key(botId), state.encode());
    });
    return ChatRequestActivity._(db, botId, id, generation);
  }
}

class ChatRequestActivity {
  ChatRequestActivity._(this._db, this._botId, this._id, this._generation) {
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refresh().catchError((Object _) {}));
    });
  }
  final Database _db;
  final String _botId, _id, _generation;
  late final Timer _heartbeat;
  bool _released = false;

  Future<void> _refresh() => _db.transaction((txn) async {
        if (_released) return;
        final state = await ProactiveRequestGate._read(txn, _botId);
        state.refresh(DateTime.now().millisecondsSinceEpoch, _id,
            ProactiveRequestGate.leaseMs);
        await ProactiveRequestGate._put(
            txn, ProactiveRequestGate.key(_botId), state.encode());
      });

  Future<void> release() async {
    if (_released) return;
    _released = true;
    _heartbeat.cancel();
    await _db.transaction((txn) async {
      final state = await ProactiveRequestGate._read(txn, _botId);
      final now = DateTime.now().millisecondsSinceEpoch;
      state.release(now, _id, _generation);
      await ProactiveRequestGate._put(
          txn, ProactiveRequestGate.key(_botId), state.encode());
      if (state.liveChats(now).isEmpty)
        await ProactiveRequestGate._reschedule(txn, _botId);
    });
  }
}
