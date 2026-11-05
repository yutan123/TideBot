import 'dart:convert';

/// Keep credentials out of persisted tool diagnostics, including nested inputs.
String redactToolInput(Map<String, dynamic> args) {
  var remaining = 3000;
  Object? visit(Object? value, int depth) {
    if (remaining <= 0 || depth > 8) return '[truncated]';
    remaining -= 1;
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (remaining <= 0) break;
        final rawKey = entry.key.toString();
        final key = rawKey.length > 200 ? rawKey.substring(0, 200) : rawKey;
        remaining -= key.length;
        final lower = rawKey.toLowerCase();
        result[key] = const [
          'key',
          'token',
          'secret',
          'password',
          'authorization',
          'cookie',
          'credential'
        ].any(lower.contains)
            ? '[redacted]'
            : visit(entry.value, depth + 1);
      }
      return result;
    }
    if (value is List) {
      final result = <Object?>[];
      for (final item in value) {
        if (remaining <= 0) break;
        result.add(visit(item, depth + 1));
      }
      return result;
    }
    if (value == null || value is bool || value is num) return value;
    final text = value.toString();
    final limit = remaining.clamp(0, 200);
    final safe = text.length > limit ? '${text.substring(0, limit)}…' : text;
    remaining -= safe.length;
    return safe;
  }

  final encoded = jsonEncode(visit(args, 0));
  return encoded.length <= 4000
      ? encoded
      : jsonEncode({'truncated': true, 'preview': encoded.substring(0, 1000)});
}
