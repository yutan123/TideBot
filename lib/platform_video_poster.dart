import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'link_preview_models.dart';
import 'platform_video_resolver.dart';

/// Extract only one frame from the remote stream, without downloading the full
/// video for every card. Successful posters live in the OS temporary directory.
class PlatformVideoPoster {
  static final _pending = <String, Future<String?>>{};

  static Future<String?> load(LinkPreviewData data) {
    final key = sha256
        .convert(utf8
            .encode(jsonEncode([data.url, data.videoUrl, data.imageHeaders])))
        .toString();
    return _pending.putIfAbsent(key, () async {
      try {
        return await _load(data, key);
      } catch (_) {
        return null;
      } finally {
        // Cache files, not failed futures or paths to files the OS can evict.
        _pending.remove(key);
      }
    });
  }

  static Future<String?> _load(LinkPreviewData data, String key) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/platform_posters');
    await folder.create(recursive: true);
    final output = File('${folder.path}/$key.jpg');
    if (await output.exists() && await output.length() > 0) return output.path;
    var video = data.videoUrl;
    var headers = data.imageHeaders;
    if (video == null) {
      final result = await PlatformVideoResolver().parse(data.url);
      if (result == null || result.isGallery) return null;
      video = result.videoUrl;
      headers = result.headers;
    }
    if (video == null) return null;
    final uri = Uri.tryParse(video);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
    final temporary = File('${folder.path}/$key.partial.jpg');
    final done = Completer<bool>();
    final session = await FFmpegKit.executeWithArgumentsAsync([
      '-y',
      '-nostdin',
      '-rw_timeout',
      '10000000',
      if (headers.isNotEmpty) ...[
        '-headers',
        '${headers.entries.where((e) => !e.key.contains(RegExp(r'[\r\n]')) && !e.value.contains(RegExp(r'[\r\n]'))).map((e) => '${e.key}: ${e.value}').join('\r\n')}\r\n',
      ],
      '-i',
      video,
      '-map',
      '0:v:0',
      '-frames:v',
      '1',
      '-vf',
      'scale=640:-2',
      '-threads',
      '1',
      '-q:v',
      '3',
      temporary.path,
    ], (finished) async {
      final success = ReturnCode.isSuccess(await finished.getReturnCode());
      if (!done.isCompleted) done.complete(success);
    });
    var success = false;
    try {
      success = await done.future.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      await FFmpegKit.cancel(session.getSessionId());
      // Wait for native completion before removing an incomplete output.
      await done.future
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    }
    if (success && await temporary.exists() && await temporary.length() > 0) {
      await temporary.rename(output.path);
      return output.path;
    }
    if (await temporary.exists()) await temporary.delete();
    return null;
  }
}
