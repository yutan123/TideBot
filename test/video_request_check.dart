import 'dart:convert';
import 'dart:io';
import 'package:tide_bot/video_request.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  check(resolveVideoProviderId(primaryVideoModel, ' main ') == 'main',
      '主模型选项必须解析为真实 provider ID');
  check(resolveVideoProviderId(' video ', 'main') == 'video',
      '独立视频模型必须保持所选 provider');
  check(resolveVideoProviderId('', 'main').isEmpty, '未选择模型应保留抽帧模式');
  var rejected = false;
  try {
    resolveVideoProviderId(primaryVideoModel, '');
  } on StateError {
    rejected = true;
  }
  check(rejected, '缺少主模型必须明确报错');
  final directory =
      await Directory.systemTemp.createTemp('video_request_check_');
  try {
    final file = File('${directory.path}/sample.mov');
    final bytes = [0, 1, 2, 128, 255];
    await file.writeAsBytes(bytes);
    for (final question in ['', '把视频里的内容告诉我']) {
      final body = jsonDecode(await buildVideoRequestBody(
          path: file.path,
          mime: 'video/quicktime',
          model: 'video-model',
          userText: question));
      check(body['model'] == 'video-model', '模型名称丢失');
      check(body['stream'] == false, '视频分析须明确使用非流式响应');
      final content = body['messages'][1]['content'];
      check(content[0]['text'] == (question.isEmpty ? '请分析这个视频。' : question),
          '用户问题丢失');
      final url = content[1]['video_url']['url'] as String;
      check(url.startsWith('data:video/quicktime;base64,'), '视频 MIME 或协议错误');
      check(base64Decode(url.split(',').last).join(',') == bytes.join(','),
          '原始视频字节必须完整传入请求');
    }
    var missingRejected = false;
    try {
      await buildVideoRequestBody(
          path: '${directory.path}/missing.mp4',
          mime: 'video/mp4',
          model: 'model',
          userText: '');
    } on FileSystemException {
      missingRejected = true;
    }
    check(missingRejected, '不可访问的文件必须保留错误');
  } finally {
    await directory.delete(recursive: true);
  }
  stdout.writeln('视频模型路由与原视频请求检查通过');
}
