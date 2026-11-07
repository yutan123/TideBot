import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/video_input.dart';
import 'package:tide_bot/video_processing_service.dart';

void main() {
  test('超过五分钟即使已选择模型也先预览并让机器人决定完整分析', () async {
    final result = await prepareVideoInput(
      path: '/long.mp4',
      botId: 'bot',
      modelId: 'selected',
      readDuration: () async => 301,
      analyzeOriginal: () => throw StateError('不应直接发送完整视频'),
      extractMedia: () async => VideoProcessingResult(
          framePaths: ['preview'], duration: 301, isPreview: true),
    );
    expect(result.frames, ['preview']);
    expect(result.context, contains('full_video'));
    expect(result.context, contains('无需向用户确认'));
  });
  test('正好五分钟仍直接使用视频解析模型', () async {
    final result = await prepareVideoInput(
      path: '/v.mp4',
      botId: 'bot',
      modelId: 'selected',
      readDuration: () async => 300,
      analyzeOriginal: () async => '完整分析',
      extractMedia: () => throw StateError('不应抽帧'),
    );
    expect(result.context, contains('完整分析'));
    expect(result.duration, 300);
  });
  test('选视频模型时只发送原视频，不执行抽帧或转写', () async {
    var requests = 0;
    final result = await prepareVideoInput(
        path: '/video.mov',
        readDuration: () async => 10,
        botId: 'bot',
        modelId: 'video-provider',
        analyzeOriginal: () async {
          requests++;
          return '画面与声音分析';
        },
        extractMedia: () => throw StateError('不应抽帧'),
        transcribe: (_) => throw StateError('不应转写'));
    expect(requests, 1);
    expect(result.context, contains('画面与声音分析'));
    expect(result.frames, isEmpty);
    await result.cleanup();
  });
  test('不选择模型时抽帧并转写音频，帧传给聊天模型', () async {
    var extracted = false;
    final result = await prepareVideoInput(
        path: '/video.mp4',
        readDuration: () async => 10,
        botId: 'bot',
        modelId: '',
        analyzeOriginal: () => throw StateError('不应调用视频模型'),
        extractMedia: () async {
          extracted = true;
          return VideoProcessingResult(
              framePaths: ['frame1', 'frame2'],
              audioPath: 'audio.wav',
              duration: 10);
        },
        transcribe: (path) async {
          expect(path, 'audio.wav');
          return '你好';
        });
    expect(extracted, isTrue);
    expect(result.frames, ['frame1', 'frame2']);
    expect(result.context, contains('音频内容：你好'));
    expect(result.context, contains('均来自同一个视频'));
    expect(result.context, contains('不是用户单独发送的聊天语音'));
  });
  test('所选视频模型失败时明确报错，不静默回落到抽帧', () async {
    expect(
        prepareVideoInput(
            path: '/v.mp4',
            readDuration: () async => 10,
            botId: 'bot',
            modelId: 'selected',
            analyzeOriginal: () async => throw StateError('模型不支持视频输入'),
            extractMedia: () => throw StateError('不应抽帧')),
        throwsA(
            isA<StateError>().having((e) => e.message, 'error', '模型不支持视频输入')));
  });
  test('无音轨视频照常发送画面，不调用转写', () async {
    final result = await prepareVideoInput(
        path: '/v.mp4',
        readDuration: () async => 10,
        botId: 'bot',
        modelId: '',
        extractMedia: () async =>
            VideoProcessingResult(framePaths: ['frame'], duration: 6),
        transcribe: (_) => throw StateError('不应转写'));
    expect(result.frames, ['frame']);
    expect(result.context, isNot(contains('音频内容')));
  });
  test('视频附件识别兼容大写扩展名且不影响其他文档', () {
    expect(isVideoAttachment('/file.MOV'), isTrue);
    expect(isVideoAttachment('/file.mp4'), isTrue);
    expect(isVideoAttachment('/file.pdf'), isFalse);
  });
}
