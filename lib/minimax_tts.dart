import 'dart:typed_data';

/// MiniMax HTTP TTS: https://platform.minimaxi.com/docs/api-reference/speech-t2a-http
String miniMaxTtsEndpoint(String configuredUrl) {
  final uri = Uri.parse(configuredUrl.trim());
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri
      .replace(
          path: path.endsWith('/t2a_v2')
              ? path
              : path.endsWith('/v1')
                  ? '$path/t2a_v2'
                  : '$path/v1/t2a_v2')
      .toString();
}

/// Non-streaming requests explicitly use output_format=hex, audio_setting=mp3.
/// HTTP 200 can still contain an API error and data may be null.
Uint8List decodeMiniMaxTtsAudio(dynamic response) {
  if (response is! Map) throw const FormatException('MiniMax 响应不是 JSON 对象');
  final status = response['base_resp'];
  if (status is! Map || status['status_code'] != 0) {
    throw FormatException(
        'MiniMax 语音合成失败：code=${status is Map ? status['status_code'] : 'missing'}，'
        '${status is Map ? status['status_msg'] : '缺少 base_resp'}，trace_id=${response['trace_id'] ?? ''}');
  }
  final data = response['data'];
  final audio = data is Map ? data['audio'] : null;
  if (audio is! String ||
      audio.isEmpty ||
      audio.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(audio)) {
    throw const FormatException('MiniMax 未返回有效的十六进制音频');
  }
  return Uint8List.fromList(List<int>.generate(audio.length ~/ 2,
      (i) => int.parse(audio.substring(i * 2, i * 2 + 2), radix: 16)));
}
