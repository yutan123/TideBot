import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoPoster {
  const VideoPoster(this.path, this.aspectRatio);
  final String path;
  final double aspectRatio;
}

/// Independent from model preparation: posters survive analysis frame cleanup.
class VideoPosterService {
  static final Map<String, Future<VideoPoster>> _pending = {};

  static Future<VideoPoster> load(String path) {
    return _pending.putIfAbsent(path, () {
      final future = _load(path);
      // Retain a bounded cache, but allow failures to be retried.
      unawaited(future.then<void>((_) {
        if (_pending.length > 80) _pending.remove(_pending.keys.first);
      }, onError: (Object error, StackTrace stack) {
        _pending.remove(path);
      }));
      return future;
    });
  }

  static Future<VideoPoster> _load(String path) async {
    final source = File(path);
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('视频文件不可访问', path);
    }
    final key = sha256.convert(utf8
        .encode('$path:${stat.size}:${stat.modified.microsecondsSinceEpoch}'));
    final temp = await getTemporaryDirectory();
    final directory = Directory('${temp.path}/video_posters');
    await directory.create(recursive: true);
    final poster = File('${directory.path}/$key.jpg');
    if (!await poster.exists() || await poster.length() == 0) {
      // Argument lists preserve paths containing spaces and quotation marks.
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-threads',
        '1',
        '-i',
        path,
        '-frames:v',
        '1',
        '-vf',
        'scale=640:-2',
        '-q:v',
        '3',
        poster.path,
      ]);
      if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
          !await poster.exists()) {
        if (await poster.exists()) await poster.delete();
        throw StateError('视频封面读取失败');
      }
    }
    final codec = await ui.instantiateImageCodec(await poster.readAsBytes());
    double ratio;
    try {
      final frame = await codec.getNextFrame();
      ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    return VideoPoster(poster.path, ratio);
  }
}
