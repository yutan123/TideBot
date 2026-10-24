import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

/// 视频处理服务，负责抽帧和音频提取
class VideoProcessingService {
  static final VideoProcessingService _instance =
      VideoProcessingService._internal();
  static VideoProcessingService get instance => _instance;
  VideoProcessingService._internal();

  /// 获取视频时长（秒）
  Future<double> getVideoDuration(String videoPath) async {
    try {
      final session = await FFmpegKit.execute('-i "$videoPath"');
      final output = await session.getOutput();
      final allOutput = await session.getAllLogsAsString();

      // FFmpeg 将信息输出到 stderr
      final fullOutput = (output ?? '') + (allOutput ?? '');
      final durationRegex = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2}\.\d{2})');
      final match = durationRegex.firstMatch(fullOutput);

      if (match != null) {
        final hours = int.parse(match.group(1)!);
        final minutes = int.parse(match.group(2)!);
        final seconds = double.parse(match.group(3)!);
        return hours * 3600 + minutes * 60 + seconds;
      }

      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// 抽帧配置
  VideoFrameConfig calculateFrameConfig(double durationSeconds) {
    if (durationSeconds <= 30) {
      // ≤30秒：2秒/帧，上限15帧
      final frameCount = (durationSeconds / 2).ceil().clamp(1, 15);
      return VideoFrameConfig(
        frameCount: frameCount,
        interval: durationSeconds / frameCount,
      );
    } else if (durationSeconds <= 120) {
      // 30秒-2分钟：5秒/帧，范围6-24帧
      final frameCount = (durationSeconds / 5).ceil().clamp(6, 24);
      return VideoFrameConfig(
        frameCount: frameCount,
        interval: durationSeconds / frameCount,
      );
    } else if (durationSeconds <= 300) {
      // 2-5分钟：8秒/帧，范围15-37帧
      final frameCount = (durationSeconds / 8).ceil().clamp(15, 37);
      return VideoFrameConfig(
        frameCount: frameCount,
        interval: durationSeconds / frameCount,
      );
    } else {
      // >5分钟：预览模式，前5帧
      return VideoFrameConfig(
        frameCount: 5,
        interval: 8.0,
        isPreview: true,
      );
    }
  }

  /// 抽取视频帧
  Future<List<String>> extractFrames({
    required String videoPath,
    required int frameCount,
    required double duration,
    int targetWidth = 854, // 480p宽度
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outputDir = Directory(
        '${tempDir.path}/video_frames_${DateTime.now().millisecondsSinceEpoch}');
    await outputDir.create(recursive: true);

    final framePaths = <String>[];
    final interval = duration / frameCount;

    try {
      for (int i = 0; i < frameCount; i++) {
        final timestamp = i * interval;
        final outputPath = '${outputDir.path}/frame_$i.jpg';

        final command =
            '-ss ${timestamp.toStringAsFixed(2)} -i "$videoPath" -vframes 1 -vf scale=$targetWidth:-1 -q:v 3 "$outputPath"';

        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode) &&
            await File(outputPath).exists()) {
          framePaths.add(outputPath);
        }
      }

      return framePaths;
    } catch (e) {
      // 清理已创建的文件
      for (final path in framePaths) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 提取音频并转为 WAV
  Future<String?> extractAudio(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/video_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      final command =
          '-i "$videoPath" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) && await File(outputPath).exists()) {
        // 检查文件大小，如果太小可能没有音频
        final fileSize = await File(outputPath).length();
        if (fileSize < 1024) {
          // 小于1KB，可能是无声视频
          await File(outputPath).delete();
          return null;
        }
        return outputPath;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 清理临时文件
  Future<void> cleanupTempFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        // 如果是帧图片，也删除父目录
        if (path.contains('video_frames_')) {
          final dir = file.parent;
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      } catch (_) {}
    }
  }

  /// 执行FFmpeg命令
  Future<bool> executeFFmpegCommand(String command) async {
    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      } else {
        final output = await session.getOutput();
        print('[FFmpeg] Command failed: $output');
        return false;
      }
    } catch (e) {
      print('[FFmpeg] Execute error: $e');
      return false;
    }
  }
}

/// 视频帧配置
class VideoFrameConfig {
  final int frameCount;
  final double interval;
  final bool isPreview;

  VideoFrameConfig({
    required this.frameCount,
    required this.interval,
    this.isPreview = false,
  });
}

/// 视频处理结果
class VideoProcessingResult {
  final List<String> framePaths;
  final String? audioPath;
  final double duration;
  final bool isPreview;
  final String? originalVideoPath; // 保存的原始视频文件路径（用户上传时压缩保存）

  VideoProcessingResult({
    required this.framePaths,
    this.audioPath,
    required this.duration,
    this.isPreview = false,
    this.originalVideoPath,
  });

  /// 清理所有临时文件
  Future<void> cleanup() async {
    // 只清理帧图片和临时音频文件，保留压缩后的原始视频文件
    await VideoProcessingService.instance.cleanupTempFiles([
      ...framePaths,
      if (audioPath != null) audioPath!,
      // 注意：不删除 originalVideoPath，因为它需要被长期保存用于后续查看
    ]);
  }
}
