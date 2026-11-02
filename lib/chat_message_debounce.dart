/// A turn may be superseded until its first durable reply or tool action.
/// Committing is idempotent so tools and message persistence share one boundary.
class ChatTurnCommit {
  bool _superseded = false;
  bool _committed = false;

  bool get isCommitted => _committed;

  bool supersede() {
    if (_committed) return false;
    _superseded = true;
    return true;
  }

  bool beginCommit() {
    if (_superseded) return false;
    _committed = true;
    return true;
  }
}

/// Monotonic, UI-independent policy for collecting a conversational turn.
class ChatMessageDebounce {
  ChatMessageDebounce({this.maxWait = const Duration(seconds: 12)});

  final Duration maxWait;
  Duration? _started;
  Duration? _messageAt;
  Duration? _inputAt;
  Duration _quiet = Duration.zero;
  int _shortStreak = 0;

  bool get hasMessages => _started != null;

  void addMessage(String text, Duration now) {
    _started ??= now;
    _messageAt = now;
    final clean = text.trim();
    final length = clean.runes.length;
    _shortStreak = length <= 10 ? _shortStreak + 1 : 0;
    var ms = length <= 3
        ? 3200
        : (length <= 10 ? 2600 : (length <= 30 ? 2000 : 1200));
    if (RegExp(r'(…|\.\.\.|[，、：:,])$').hasMatch(clean)) {
      ms += 1200;
    } else if (RegExp(r'[。！？!?]$').hasMatch(clean)) {
      ms -= 600;
    }
    if (_shortStreak >= 2) ms += 300 * (_shortStreak - 1).clamp(0, 3);
    _quiet = Duration(milliseconds: ms.clamp(1000, 6000));
  }

  void inputChanged({required bool hasText, required Duration now}) {
    _inputAt = hasText ? now : null;
  }

  bool isTyping(Duration now) =>
      _inputAt != null && now - _inputAt! < const Duration(milliseconds: 1500);

  Duration remaining(Duration now) {
    if (_started == null) return Duration.zero;
    final deadline = _started! + maxWait;
    var readyAt = _messageAt! + _quiet;
    if (_inputAt != null) {
      final inputReady = _inputAt! + const Duration(milliseconds: 1800);
      if (inputReady > readyAt) readyAt = inputReady;
    }
    if (readyAt > deadline) readyAt = deadline;
    return now >= readyAt ? Duration.zero : readyAt - now;
  }

  void reset() {
    _started = null;
    _messageAt = null;
    _shortStreak = 0;
  }
}

/// Batch IDs, rather than text equality, determine which saved user rows are
/// already supplied as the current turn. Other roles are never filtered.
List<Map<String, dynamic>> historyBeforeCurrentBatch(
  List<Map<String, dynamic>> history,
  Set<String> currentMessageIds,
) =>
    history
        .where(
          (row) =>
              row['role'] != 'user' ||
              !currentMessageIds.contains(row['id']?.toString()),
        )
        .toList();
