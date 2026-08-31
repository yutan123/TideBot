import 'dart:async';

/// In-process delivery channel for persisted chat changes.
///
/// Background isolates get their own bus instance. They still publish after
/// writing SQLite, while the foreground uses the same event contract for
/// immediate UI updates.
enum ChatEventType { inserted, updated, failed, retrying, read, unread }

class ChatEvent {
  final ChatEventType type;
  final String? botId;
  final String? messageId;
  final Map<String, dynamic>? message;
  final int version;

  const ChatEvent({
    required this.type,
    this.botId,
    this.messageId,
    this.message,
    this.version = 1,
  });
}

class ChatEventBus {
  ChatEventBus._();
  static final ChatEventBus instance = ChatEventBus._();

  final StreamController<ChatEvent> _controller =
      StreamController<ChatEvent>.broadcast(sync: true);

  Stream<ChatEvent> get events => _controller.stream;

  void publish(ChatEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }
}
