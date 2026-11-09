import 'dart:async';
import 'dart:io';

/// App-wide last-known internet reachability, independent of sidebar lifetime.
/// No check runs until the app enters the foreground.
class InternetReachabilityMonitor {
  InternetReachabilityMonitor({
    Future<bool> Function()? probe,
    this.interval = const Duration(minutes: 1),
    Timer Function(Duration, void Function(Timer))? periodicTimer,
  })  : _probe = probe,
        _periodicTimer = periodicTimer ?? Timer.periodic;

  static final instance = InternetReachabilityMonitor();

  final Future<bool> Function()? _probe;
  final Duration interval;
  final Timer Function(Duration, void Function(Timer)) _periodicTimer;
  final _changes = StreamController<bool>.broadcast(sync: true);
  Timer? _timer;
  ConnectionTask<Socket>? _connection;
  Socket? _socket;
  bool _foreground = false;
  bool _disposed = false;
  bool? _online;
  int _generation = 0;
  int? _checkingGeneration;

  bool? get online => _online;
  Stream<bool> get changes => _changes.stream;

  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _connection?.cancel();
    _connection = null;
    _socket?.destroy();
    _socket = null;
    if (!foreground) return;
    unawaited(_refresh());
    _timer = _periodicTimer(interval, (_) => unawaited(_refresh()));
  }

  bool _current(int generation) =>
      !_disposed && _foreground && generation == _generation;

  Future<void> _refresh() async {
    if (!_foreground || _disposed || _checkingGeneration == _generation) return;
    final generation = _generation;
    _checkingGeneration = generation;
    try {
      final online = await (_probe?.call() ?? _probeNetwork(generation));
      if (!_current(generation)) return;
      if (_online != online) {
        _online = online;
        _changes.add(online);
      }
    } catch (_) {
      if (_current(generation) && _online != false) {
        _online = false;
        _changes.add(false);
      }
    } finally {
      if (_checkingGeneration == generation) _checkingGeneration = null;
    }
  }

  Future<bool> _probeNetwork(int generation) async {
    // Device internet reachability, not model/provider health. Try independent
    // endpoints to avoid relying on one DNS lookup or one resolver.
    for (final address in ['1.1.1.1', '8.8.8.8']) {
      if (!_current(generation)) return false;
      ConnectionTask<Socket>? task;
      Socket? socket;
      try {
        task = await Socket.startConnect(InternetAddress(address), 53);
        if (!_current(generation)) {
          task.cancel();
          return false;
        }
        _connection = task;
        socket = await task.socket.timeout(const Duration(seconds: 2));
        if (!_current(generation)) return false;
        _socket = socket;
        return true;
      } catch (_) {
        // Only continue to the fallback while still in the same foreground visit.
      } finally {
        task?.cancel();
        socket?.destroy();
        if (identical(_connection, task)) _connection = null;
        if (identical(_socket, socket)) _socket = null;
      }
    }
    return false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    setForeground(false);
    _disposed = true;
    await _changes.close();
  }
}
