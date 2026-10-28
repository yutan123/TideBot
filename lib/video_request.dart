import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:isolate';

const primaryVideoModel = '__use_primary_vision__';

bool shouldSendOriginalVideo(String selected, double duration) =>
    selected.trim().isNotEmpty && !(duration > 300);

String resolveVideoProviderId(String selected, String primary) {
  final id = selected.trim();
  if (id != primaryVideoModel) return id;
  final primaryId = primary.trim();
  if (primaryId.isEmpty) throw StateError('请先设置主聊天模型');
  return primaryId;
}

/// Keep file encoding and large JSON serialization off the UI isolate.
Future<String> buildVideoRequestBody({
  required String path,
  required String mime,
  required String model,
  required String userText,
}) =>
    Isolate.run(() async {
      final data = base64Encode(await File(path).readAsBytes());
      return jsonEncode({
        'model': model,
        'stream': false,
        'messages': [
          {
            'role': 'system',
            'content': '请客观分析视频中的画面、动作、声音与文字，结合问题提供中文分析。不确定的内容不得编造。',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': userText.isEmpty ? '请分析这个视频。' : userText
              },
              {
                'type': 'video_url',
                'video_url': {'url': 'data:$mime;base64,$data'}
              },
            ],
          },
        ],
      });
    });

Uri videoCompletionEndpoint(String baseUrl) {
  final uri = Uri.parse(baseUrl.trim());
  if (!const ['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
    throw StateError('视频模型服务地址无效');
  }
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (!path.endsWith('/chat/completions')) path = '$path/chat/completions';
  return uri.replace(path: path);
}

/// This is the same transport used by AIManager and the local HTTP regression.
Future<http.Response> requestVideoAnalysis({
  required String baseUrl,
  required String apiKey,
  required String path,
  required String mime,
  required String model,
  required String userText,
  Duration timeout = const Duration(minutes: 5),
  void Function(String stage, Map<String, Object?> data)? onStage,
}) async {
  final endpoint = videoCompletionEndpoint(baseUrl);
  final client = http.Client();
  var expired = false;
  try {
    return await () async {
      onStage?.call('encode', {'bytes': await File(path).length()});
      final body = await buildVideoRequestBody(
          path: path, mime: mime, model: model, userText: userText);
      if (expired) throw TimeoutException('视频请求准备超时');
      onStage?.call('request',
          {'url': endpoint.toString(), 'model': model, 'media_type': mime});
      final response = await client.post(endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey'
          },
          body: body);
      onStage?.call('response', {'status': response.statusCode});
      return response;
    }()
        .timeout(timeout, onTimeout: () {
      expired = true;
      throw TimeoutException('视频分析请求超时', timeout);
    });
  } finally {
    // Timeout must terminate the upload, rather than leave it running unseen.
    client.close();
  }
}
