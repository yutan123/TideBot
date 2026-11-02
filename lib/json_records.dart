import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Reads a top-level JSON object, emitting large arrays one element at a time.
/// String escaping and nesting are tracked across arbitrary UTF-8 chunks.
class JsonRecords {
  static Stream<({String key, dynamic value, bool element})> read(
    File file, {
    Set<String> arrays = const {
      'messages',
      'video_history',
      'call_sessions',
      'call_messages',
    },
  }) async* {
    final reader = _Reader(file.openRead().transform(utf8.decoder));
    try {
      await reader.expect('{');
      if (await reader.peek() == '}') {
        await reader.take();
        if (await reader.peek() != null)
          throw const FormatException('JSON 尾部有多余内容');
        return;
      }
      while (true) {
        final key = jsonDecode(await reader.value()) as String;
        await reader.expect(':');
        if (arrays.contains(key)) {
          await reader.expect('[');
          if (await reader.peek() != ']') {
            while (true) {
              yield (
                key: key,
                value: jsonDecode(await reader.value()),
                element: true,
              );
              final delimiter = await reader.take();
              if (delimiter == ']') break;
              if (delimiter != ',') throw const FormatException('数组格式无效');
            }
          } else {
            await reader.take();
          }
          yield (key: key, value: null, element: false);
        } else {
          yield (
            key: key,
            value: jsonDecode(await reader.value()),
            element: false,
          );
        }
        final delimiter = await reader.take();
        if (delimiter == '}') break;
        if (delimiter != ',') throw const FormatException('JSON 对象格式无效');
      }
      if (await reader.peek() != null)
        throw const FormatException('JSON 尾部有多余内容');
    } finally {
      await reader.close();
    }
  }
}

class _Reader {
  final StreamIterator<String> _chunks;
  String _chunk = '';
  int _index = 0;
  _Reader(Stream<String> stream) : _chunks = StreamIterator(stream);
  Future<String?> _rawPeek() async {
    while (_index == _chunk.length) {
      if (!await _chunks.moveNext()) return null;
      _chunk = _chunks.current;
      _index = 0;
    }
    return _chunk[_index];
  }

  Future<String?> peek() async {
    var c = await _rawPeek();
    while (c != null && ' \n\r\t'.contains(c)) {
      _index++;
      c = await _rawPeek();
    }
    return c;
  }

  Future<String?> take() async {
    final c = await peek();
    if (c != null) _index++;
    return c;
  }

  Future<void> expect(String token) async {
    if (await take() != token) throw FormatException('预期 $token');
  }

  Future<String> value() async {
    if (await peek() == null) throw const FormatException('JSON 不完整');
    final buffer = StringBuffer();
    var depth = 0;
    var string = false;
    var escaped = false;
    while (true) {
      final c = await _rawPeek();
      if (c == null) break;
      if (!string &&
          depth == 0 &&
          (c == ',' || c == ']' || c == '}' || ' \n\r\t'.contains(c)))
        break;
      _index++;
      buffer.write(c);
      if (string) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          string = false;
          if (depth == 0) break;
        }
      } else if (c == '"') {
        string = true;
      } else if (c == '[' || c == '{') {
        depth++;
      } else if (c == ']' || c == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    if (string || depth != 0 || buffer.isEmpty)
      throw const FormatException('JSON 不完整');
    return buffer.toString();
  }

  Future<void> close() => _chunks.cancel();
}
