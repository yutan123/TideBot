import 'package:tide_bot/proactive_request_state.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  const lease = 600000;
  var state = ProactiveRequestState.decode(null);
  check(state.allows(0, ''), 'Existing installations start idle');
  state.userActivity(10, 'user-1', lease);
  check(!state.allows(11, ''), 'User intent invalidates a prepared request');
  check(state.busy(11), 'Attachment preparation and debounce reserve the turn');
  state.begin(20, 'chat-1', 'request-1', lease);
  check(!state.allows(21, 'request-1'),
      'An active normal chat blocks proactive startup');
  state = ProactiveRequestState.decode(state.encode());
  check(state.busy(30), 'Reservations survive another engine reading SQLite');
  state.userActivity(40, 'user-2', lease);
  state.release(50, 'chat-1', 'request-1');
  check(state.busy(51),
      'Releasing an old request preserves the queued user turn');
  state.begin(60, 'chat-2', 'request-2', lease);
  state.begin(70, 'chat-3', 'request-3', lease);
  state.release(80, 'chat-2', 'request-2');
  check(
      state.busy(81), 'Overlapping normal chats release only their own lease');
  state.refresh(lease, 'chat-3', lease);
  check(state.busy(lease + 100), 'Heartbeat protects long normal requests');
  state.release(lease + 101, 'chat-3', 'request-3');
  check(!state.busy(lease + 102),
      'Success, failure and cancellation can all release a lease');
  check(!state.allows(lease + 102, ''),
      'A late old proactive result stays invalid after chat ends');
  check(!state.allows(lease + 102, 'request-2'),
      'Releasing a newer request never revives an old version');
  check(state.allows(lease + 102, 'request-3'),
      'A fresh proactive cycle can run after the interval');
  final otherBot = ProactiveRequestState.decode(null);
  state.begin(lease + 200, 'chat-4', 'request-4', lease);
  check(otherBot.allows(lease + 201, ''), 'Bots have independent reservations');
  check(!state.busy(lease * 2 + 201),
      'Killed engines recover through lease expiration');
  check(!state.allows(lease * 2 + 201, 'request-3'),
      'Expiration cannot restore stale requests');
  for (final broken in [
    'invalid',
    '[]',
    '{"chats":false}',
    '{"chats":{"bad":"x"},"pendingUntil":"x"}'
  ]) {
    check(!ProactiveRequestState.decode(broken).busy(1),
        'Malformed state is recoverable: $broken');
  }
  print('Proactive request coordination regression checks passed.');
}
