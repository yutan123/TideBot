import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_navigation.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class OtaUpdate {
  static const _channel = MethodChannel('tidebot.native.channel');
  static const _jsonRoutes = <String>[
    'https://raw.githubusercontent.com/yutan123/TideBot-OTA/main/update.json',
    'https://cdn.jsdelivr.net/gh/yutan123/TideBot-OTA@main/update.json',
    'https://github.com/yutan123/TideBot-OTA/raw/refs/heads/main/update.json',
  ];

  static Future<void> checkOncePerDay() async {
    final db = DBManager();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (await db.getKV('ota_checked_date') == today) return;
    await db.insertKV('ota_checked_date', today);

    try {
      final body = await _getWithRetry(_jsonRoutes);
      final data = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      final remoteVersion = (data['version'] ?? '').toString().trim();
      if (remoteVersion.isEmpty) return;
      final info = await PackageInfo.fromPlatform();
      if (_compare(remoteVersion, info.version) <= 0) return;
      if (await db.getKV('ota_ignored_version') == remoteVersion) return;
      final context = appNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await _showUpdate(context, data, remoteVersion);
    } catch (e) {
      debugPrint('[ota] check failed: $e');
    }
  }

  static Future<void> _showUpdate(
      BuildContext context, Map<String, dynamic> data, String version) async {
    final notes = (data['release_notes'] ?? data['content'] ?? '有新的 TideBot 版本')
        .toString();
    final routes = (data['download_urls'] ?? data['download_links']);
    final urls = routes is List
        ? routes.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    if (urls.isEmpty) return;
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
                    child: TideDialogs.glassButton('忽略此版本',
                        color: theme.buttonSecondary,
                        textColor: theme.textStrong,
                        onTap: () => Navigator.pop(ctx, 'ignore'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TideDialogs.glassButton('立即更新',
                        onTap: () => Navigator.pop(ctx, 'update'))),
              ]),
            ]),
          ),
        );
      },
    );
    if (action == 'ignore') {
      await DBManager().insertKV('ota_ignored_version', version);
      return;
    }
    if (action != 'update') return;
    try {
      final bytes = await _getWithRetry(urls);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tidebot-$version.apk');
      await file.writeAsBytes(bytes, flush: true);
      await _channel.invokeMethod('installApk', {'path': file.path});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新下载失败：$e')));
      }
    }
  }

  static Future<List<int>> _getWithRetry(List<String> urls) async {
    final errors = <String>[];
    for (final url in urls.take(3)) {
      for (var attempt = 1; attempt <= 3; attempt++) {
        final client = http.Client();
        try {
          final response = await client.get(Uri.parse(url), headers: {
            'User-Agent': 'TideBot-OTA'
          }).timeout(const Duration(seconds: 30));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return response.bodyBytes;
          }
          errors.add('$url 第$attempt次 HTTP ${response.statusCode}');
        } catch (e) {
          errors.add('$url 第$attempt次 $e');
        } finally {
          client.close();
        }
      }
    }
    throw HttpException('三条线路均失败（每条已重试三次）：${errors.join('；')}');
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
