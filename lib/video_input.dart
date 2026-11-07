import 'dart:async';
import 'ai.dart';
import 'video_request.dart';
import 'video_source_context.dart';
import 'video_processing_service.dart';

bool isVideoAttachment(String path) => const {
      'mp4',
      'mov',
      'mkv',
      'avi',
      'webm',
      'm4v',
      '3gp',
      'mpeg',
      'mpg',
    }.contains(path.split('.').last.toLowerCase());

/// Runs only after the user's attachment has been sent and persisted.
class PreparedVideoInput {
  final double duration;
  final String context;
  final List<String> frames;
  final VideoProcessingResult? temporaryMedia;
  const PreparedVideoInput(this.context,
      {this.frames = const [], this.temporaryMedia, this.duration = 0});

  Future<void> cleanup() async => temporaryMedia?.cleanup();
}

Future<PreparedVideoInput> prepareVideoInput({
  required String path,
  required String botId,
  required String modelId,
  String userText = '',
  String videoId = '',
  Future<double> Function()? readDuration,
  Future<String> Function()? analyzeOriginal,
  Future<VideoProcessingResult> Function()? extractMedia,
  Future<String?> Function(String)? transcribe,
}) async {
  final duration = await (readDuration?.call() ??
      VideoProcessingService.instance.getVideoDuration(path));
  // A local probe failure must not prevent a capable remote model from seeing
  // the original file. Only the extraction path requires a known duration.
  if (shouldSendOriginalVideo(modelId, duration)) {
    final analysis = await (analyzeOriginal?.call() ??
            AIManager().describeVideoForBot(
              videoPath: path,
              botId: botId,
              providerId: modelId.trim(),
              userText: userText,
            ))
        .timeout(const Duration(minutes: 5));
    return PreparedVideoInput('[视频解析模型分析]\n$analysis', duration: duration);
  }
  if (!duration.isFinite || duration <= 0) throw StateError('无法读取视频时长，请重新选择视频');
  final result = await (extractMedia?.call() ?? _extract(path, duration))
      .timeout(const Duration(minutes: 5));
  try {
    final transcript = result.audioPath == null
        ? null
        : await (transcribe?.call(result.audioPath!) ??
                AIManager().transcribeAudio(
                    botId: botId,
                    audioPath: result.audioPath!,
                    sourceContext: videoAudioSourceContext(videoId,
                        isPreview: result.isPreview)))
            .timeout(const Duration(seconds: 60));
    return PreparedVideoInput(
        [
          '[用户发送的视频：${result.duration.toStringAsFixed(1)}秒，${result.framePaths.length}帧]',
          '本条视频的抽帧图片与下方音轨转写（如有）均来自同一个视频；请结合两者理解，不要当作彼此无关的图片和聊天语音。',
          if (result.audioPath == null) '本视频未提取到音轨，请仅依据画面回答。',
          if (result.isPreview)
            '长视频预览：仅提供前40秒画面及从原视频提取的音轨转写（如有），两者不保证逐帧对应。请自行判断是否需要完整视频；需要时调用 view_video，video_id 使用本条提供的编号，full_video 设为 true。无需向用户确认；不需要则直接回答。未调用前不得声称看过完整视频。',
          if (transcript?.trim().isNotEmpty == true)
            '视频音轨转写（来自本条视频，不是用户单独发送的聊天语音）\n音频内容：${transcript!.trim()}',
          if (result.audioPath != null && transcript?.trim().isNotEmpty != true)
            '音频未取得转写结果，请仅依据画面回答。',
        ].join('\n'),
        frames: result.framePaths,
        temporaryMedia: result);
  } catch (_) {
    await result.cleanup();
    rethrow;
  }
}

Future<VideoProcessingResult> _extract(String path, double duration) async {
  final service = VideoProcessingService.instance;
  final config = service.calculateFrameConfig(duration);
  List<String> frames = [];
  String? audio;
  try {
    // Wait for both tasks so cleanup cannot race ongoing extraction.
    await Future.wait<void>([
      () async {
        frames = await service.extractFrames(
            videoPath: path, frameCount: config.frameCount, duration: duration);
      }(),
      () async {
        audio = await service.extractAudio(path);
      }(),
    ]);
    if (frames.isEmpty) throw StateError('视频抽帧失败，请检查视频格式后重试');
    return VideoProcessingResult(
        framePaths: frames,
        audioPath: audio,
        duration: duration,
        isPreview: config.isPreview);
  } catch (_) {
    await service.cleanupTempFiles([...frames, if (audio != null) audio!]);
    rethrow;
  }
}
