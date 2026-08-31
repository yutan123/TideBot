import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/ai.dart';
import 'package:tide_bot/chat_event_bus.dart';

void main() {
  test('cancellation token invokes callbacks once and supports late listeners',
      () {
    final token = AICancellationToken();
    var calls = 0;
    token.addOnCancel(() => calls++);
    token.cancel();
    token.cancel();
    token.addOnCancel(() => calls++);

    expect(token.isCancelled, isTrue);
    expect(calls, 2);
    expect(
        () => token.throwIfCancelled(), throwsA(isA<AICancelledException>()));
  });

  test('chat event bus delivers message identity and version', () async {
    const event = ChatEvent(
      type: ChatEventType.updated,
      botId: 'bot-1',
      messageId: 'message-1',
      version: 3,
      message: {'content': 'updated'},
    );
    final received = <ChatEvent>[];
    final subscription = ChatEventBus.instance.events.listen(received.add);
    addTearDown(subscription.cancel);

    ChatEventBus.instance.publish(event);
    await Future<void>.delayed(const Duration());

    expect(received, hasLength(1));
    expect(received.single.type, ChatEventType.updated);
    expect(received.single.botId, 'bot-1');
    expect(received.single.messageId, 'message-1');
    expect(received.single.version, 3);
    expect(received.single.message?['content'], 'updated');
  });
}
