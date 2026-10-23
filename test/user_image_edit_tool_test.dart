import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tide_bot/bot_image_request.dart';
import 'package:tide_bot/user_image_edit_tool.dart';

void main() {
  const current = {1: '/current-photo.png', 2: '/second-photo.png'};
  const history = {1: '/historical-photo.png', 7: '/older-photo.png'};
  const prompt = '  转为动漫画风。\n保留原图服装、背景和构图。  ';

  UserImageEditSelection resolve(Map<String, dynamic> args) =>
      resolveUserImageEdit(args,
          currentImages: current, historyImages: history);

  test('source selects the correct image even when numbers overlap', () {
    final now =
        resolve({'source': 'current', 'image_number': 1, 'prompt': prompt});
    final old =
        resolve({'source': 'history', 'image_number': 1, 'prompt': prompt});
    expect(now.path, '/current-photo.png');
    expect(old.path, '/historical-photo.png');
    expect(now.prompt, prompt);
    expect(old.prompt, prompt);
    expect(current, {1: '/current-photo.png', 2: '/second-photo.png'});
    expect(history, {1: '/historical-photo.png', 7: '/older-photo.png'});
  });

  test('source and number must be explicit and cannot select another group',
      () {
    for (final args in <Map<String, dynamic>>[
      {'image_number': 1, 'prompt': prompt},
      {'source': 'latest', 'image_number': 1, 'prompt': prompt},
      {'source': 'current', 'prompt': prompt},
      {'source': 'history', 'image_number': 2, 'prompt': prompt},
      {'source': 'current', 'image_number': 7, 'prompt': prompt},
      {'source': 'history', 'image_number': 99, 'prompt': prompt},
    ]) {
      expect(() => resolve(args), throwsFormatException);
    }
  });

  test('image numbers reject strings, decimals, zero and negative values', () {
    for (final number in ['1', 1.0, 0, -1, null, true]) {
      expect(
          () => resolve(
              {'source': 'current', 'image_number': number, 'prompt': prompt}),
          throwsFormatException);
    }
  });

  test('prompt is required and never supplied or coerced by the application',
      () {
    for (final value in [null, '', ' \n ', 123, true]) {
      expect(
          () => resolve(
              {'source': 'current', 'image_number': 1, 'prompt': value}),
          throwsFormatException);
    }
  });

  test('paths, URLs and permanent reference options are rejected', () {
    for (final key in ['path', 'image_path', 'url', 'use_portrait_reference']) {
      expect(
          () => resolve({
                'source': 'current',
                'image_number': 1,
                'prompt': prompt,
                key: '/untrusted.png',
              }),
          throwsFormatException);
    }
  });

  test('a later request cannot reuse a previous temporary selection', () {
    resolve({'source': 'current', 'image_number': 1, 'prompt': prompt});
    expect(
        () => resolveUserImageEdit(
            {'source': 'current', 'image_number': 1, 'prompt': prompt},
            currentImages: const {}, historyImages: history),
        throwsFormatException);
  });

  test('schema requires all parameters and separates edit from portrait tools',
      () {
    final function = userImageEditToolSchema(
        currentImageNumbers: [1, 2],
        historyImageNumbers: [1, 7])['function'] as Map;
    expect(function['name'], 'edit_user_image');
    final parameters = function['parameters'] as Map;
    expect(parameters['required'], ['source', 'image_number', 'prompt']);
    expect(parameters['additionalProperties'], isFalse);
    expect(function['description'], contains('不能用 generate_image 代替'));
    expect(function['description'], contains('系统不会追加'));
    expect(function['description'], contains('可用编号参见当前上下文'));
    expect(
      userImageEditToolSchema(
        currentImageNumbers: [3],
        historyImageNumbers: [4, 9],
      )['function'],
      function,
    );
    final properties = parameters['properties'] as Map;
    expect(properties.keys, ['source', 'image_number', 'prompt']);
    expect((properties['source'] as Map)['enum'], ['current', 'history']);
    expect((properties['image_number'] as Map)['type'], 'integer');
  });

  test('context labels current and historical numbers independently', () {
    final context = userImageEditContext(
        currentImageNumbers: [1, 2], historyImageNumbers: [1, 7]);
    expect(context, contains('source=current）：[本轮图片#1]、[本轮图片#2]'));
    expect(context, contains('source=history）：[图片#1]、[图片#7]'));
    expect(context, isNot(contains('/current-photo.png')));
  });

  for (final source in ['current', 'history']) {
    test('$source edit uploads the chosen reference with the exact prompt',
        () async {
      final selection =
          resolve({'source': source, 'image_number': 1, 'prompt': prompt});
      final bytesByPath = {
        '/current-photo.png': [137, 80, 78, 71, 1],
        '/historical-photo.png': [137, 80, 78, 71, 2],
      };
      final request = buildBotImageRequest(
          baseUrl: 'https://example.com/v1',
          model: 'image-edit-model',
          apiKey: 'key',
          prompt: selection.prompt,
          reference: bytesByPath[selection.path]!,
          applyPortraitInstructions: false) as http.MultipartRequest;
      expect(request.url.path, '/v1/images/edits');
      expect(request.fields['prompt'], prompt);
      expect(request.fields['prompt'], isNot(contains('日常穿搭参考')));
      expect(request.fields['prompt'], isNot(contains('保持人物身份一致')));
      expect(request.files.single.field, 'image');
      expect(request.files.single.contentType.toString(), 'image/png');
      expect(await request.files.single.finalize().toBytes(),
          bytesByPath[selection.path]);
    });
  }
}
