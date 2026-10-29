import 'dart:convert';

/// Video analysis is source material for the next chat request, not a chat reply.
/// Do not apply chat protocol/planning filters to this text.
String parseVideoAnalysisResponse(String source, {required int statusCode}) {
  final raw = source.replaceFirst('\uFEFF', '').trim();
  dynamic payload;
  try {
    payload = jsonDecode(raw);
  } on FormatException {
    if (statusCode < 200 || statusCode >= 300) {
      throw StateError('视频解析请求失败（HTTP $statusCode），响应不是 JSON');
    }
    if (!RegExp(r'^data:', multiLine: true).hasMatch(raw)) {
      throw const FormatException('视频解析接口返回了非 JSON 响应，请检查服务地址');
    }
    final result = StringBuffer();
    final event = <String>[];
    void consume() {
      if (event.isEmpty) return;
      final data = event.join('\n').trim();
      event.clear();
      if (data == '[DONE]') return;
      final decoded = jsonDecode(data);
      _checkVideoError(decoded, statusCode);
      result.write(_videoText(decoded));
    }

    for (final line in const LineSplitter().convert(raw)) {
      if (line.isEmpty) {
        consume();
      } else if (line.startsWith('data:')) {
        event.add(line.substring(5).trimLeft());
      }
    }
    consume();
    return _requireVideoText(result.toString());
  }
  _checkVideoError(payload, statusCode);
  return _requireVideoText(_videoText(payload));
}

void _checkVideoError(dynamic payload, int statusCode) {
  final error = payload is Map ? payload['error'] : null;
  final code = payload is Map ? payload['code'] : null;
  if (statusCode < 200 ||
      statusCode >= 300 ||
      (error != null && error != false) ||
      (code != null && ![0, 200, '0', '200', 'OK', 'Success'].contains(code))) {
    final detail = error is Map
        ? error['message'] ?? error['code']
        : error ?? (payload is Map ? payload['message'] ?? code : null);
    // Keep diagnostic text bounded and exclude any echoed media or credentials.
    var message = detail?.toString() ?? '服务商未提供错误详情';
    message = message.replaceAll(RegExp(r'data:[^\s"]+'), '[媒体已省略]').replaceAll(
        RegExp(r'Bearer\s+[^\s,}]+', caseSensitive: false),
        'Bearer [REDACTED]');
    if (message.length > 500) message = '${message.substring(0, 500)}…';
    throw StateError('视频解析请求失败（HTTP $statusCode）：$message');
  }
}

String _requireVideoText(String text) {
  if (text.trim().isEmpty) {
    throw StateError('视频解析接口未返回分析正文（HTTP 成功不代表解析成功），请检查模型是否支持原视频输入');
  }
  return text.trim();
}

String _videoContent(dynamic value) {
  if (value is String) return value;
  if (value is List)
    return value.map(_videoContent).where((s) => s.isNotEmpty).join('\n');
  if (value is Map) {
    return _videoContent(value['text'] ?? value['content']);
  }
  return '';
}

String _videoText(dynamic payload) {
  if (payload is! Map) return '';
  final choices = payload['choices'];
  if (choices is List && choices.isNotEmpty && choices.first is Map) {
    final choice = choices.first as Map;
    final message = choice['message'] ?? choice['delta'];
    final text = message is Map ? _videoContent(message['content']) : '';
    if (text.isNotEmpty) return text;
    final direct = _videoContent(choice['text']);
    if (direct.isNotEmpty) return direct;
  }
  final output = payload['output'];
  if (output is Map) {
    final nested = _videoText(output);
    if (nested.isNotEmpty) return nested;
    final message = output['message'];
    if (message is Map) {
      final text = _videoContent(message['content']);
      if (text.isNotEmpty) return text;
    }
  } else if (output is List) {
    final text = output
        .whereType<Map>()
        .where((m) => m['type'] == 'message')
        .map((m) => _videoContent(m['content']))
        .where((s) => s.isNotEmpty)
        .join('\n');
    if (text.isNotEmpty) return text;
  }
  final data = payload['data'];
  if (data is Map) {
    final text = _videoText(data);
    if (text.isNotEmpty) return text;
  }
  return _videoContent(
      payload['output_text'] ?? payload['text'] ?? payload['content']);
}
