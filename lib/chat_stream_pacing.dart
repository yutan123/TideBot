import 'package:flutter/material.dart';

/// Display timing belongs to the chat client, independently of SSE chunk sizes.
Duration chatStreamInterval(int speed) => Duration(
    milliseconds: (320 - (speed.clamp(1, 100) - 1) * 240 / 99).round());

/// Consume one visible character without splitting emoji or combining marks.
(String, String) takeChatStreamCharacter(String pending) {
  if (pending.isEmpty) return ('', '');
  final first = pending.characters.first;
  return (first, pending.substring(first.length));
}
