import 'dart:convert';

/// A missing scope means all bots, including bots created later. [] means none.
bool toolEnabledForBot(Object? encodedScope, String botId) {
  if (encodedScope == null) return true;
  try {
    final value = jsonDecode(encodedScope.toString());
    return value is List && value.contains(botId);
  } catch (_) {
    return false;
  }
}

List<Map<String, dynamic>> toolRowsForBot(
        List<Map<String, dynamic>> rows, String? botId) =>
    botId == null
        ? rows
        : rows
            .where((row) => toolEnabledForBot(row['bot_scope'], botId))
            .toList();
