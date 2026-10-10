import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tide_bot/bot_image_request.dart';
import 'package:tide_bot/bot_image_tool.dart';

void main() {
  test('configured portrait requires an explicit boolean tool decision', () {
    final function =
        botImageToolSchema(hasPortraitReference: true)['function'] as Map;
    final parameters = function['parameters'] as Map;
    expect(parameters['required'], contains('use_portrait_reference'));
    expect(function['description'], contains('你自己的照片'));
    expect(function['description'], contains('如果画面出现人物'));
    expect(
        () => resolvePortraitReference(
            hasPortraitReference: true, selection: null),
        throwsFormatException);
    expect(
        () => resolvePortraitReference(
            hasPortraitReference: true, selection: 'false'),
        throwsFormatException);
  });

  test('food decision omits portrait and sends generation JSON', () {
    final useReference =
        resolvePortraitReference(hasPortraitReference: true, selection: false);
    final request = buildBotImageRequest(
      baseUrl: 'https://example.com/v1',
      model: 'image',
      apiKey: 'key',
      prompt: '一碗牛肉面，不包含人物',
      reference: useReference ? [137, 80, 78, 71] : null,
    );
    expect(request, isA<http.Request>());
    expect(request.url.path, '/v1/images/generations');
    expect(jsonDecode((request as http.Request).body)['prompt'], '一碗牛肉面，不包含人物');
  });

  test('portrait decision sends reference through image editing', () async {
    final useReference =
        resolvePortraitReference(hasPortraitReference: true, selection: true);
    final request = buildBotImageRequest(
      baseUrl: 'https://example.com/v1',
      model: 'image',
      apiKey: 'key',
      prompt: '在景点自拍',
      reference: useReference ? [137, 80, 78, 71] : null,
    ) as http.MultipartRequest;
    expect(request.url.path, '/v1/images/edits');
    expect(request.fields['prompt'], contains('保持人物身份一致'));
    expect(await request.files.single.finalize().toBytes(), [137, 80, 78, 71]);
  });

  test('unconfigured portrait uses text generation and rejects editing', () {
    final parameters =
        (botImageToolSchema(hasPortraitReference: false)['function']
            as Map)['parameters'] as Map;
    expect(
        (parameters['properties'] as Map).containsKey('use_portrait_reference'),
        false);
    expect(
        resolvePortraitReference(hasPortraitReference: false, selection: null),
        false);
    expect(
        resolvePortraitReference(hasPortraitReference: false, selection: false),
        false);
    expect(
        () => resolvePortraitReference(
            hasPortraitReference: false, selection: true),
        throwsFormatException);
  });
}
