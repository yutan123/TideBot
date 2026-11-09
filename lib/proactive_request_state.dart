import 'dart:convert';

/// The JSON contract shared with the Android proactive worker.
class ProactiveRequestState {
  ProactiveRequestState._(this._state);

  factory ProactiveRequestState.decode(String? value) {
    try {
      return ProactiveRequestState._(
          Map<String, dynamic>.from(jsonDecode(value ?? '{}') as Map));
    } catch (_) {
      return ProactiveRequestState._({});
    }
  }

  final Map<String, dynamic> _state;
  String get generation =>
      _state['generation'] is String ? _state['generation'] as String : '';
  int get pendingUntil => _state['pendingUntil'] is num
      ? (_state['pendingUntil'] as num).toInt()
      : 0;

  Map<String, dynamic> liveChats(int now) {
    final chats = _state['chats'];
    return (chats is Map
        ? Map<String, dynamic>.from(chats)
        : <String, dynamic>{})
      ..removeWhere((_, until) => until is! num || until.toInt() <= now);
  }

  bool busy(int now) => pendingUntil > now || liveChats(now).isNotEmpty;

  bool allows(int now, String expectedGeneration) =>
      generation == expectedGeneration && !busy(now);

  void userActivity(int now, String nextGeneration, int leaseMs) {
    _state['generation'] = nextGeneration;
    _state['pendingUntil'] = now + leaseMs;
    _state['chats'] = liveChats(now);
  }

  void begin(int now, String id, String nextGeneration, int leaseMs) {
    userActivity(now, nextGeneration, leaseMs);
    _state['chats'] = liveChats(now)..[id] = now + leaseMs;
    _state['pendingUntil'] = 0;
  }

  void refresh(int now, String id, int leaseMs) {
    _state['chats'] = liveChats(now)..[id] = now + leaseMs;
  }

  void release(int now, String id, String requestGeneration) {
    _state['chats'] = liveChats(now)..remove(id);
    if (generation == requestGeneration) _state['pendingUntil'] = 0;
  }

  String encode() => jsonEncode(_state);
}
