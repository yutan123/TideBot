import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_navigation.dart';
import 'db.dart';
import 'global_notice.dart';
import 'theme.dart';
import 'ui_components.dart';

class OtaUpdate {
  static const _channel = MethodChannel('tidebot.native.channel');
  static const _releaseApi =
      'https://api.github.com/repos/yutan123/TideBot/releases/latest';

  static Future<void> checkOncePerDay() async {
    final db = DBManager();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (await db.getKV('ota_checked_date') == today) return;
    await db.setKV('ota_checked_date', today);
    await _check(showWhenCurrent: false);
  }

  static Future<void> checkNow(BuildContext context) =>
      _check(showWhenCurrent: true, context: context);

  static Future<void> _check({
    required bool showWhenCurrent,
    BuildContext? context,
  }) async {
    try {
      final release = await _latestRelease();
      final version = _releaseVersion(release);
      final installed = (await PackageInfo.fromPlatform()).version;
      if (version.isEmpty || _compare(version, installed) <= 0) {
        if (showWhenCurrent && context != null && context.mounted) {
          GlobalNotice.show('当前已是最新版本');
        }
        return;
      }
      if (await DBManager().getKV('ota_ignored_version') == version &&
          !showWhenCurrent) {
        return;
      }
      final target = context ?? appNavigatorKey.currentContext;
      if (target == null || !target.mounted) return;
      await _showUpdate(target, release, version);
    } catch (error) {
      debugPrint('[ota] check failed: $error');
      if (showWhenCurrent && context != null && context.mounted) {
        GlobalNotice.show('检查更新失败：$error', color: const Color(0xFFE74C3C));
      }
    }
  }

  static Future<Map<String, dynamic>> _latestRelease() async {
    final response = await http.get(
      Uri.parse(_releaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'TideBot',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('GitHub Release HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const FormatException('Release 响应格式错误');
    return Map<String, dynamic>.from(decoded);
  }

  static String _releaseVersion(Map<String, dynamic> release) {
    final raw =
        (release['tag_name'] ?? release['name'] ?? '').toString().trim();
    return raw.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
  }

  static List<String> _apkUrls(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return const [];
    final preferred = <String>[];
    final fallback = <String>[];
    for (final raw in assets.whereType<Map>()) {
      final name = raw['name']?.toString() ?? '';
      final url = raw['browser_download_url']?.toString() ?? '';
      if (!url.startsWith('https://') || !name.toLowerCase().endsWith('.apk')) {
        continue;
      }
      if (name.toLowerCase() == 'tidebot.apk') {
        preferred.add(url);
      } else {
        fallback.add(url);
      }
    }
    return [...preferred, ...fallback];
  }

  static Future<void> _showUpdate(
    BuildContext context,
    Map<String, dynamic> release,
    String version,
  ) async {
    final urls = _apkUrls(release);
    if (urls.isEmpty) {
      GlobalNotice.show('该版本没有 TideBot.apk 安装包',
          color: const Color(0xFFE74C3C));
      return;
    }
    final notes = (release['body']?.toString().trim().isNotEmpty == true)
        ? release['body'].toString().trim()
        : '有新的 TideBot 版本可用。';
    final action = await TideDialogs.show<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = TideTheme.of(ctx);
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: TideDialogs.glassContent(context: ctx, children: [
              Text('发现新版本 $version',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 10),
              Text(notes,
                  style:
                      TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: TideDialogs.glassButton(
                    '忽略此版本',
                    color: theme.buttonSecondary,
                    textColor: theme.textStrong,
                    onTap: () => Navigator.pop(ctx, 'ignore'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TideDialogs.glassButton(
                    '立即更新',
                    onTap: () => Navigator.pop(ctx, 'update'),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
    if (action == 'ignore') {
      await DBManager().setKV('ota_ignored_version', version);
      return;
    }
    if (action != 'update') return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/TideBot.apk');
      await _download(await _rankUrls(urls), file);
      await _channel.invokeMethod('installApk', {'path': file.path});
    } catch (error) {
      if (context.mounted) {
        GlobalNotice.show('更新下载失败：$error', color: const Color(0xFFE74C3C));
      }
    }
  }

  static List<String> _candidateUrls(String url) {
    return {
      url,
      'https://ghproxy.net/$url',
      'https://mirror.ghproxy.com/$url',
      'https://gh-proxy.com/$url',
    }.toList();
  }

  static bool _isValidApkProbe(http.StreamedResponse response) {
    if (response.statusCode != 200 && response.statusCode != 206) return false;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final contentRange = response.headers['content-range'];
    final contentLength =
        int.tryParse(response.headers['content-length'] ?? '');
    // Proxies frequently return an HTML challenge page with HTTP 200. A ranged
    // APK response must either identify an Android archive or carry range data.
    return !contentType.contains('text/html') &&
        (contentType.contains('application/vnd.android.package-archive') ||
            contentType.contains('application/octet-stream') ||
            contentRange != null ||
            (contentLength != null && contentLength >= 4));
  }

  static Future<List<String>> _rankUrls(List<String> urls) async {
    final probes = await Future.wait(
      urls.expand(_candidateUrls).map((url) async {
        final started = DateTime.now();
        final client = http.Client();
        try {
          final response = await client
              .send(http.Request('GET', Uri.parse(url))
                ..headers.addAll({
                  'User-Agent': 'TideBot',
                  'Range': 'bytes=0-3',
                }))
              .timeout(const Duration(seconds: 8));
          final valid = _isValidApkProbe(response);
          await response.stream.drain<void>();
          return (
            url: url,
            valid: valid,
            elapsed: DateTime.now().difference(started)
          );
        } catch (_) {
          return (url: url, valid: false, elapsed: const Duration(days: 1));
        } finally {
          client.close();
        }
      }),
    );
    final valid = probes.where((probe) => probe.valid).toList()
      ..sort((a, b) => a.elapsed.compareTo(b.elapsed));
    return [...valid.map((probe) => probe.url), ...urls];
  }

  static Future<void> _download(List<String> urls, File destination) async {
    final errors = <String>[];
    for (final url in urls) {
      final client = http.Client();
      IOSink? sink;
      try {
        if (await destination.exists()) await destination.delete();
        final request = http.Request('GET', Uri.parse(url))
          ..headers['User-Agent'] = 'TideBot';
        final response =
            await client.send(request).timeout(const Duration(seconds: 30));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          errors.add('$url HTTP ${response.statusCode}');
          continue;
        }
        sink = destination.openWrite(mode: FileMode.writeOnly);
        await response.stream.pipe(sink);
        sink = null;
        final bytes = await destination.readAsBytes();
        if (bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4b &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04) {
          return;
        }
        errors.add('$url 不是有效 APK 文件');
      } catch (error) {
        errors.add('$url $error');
      } finally {
        await sink?.close();
        client.close();
        if (await destination.exists() && await destination.length() == 0) {
          await destination.delete();
        }
      }
    }
    throw HttpException('安装包下载失败：${errors.join('；')}');
  }

  static int _compare(String a, String b) {
    final aa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < (aa.length > bb.length ? aa.length : bb.length); i++) {
      final x = i < aa.length ? aa[i] : 0;
      final y = i < bb.length ? bb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
