import 'dart:async';
import 'package:flutter/foundation.dart';
import 'db.dart';
import 'chat_event_bus.dart';

/// 语音通话状态
enum VoiceCallStatus {
  idle,
  ringing, // 响铃中（等待接听）
  active, // 通话中
  ended, // 已结束
  rejected, // 已拒接
  timeout, // 超时未接
}

/// 通话记录
class VoiceCallRecord {
  final String id;
  final String botId;
  final String initiator; // 'user' or 'assistant'
  final VoiceCallStatus status;
  final int duration; // 秒
  final String summary;
  final String transcript;
  final int timestamp;

  VoiceCallRecord({
    required this.id,
    required this.botId,
    required this.initiator,
    required this.status,
    required this.duration,
    required this.summary,
    required this.transcript,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'bot_id': botId,
        'initiator': initiator,
        'status': status.name,
        'duration': duration,
        'summary': summary,
        'transcript': transcript,
        'timestamp': timestamp,
      };

  factory VoiceCallRecord.fromJson(Map<String, dynamic> json) {
    return VoiceCallRecord(
      id: json['id']?.toString() ?? '',
      botId: json['bot_id']?.toString() ?? '',
      initiator: json['initiator']?.toString() ?? 'user',
      status: VoiceCallStatus.values.firstWhere(
        (e) => e.name == json['status']?.toString(),
        orElse: () => VoiceCallStatus.ended,
      ),
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      summary: json['summary']?.toString() ?? '',
      transcript: json['transcript']?.toString() ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 当前通话状态
class ActiveCall {
  final String botId;
  final String callId;
  final String initiator;
  final DateTime startTime;
  bool _bannerIgnored = false;
  bool get bannerIgnored => _bannerIgnored;

  ActiveCall({
    required this.botId,
    required this.callId,
    required this.initiator,
    required this.startTime,
  });
}

/// 语音通话状态管理服务
class VoiceCallStateService extends ChangeNotifier {
  static final VoiceCallStateService _instance =
      VoiceCallStateService._internal();
  factory VoiceCallStateService() => _instance;
  VoiceCallStateService._internal();

  static VoiceCallStateService get instance => _instance;

  /// 当前活跃的通话
  ActiveCall? _activeCall;
  ActiveCall? get activeCall => _activeCall;

  /// 等待接听的通话（响铃状态）
  final Map<String, ActiveCall> _ringingCalls = {};
  Map<String, ActiveCall> get ringingCalls => Map.unmodifiable(_ringingCalls);

  /// 响铃超时定时器
  final Map<String, Timer> _timeoutTimers = {};

  /// 开始响铃（机器人发起通话）
  void startRinging(String callId, String botId,
      {bool isIncoming = true, DateTime? startedAt}) {
    if (_activeCall != null || _ringingCalls.containsKey(botId)) return;
    final call = ActiveCall(
      botId: botId,
      callId: callId,
      initiator: isIncoming ? 'assistant' : 'user',
      startTime: startedAt ?? DateTime.now(),
    );
    _ringingCalls[botId] = call;

    // 2分钟超时
    final remaining = call.startTime
        .add(const Duration(minutes: 2))
        .difference(DateTime.now());
    _timeoutTimers[callId]?.cancel();
    _timeoutTimers[callId] =
        Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (_ringingCalls[botId]?.callId == callId) {
        timeout(botId, callId);
      }
    });

    notifyListeners();
  }

  /// 只收起来电浮岛，保留通话及未接超时处理。
  void ignoreBanner(String botId, String callId) {
    final call = _ringingCalls[botId];
    if (call == null || call.callId != callId || call._bannerIgnored) return;
    call._bannerIgnored = true;
    notifyListeners();
  }

  /// 接听通话
  void accept(String botId, String callId) {
    if (_ringingCalls[botId]?.callId != callId) return;
    final call = _ringingCalls.remove(botId);
    _timeoutTimers[callId]?.cancel();
    _timeoutTimers.remove(callId);

    if (call != null) {
      _activeCall = call;
      notifyListeners();
    }
  }

  /// 拒接通话
  void reject(String botId, String callId) {
    if (_ringingCalls[botId]?.callId != callId) return;
    _ringingCalls.remove(botId);
    _timeoutTimers[callId]?.cancel();
    _timeoutTimers.remove(callId);
    notifyListeners();
  }

  int _revision = 0;
  bool _recovered = false;
  final Set<String> _responding = {};

  /// Resolve competing buttons and timeout with one conditional transaction.
  Future<bool> respond(String botId, String callId,
      {required bool accepted}) async {
    if (_ringingCalls[botId]?.callId != callId || !_responding.add(callId))
      return false;
    _revision++;
    try {
      final db = await DBManager().database;
      final status = accepted ? 'active' : 'rejected';
      final content = accepted ? '[语音通话，通话中]' : '[语音通话，已拒接]';
      final changed = await db.transaction((txn) async {
        final count = await txn.update(
            'voice_call_records',
            {
              'status': status,
              if (!accepted) 'end_time': DateTime.now().millisecondsSinceEpoch,
            },
            where: "id = ? AND status = 'ringing'",
            whereArgs: [callId]);
        if (count > 0)
          await txn.update(
              'chat_history',
              {
                'call_status': status,
                'content': content,
              },
              where: 'id = ?',
              whereArgs: ['card_$callId']);
        return count;
      });
      if (changed == 0) {
        reject(botId, callId);
        return false;
      }
      if (accepted) {
        accept(botId, callId);
      } else {
        reject(botId, callId);
      }
      try {
        final message = await DBManager().getMessageById('card_$callId');
        ChatEventBus.instance.publish(ChatEvent(
            type: ChatEventType.updated,
            botId: botId,
            messageId: 'card_$callId',
            message: message));
      } catch (error) {
        debugPrint('Call event refresh failed: $error');
      }
      return true;
    } finally {
      _revision++;
      _responding.remove(callId);
      final waiting = _ringingCalls[botId];
      if (waiting?.callId == callId &&
          _timeoutTimers[callId]?.isActive != true) {
        _timeoutTimers[callId] = Timer(Duration.zero, () {
          unawaited(timeout(botId, callId));
        });
      }
    }
  }

  /// 超时
  Future<void> timeout(String botId, String callId) async {
    if (_ringingCalls[botId]?.callId != callId || _responding.contains(callId))
      return;
    _revision++;
    _ringingCalls.remove(botId);
    _timeoutTimers[callId]?.cancel();
    _timeoutTimers.remove(callId);

    try {
      final db = await DBManager().database;
      final changed = await db.transaction((txn) async {
        final count = await txn.update(
            'voice_call_records',
            {
              'status': 'timeout',
              'end_time': DateTime.now().millisecondsSinceEpoch,
            },
            where: "id = ? AND status = 'ringing'",
            whereArgs: [callId]);
        if (count > 0) {
          await txn.update(
              'chat_history',
              {
                'call_status': 'timeout',
                'content': '[语音通话，超时未接通]',
              },
              where: 'id = ?',
              whereArgs: ['card_$callId']);
        }
        return count;
      });
      if (changed > 0) {
        final message = await DBManager().getMessageById('card_$callId');
        ChatEventBus.instance.publish(ChatEvent(
            type: ChatEventType.updated,
            botId: botId,
            messageId: 'card_$callId',
            message: message));
      }
    } catch (error) {
      debugPrint('Call timeout update failed: $error');
    }
    notifyListeners();
  }

  bool _syncing = false;
  Future<void> synchronize() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final db = await DBManager().database;
      if (!_recovered && _activeCall == null && _responding.isEmpty) {
        // A call page cannot survive process death. Release abandoned active rows.
        await db.transaction((txn) async {
          await txn.rawUpdate(
              "UPDATE chat_history SET call_status = 'ended' WHERE call_id IN (SELECT id FROM voice_call_records WHERE status = 'active')");
          await txn.rawUpdate(
              "UPDATE voice_call_records SET status = 'ended', end_time = ? WHERE status = 'active'",
              [DateTime.now().millisecondsSinceEpoch]);
        });
        _recovered = true;
      }
      final revision = _revision;
      final rows = await db.rawQuery(
          "SELECT v.* FROM voice_call_records v JOIN chat_history h ON h.id = 'card_' || v.id WHERE v.status = 'ringing' AND v.initiator = 'assistant' ORDER BY v.start_time");
      if (revision != _revision || _responding.isNotEmpty) return;
      final ids = rows.map((row) => row['id'].toString()).toSet();
      for (final call in _ringingCalls.values.toList()) {
        if (!ids.contains(call.callId)) reject(call.botId, call.callId);
      }
      for (final row in rows) {
        final started = DateTime.fromMillisecondsSinceEpoch(
            (row['start_time'] as num).toInt());
        if (DateTime.now().difference(started).inMilliseconds < 1500) continue;
        startRinging(row['id'].toString(), row['bot_id'].toString(),
            startedAt: started);
      }
    } finally {
      _syncing = false;
    }
  }

  /// 结束通话
  void endCall() {
    _activeCall = null;
    notifyListeners();
  }

  /// 检查是否有响铃通话
  bool hasRingingCall(String botId) => _ringingCalls.containsKey(botId);

  /// 检查是否在通话中
  bool isInCall(String botId) => _activeCall?.botId == botId;

  /// 清理资源
  @override
  void dispose() {
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    super.dispose();
  }
}
