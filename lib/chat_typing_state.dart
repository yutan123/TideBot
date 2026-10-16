import 'dart:async';
import 'package:flutter/foundation.dart';

/// Transient UI activity must never be restored from a database boolean.
/// A new app process starts empty; re-entering a chat in the same process can
/// still observe a real in-flight operation. Each owner releases only its lease.
class ChatTypingState extends ChangeNotifier {
  static final instance = ChatTypingState();
  final Map<String, Set<ChatTypingLease>> _active = {};

  bool isTyping(String botId) => _active[botId]?.isNotEmpty == true;

  ChatTypingLease begin(String botId,
      {Duration lifetime = const Duration(minutes: 10)}) {
    final lease = ChatTypingLease._(this, botId);
    _active.putIfAbsent(botId, () => {}).add(lease);
    lease._expiry = Timer(lifetime, lease.close);
    notifyListeners();
    return lease;
  }

  void _finish(ChatTypingLease lease) {
    final entries = _active[lease.botId];
    if (entries?.remove(lease) != true) return;
    if (entries!.isEmpty) _active.remove(lease.botId);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final lease in _active.values.expand((items) => items)) {
      lease._expiry?.cancel();
      lease._closed = true;
    }
    _active.clear();
    super.dispose();
  }
}

class ChatTypingLease {
  ChatTypingLease._(this._owner, this.botId);
  final ChatTypingState _owner;
  final String botId;
  Timer? _expiry;
  bool _closed = false;
  bool get isClosed => _closed;

  void close() {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    _owner._finish(this);
  }
}
