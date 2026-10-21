import 'dart:async';
import 'package:flutter/foundation.dart';
import 'db.dart';

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
  void startRinging(String callId, String botId, {bool isIncoming = true}) {
    final call = ActiveCall(
      botId: botId,
      callId: callId,
      initiator: isIncoming ? 'assistant' : 'user',
      startTime: DateTime.now(),
    );
    _ringingCalls[botId] = call;

    // 2分钟超时
    _timeoutTimers[callId] = Timer(const Duration(minutes: 2), () {
      if (_ringingCalls.containsKey(botId)) {
        timeout(botId, callId);
      }
    });

    notifyListeners();
  }

  /// 接听通话
  void accept(String botId, String callId) {
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
    _ringingCalls.remove(botId);
    _timeoutTimers[callId]?.cancel();
    _timeoutTimers.remove(callId);
    notifyListeners();
  }

  /// 超时
  Future<void> timeout(String botId, String callId) async {
    _ringingCalls.remove(botId);
    _timeoutTimers[callId]?.cancel();
    _timeoutTimers.remove(callId);

    // 更新数据库和聊天记录
    try {
      await DBManager().updateVoiceCallRecord(
        callId,
        status: 'timeout',
        endTime: DateTime.now(),
      );

      await DBManager().updateChatMessage(
        callId,
        content: '[语音通话，超时未接通]',
      );
    } catch (_) {
      // 静默失败
    }

    notifyListeners();
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
