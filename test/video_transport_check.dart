import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:tide_bot/video_request.dart';
import 'package:tide_bot/video_response.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  check(shouldSendOriginalVideo('model', 0), '本地无法探测时长不能阻止原视频请求');
  check(shouldSendOriginalVideo(primaryVideoModel, 10), '主模型应进入原视频链路');
  check(!shouldSendOriginalVideo('', 10), '未设置视频模型应保留抽帧');
  check(!shouldSendOriginalVideo('model', 301), '长视频应保留预览策略');
  final directory = await Directory.systemTemp.createTemp('video_transport_');
  final file = File('${directory.path}/有 空格的视频.mp4');
  final bytes = [0, 1, 128, 255];
  await file.writeAsBytes(bytes);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final received = <String>[];
  final serverErrors = <Object>[];
  final subscription = server.listen((request) async {
    try {
      received.add(request.uri.path);
      check(request.method == 'POST', '必须发送 POST');
      check(
          request.headers.value('Authorization') == 'Bearer test-key', '鉴权头丢失');
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      check(body['model'] == 'chosen-model', '实际请求模型不正确');
      check(body['stream'] == false, '应请求非流式响应');
      final content = body['messages'][1]['content'];
      check(content[0]['text'] == '告诉我视频内容', '实际请求丢失问题');
      final media = content[1]['video_url']['url'] as String;
      check(base64Decode(media.split(',').last).join(',') == bytes.join(','),
          '实际上传内容不是原视频');
      if (request.uri.path.startsWith('/slow/')) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode =
          request.uri.path.startsWith('/unsupported/') ? 400 : 200;
      request.response.write(jsonEncode(request.response.statusCode == 200
          ? {
              'choices': [
                {
                  'message': {'content': '视频分析结果'}
                }
              ]
            }
          : {
              'error': {'message': 'model does not support video_url'}
            }));
      await request.response.close();
    } catch (error) {
      // Closing the client during the timeout case can close this socket.
      if (!request.uri.path.startsWith('/slow/')) serverErrors.add(error);
      try {
        await request.response.close();
      } catch (_) {}
    }
  });
  final origin = 'http://${server.address.address}:${server.port}';
  Future<dynamic> send(String base,
          {Duration timeout = const Duration(seconds: 5),
          void Function(String, Map<String, Object?>)? onStage}) =>
      requestVideoAnalysis(
          baseUrl: base,
          apiKey: 'test-key',
          path: file.path,
          mime: 'video/mp4',
          model: 'chosen-model',
          userText: '告诉我视频内容',
          timeout: timeout,
          onStage: onStage);
  try {
    final stages = <String>[];
    for (final base in ['$origin/v1', '$origin/v1/chat/completions/']) {
      final response =
          await send(base, onStage: (stage, _) => stages.add(stage));
      check(response.statusCode == 200, '原视频请求未成功');
      check(
          parseVideoAnalysisResponse(utf8.decode(response.bodyBytes),
                  statusCode: response.statusCode) ==
              '视频分析结果',
          '收到响应后必须交出可用分析正文');
      check(
          jsonDecode(response.body)['choices'][0]['message']['content'] ==
              '视频分析结果',
          '响应未完整接收');
    }
    check(received.take(2).every((path) => path == '/v1/chat/completions'),
        '完整地址不能重复拼接 chat/completions');
    check(stages.join(',') == 'encode,request,response,encode,request,response',
        '请求阶段必须可追踪');
    final failed = await send('$origin/unsupported');
    check(failed.statusCode == 400 && failed.body.contains('video_url'),
        '服务商错误不得伪装成功或丢失响应');
    var timedOut = false;
    try {
      await send('$origin/slow', timeout: const Duration(milliseconds: 300));
    } on TimeoutException {
      timedOut = true;
    }
    check(timedOut, '超时请求必须退出');
    check(serverErrors.isEmpty, '服务端收到无效原视频请求：$serverErrors');
    stdout.writeln('视频 HTTP 实际收发检查通过：原视频、完整地址、400 错误、超时');
  } finally {
    await subscription.cancel();
    await server.close(force: true);
    await directory.delete(recursive: true);
  }
}
