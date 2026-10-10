import 'dart:convert';

/// Remove only recognizable internal tool payloads, preserving ordinary JSON.
String stripInternalToolPayloads(String text) {
  final out = StringBuffer();
  var cursor = 0;
  while (cursor < text.length) {
    final start = text.indexOf('{', cursor);
    if (start < 0) {
      out.write(text.substring(cursor));
      break;
    }
    out.write(text.substring(cursor, start));
    var depth = 0;
    var quoted = false;
    var escaped = false;
    var end = -1;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}' && --depth == 0) {
        end = i + 1;
        break;
      }
    }
    if (end < 0) {
      out.write(text.substring(start));
      break;
    }
    final chunk = text.substring(start, end);
    var internal = false;
    try {
      final value = jsonDecode(chunk);
      if (value is Map) {
        final name = value['name'] ??
            (value['function'] is Map ? value['function']['name'] : null);
        internal = const {
              'choose_silence',
              'set_emotion',
              'send_sticker',
              'write_diary'
            }.contains(name) ||
            (value.containsKey('mood') &&
                value.containsKey('intensity') &&
                value.containsKey('reason'));
      }
    } catch (_) {}
    if (!internal) out.write(chunk);
    cursor = end;
  }
  return out.toString().replaceAll(RegExp(r'```(?:json)?\s*```'), '').trim();
}

bool isFreshLifeEndEvent(DateTime end, DateTime now, {int resumedAt = 0}) {
  final age = now.difference(end);
  return !age.isNegative &&
      age <= const Duration(minutes: 10) &&
      end.millisecondsSinceEpoch > resumedAt;
}
