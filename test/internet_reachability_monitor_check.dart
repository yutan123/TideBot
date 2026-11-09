import 'dart:async';

import '../lib/internet_reachability_monitor.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class ManualTimer implements Timer {
  ManualTimer(this.callback);
  final void Function(Timer) callback;
  bool _active = true;
  int _tick = 0;
  void fire() {
    if (!_active) return;
    _tick++;
    callback(this);
  }

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
}

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
}

Future<void> main() async {
  final requests = <Completer<bool>>[];
  final timers = <ManualTimer>[];
  final monitor = InternetReachabilityMonitor(
    probe: () {
      final pending = Completer<bool>();
      requests.add(pending);
      return pending.future;
    },
    periodicTimer: (duration, callback) {
      check(duration == const Duration(minutes: 1), 'Poll every minute');
      final timer = ManualTimer(callback);
      timers.add(timer);
      return timer;
    },
  );
  final results = <bool>[];
  var subscription = monitor.changes.listen(results.add);
  check(
      monitor.online == null && requests.isEmpty, 'No invented offline state');
  monitor.setForeground(false);
  check(requests.isEmpty && timers.isEmpty, 'No background startup work');
  monitor.setForeground(true);
  check(
      requests.length == 1 && timers.length == 1, 'Immediate foreground check');
  monitor.setForeground(true);
  timers.last.fire();
  check(requests.length == 1 && timers.length == 1,
      'No duplicate or overlapping checks');
  requests.last.complete(true);
  await flush();
  check(monitor.online == true && results.length == 1,
      'Publish first online result');

  // Simulate closing and reopening the sidebar, without restarting the monitor.
  await subscription.cancel();
  timers.last.fire();
  check(requests.length == 2 && monitor.online == true,
      'Poll with no sidebar; keep cache');
  subscription = monitor.changes.listen(results.add);
  check(monitor.online == true, 'Reopened sidebar sees cached online state');
  requests.last.complete(false);
  await flush();
  check(monitor.online == false && results.last == false,
      'Update only after completion');

  timers.last.fire();
  final staleRequest = requests.last;
  monitor.setForeground(false);
  final requestCount = requests.length;
  timers.last.fire();
  check(requests.length == requestCount && !timers.last.isActive,
      'Background cancels polling');
  check(monitor.online == false, 'Background preserves last result');
  monitor.setForeground(true);
  check(requests.length == requestCount + 1,
      'Resume checks immediately despite stale request');
  requests.last.complete(true);
  await flush();
  staleRequest.complete(false);
  await flush();
  check(monitor.online == true,
      'Stale previous-foreground result cannot overwrite');

  timers.last.fire();
  final backgroundRequest = requests.last;
  monitor.setForeground(false);
  backgroundRequest.complete(false);
  await flush();
  check(monitor.online == true, 'Ignore results completed in background');
  monitor.setForeground(true);
  check(monitor.online == true, 'Resume never resets cache to offline');
  requests.last.completeError(StateError('network failure'));
  await flush();
  check(
      monitor.online == false, 'Real foreground probe failure updates offline');

  await subscription.cancel();
  await monitor.dispose();
  final countAfterDispose = requests.length;
  monitor.setForeground(true);
  timers.last.fire();
  check(requests.length == countAfterDispose, 'Dispose stops future work');
  print('Internet reachability lifecycle checks passed');
}
