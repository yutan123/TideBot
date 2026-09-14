import 'db.dart';

/// Rolls only at the full limit, then removes whole oldest messages to half.
/// The latest message is always preserved, even if it alone exceeds the limit.
({int removed, int tokens}) rollChatWindow(
    List<Map<String, dynamic>> messages, int limit) {
  final sizes = messages
      .map((m) => estimateTokens(m['content']?.toString() ?? ''))
      .toList();
  var tokens = sizes.fold<int>(0, (a, b) => a + b);
  var removed = 0;
  if (tokens >= limit) {
    while (tokens > limit ~/ 2 && removed < sizes.length - 1) {
      tokens -= sizes[removed++];
    }
  }
  return (removed: removed, tokens: tokens);
}
