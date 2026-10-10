import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tide_bot/bot_image_request.dart';

void main() {
  test('without reference keeps generation JSON request', () {
    final request = buildBotImageRequest(
        baseUrl: 'https://example.com/v1',
        model: 'image',
        apiKey: 'key',
        prompt: '画画') as http.Request;
    expect(request.url.path, '/v1/images/generations');
    expect(jsonDecode(request.body),
        {'model': 'image', 'prompt': '画画', 'n': 1, 'size': '1024x1024'});
    expect(request.headers['Authorization'], 'Bearer key');
  });
  test('reference is transmitted as PNG multipart edit input', () async {
    final request = buildBotImageRequest(
        baseUrl: 'https://example.com/v1',
        model: 'image',
        apiKey: 'key',
        prompt: '海边自拍',
        reference: [137, 80, 78, 71]) as http.MultipartRequest;
    expect(request.url.path, '/v1/images/edits');
    expect(request.fields['model'], 'image');
    expect(request.fields['prompt'], contains('海边自拍'));
    expect(request.fields['prompt'], contains('保持人物身份一致'));
    expect(request.files.single.field, 'image');
    expect(request.files.single.contentType.toString(), 'image/png');
    expect(await request.files.single.finalize().toBytes(), [137, 80, 78, 71]);
  });
}
