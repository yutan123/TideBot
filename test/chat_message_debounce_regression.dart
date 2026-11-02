import 'package:tide_bot/chat_message_debounce.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  final superseded = ChatTurnCommit();
  check(superseded.supersede(), 'Uncommitted request must be cancellable');
  check(!superseded.beginCommit(), 'Superseded reply must not persist');
  check(!superseded.isCommitted, 'Rejected commit must not become durable');
  final committed = ChatTurnCommit();
  check(committed.beginCommit(), 'Current reply or tool may commit');
  check(!committed.supersede(), 'Durable reply/tool must not be replayed');
  check(committed.beginCommit(), 'Tool and reply commits must be idempotent');
  final replacement = ChatTurnCommit();
  check(
    replacement.beginCommit(),
    'New turn must not inherit old cancellation',
  );
  final window = ChatMessageDebounce();
  check(window.remaining(ms(0)) == Duration.zero, 'Empty queue must not wait');
  window.inputChanged(hasText: true, now: ms(0));
  check(
    window.remaining(ms(100)) == Duration.zero,
    'Typing alone must not send a draft',
  );
  check(window.isTyping(ms(1499)), 'Recent input should be active');
  check(!window.isTyping(ms(1500)), 'Idle draft must stop being active');
  window.inputChanged(hasText: false, now: ms(0));

  window.addMessage('那个', ms(0));
  check(
    window.remaining(ms(0)) == ms(3200),
    'Short fragment needs a collection window',
  );
  window.addMessage('我今天', ms(1000));
  check(
    window.remaining(ms(3200)) > Duration.zero,
    'Follow-up must reset the quiet deadline',
  );
  window.addMessage('想跟你说说', ms(2200));
  check(
    window.remaining(ms(5399)) > Duration.zero,
    'Three fragments must remain in the same turn',
  );
  check(
    window.remaining(ms(5400)) == Duration.zero,
    'Quiet turn must eventually flush',
  );

  window.reset();
  window.addMessage('你今天过得怎么样？', ms(0));
  final questionWait = window.remaining(ms(0));
  window.reset();
  window.addMessage('你今天过得怎么样，', ms(0));
  check(
    window.remaining(ms(0)) > questionWait,
    'Continuation punctuation should wait longer',
  );

  window.reset();
  window.addMessage('这是一个内容已经比较完整而且长度比较长的问题。请告诉我你的具体看法好吗？', ms(0));
  check(
    window.remaining(ms(0)) == ms(1000),
    'Complete long message should respond sooner',
  );
  window.inputChanged(hasText: true, now: ms(900));
  check(
    window.remaining(ms(1000)) == ms(1700),
    'Real input activity must extend the quiet window',
  );
  check(
    window.remaining(ms(2700)) == Duration.zero,
    'Unsent idle draft must not block forever',
  );
  window.inputChanged(hasText: true, now: ms(3000));
  window.inputChanged(hasText: false, now: ms(3100));
  check(!window.isTyping(ms(3100)), 'Clearing input must stop typing');
  check(
    window.remaining(ms(3100)) == Duration.zero,
    'Clearing draft must remove input hold',
  );

  window.reset();
  window.addMessage('等一下', ms(0));
  for (var i = 1; i < 12; i++) {
    window.addMessage('还有', ms(i * 1000));
    window.inputChanged(hasText: true, now: ms(i * 1000 + 500));
  }
  check(
    window.remaining(ms(11999)) == ms(1),
    'Repeated input must respect original deadline',
  );
  check(
    window.remaining(ms(12000)) == Duration.zero,
    'Twelve seconds must flush even while typing',
  );
  window.reset();
  window.addMessage('新一轮', ms(20000));
  check(
    window.remaining(ms(20000)) == ms(3200),
    'New turn must have a fresh deadline and streak',
  );

  window.reset();
  window.inputChanged(hasText: false, now: ms(0));
  window.addMessage('', ms(0));
  check(
    window.remaining(ms(0)) > Duration.zero,
    'Attachment-only sends also need a window',
  );

  final rows = <Map<String, dynamic>>[
    {'id': 'old', 'role': 'user', 'content': '重复文字'},
    {'id': 'a', 'role': 'user', 'content': '重复文字'},
    {'id': 'b', 'role': 'user', 'type': 'image', 'file_path': 'photo.heic'},
    {'id': 'c', 'role': 'user', 'type': 'audio', 'file_path': 'speech.wav'},
    {'id': 'reply', 'role': 'assistant', 'content': '已经提交的回复'},
  ];
  final before = historyBeforeCurrentBatch(rows, {'a', 'b', 'c', 'reply'});
  check(before.length == 2, 'Only current batch user rows may be filtered');
  check(
    before[0]['id'] == 'old',
    'Identical earlier user text must be preserved',
  );
  check(
    before[1]['id'] == 'reply',
    'Committed assistant messages must be preserved',
  );
  check(rows.length == 5, 'History filtering must not mutate saved rows');
  check(
    historyBeforeCurrentBatch(rows, {}).length == 5,
    'Legacy callers retain history',
  );
  print(
    'Chat debounce regression passed: collection, typing, deadlines, attachments and batch history.',
  );
}
