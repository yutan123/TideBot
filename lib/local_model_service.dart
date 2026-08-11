import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ops.dart';

/// 全局本地模型下载服务。
///
/// 下载逻辑不挂在某个页面 State 上，而是以单例运行，因此离开「本地模型」页面、
/// 甚至在 APP 前后台切换之间都不会中断；进度通过 [progressNotifier] 暴露给页面
/// 监听，并实时把百分比推送到系统通知栏。
class LocalModelService {
  LocalModelService._internal();
  static final LocalModelService instance = LocalModelService._internal();

  final Map<String, ValueNotifier<double>> _progress = {};
  final Map<String, ValueNotifier<bool>> _downloading = {};
  final Map<String, int> _receivedBytes = {};
  final Map<String, int> _totalBytes = {};
  final Map<String, bool> _cancelRequested = {};
  final Set<String> _completed = {};

  /// 当前已接收字节数（内存值，供前台 UI 实时显示）。
  int receivedBytesOf(String id) => _receivedBytes[id] ?? 0;

  /// 当前总字节数（内存值）。
  int totalBytesOf(String id) => _totalBytes[id] ?? 0;

  /// 每个模型一个进度 notifier（0~1），页面据此刷新 UI。
  ValueNotifier<double> progressNotifier(String id) =>
      _progress.putIfAbsent(id, () => ValueNotifier<double>(0.0));

  /// 每个模型一个下载状态 notifier，供页面订阅以感知后台下载进程。
  ValueNotifier<bool> downloadingNotifier(String id) =>
      _downloading.putIfAbsent(id, () => ValueNotifier<bool>(false));

  bool isDownloading(String id) => _downloading[id]?.value ?? false;

  int _notificationId(String id) => id.hashCode & 0x00FFFFFF;

  Future<void> pauseDownload(String id) async {
    _cancelRequested[id] = true;
    downloadingNotifier(id).value = false;
    await OpsManager().cancelDownloadProgress(_notificationId(id));
  }

  /// 删除模型，同时取消正在进行的下载。
  Future<void> deleteModel(String id) async {
    _cancelRequested[id] = true;
    await OpsManager().cancelDownloadProgress(_notificationId(id));
    final dl = _downloading[id];
    if (dl != null) dl.value = false;

    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/$id.gguf');
    final part = File('${target.path}.part');
    try {
      if (await target.exists()) await target.delete();
      if (await part.exists()) await part.delete();
    } catch (_) {}
    await _clearDownloadState(id);

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
          (key) => key.startsWith('local_chat_model_'),
        )) {
      if (prefs.getString(key) == id) {
        await prefs.remove(key);
      }
    }

    _completed.remove(id);
    final p = _progress[id];
    if (p != null) p.value = 0.0;
    _receivedBytes[id] = 0;
    _totalBytes[id] = 0;
  }

  /// 检查模型是否已安装（真实文件存在且大于 1MB）。
  Future<Map<String, dynamic>> installedState(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/$id.gguf');
    final part = File('${target.path}.part');
    final prefs = await SharedPreferences.getInstance();
    final installed =
        await target.exists() && await target.length() > 1024 * 1024;
    final received = installed
        ? await target.length()
        : (await part.exists() ? await part.length() : 0);
    final savedTotal = prefs.getInt('local_model_total_$id') ?? 0;
    _receivedBytes[id] = received;
    _totalBytes[id] = installed ? received : savedTotal;
    if (!installed && savedTotal > 0) {
      progressNotifier(id).value = (received / savedTotal).clamp(0.0, 1.0);
    }
    return {
      'installed': installed,
      'receivedBytes': received,
      'totalBytes': installed ? received : savedTotal,
      'downloading': _downloading[id]?.value ?? false,
    };
  }

  /// 启动/继续下载。已在下载中则忽略，避免重复；离开页面也不中断。
  Future<void> startDownload({
    required String id,
    required String name,
    required String url,
    void Function(Map<String, dynamic>)? onState,
  }) async {
    if (url.trim().isEmpty) return;
    if (_downloading[id]?.value == true) return;
    _cancelRequested[id] = false;
    final p = progressNotifier(id);
    final dl = downloadingNotifier(id);
    dl.value = true;

    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/$id.gguf');
    final part = File('${target.path}.part');
    var existing = await part.exists() ? await part.length() : 0;
    p.value = 0.0;
    onState?.call({'downloading': true, 'receivedBytes': existing});

    final client = http.Client();
    IOSink? sink;
    var knownTotal = 0; // 仅在拿到响应后才能确定，用于失败续传时保留真实总大小
    int notifId = id.hashCode & 0x00FFFFFF; // 稳定唯一通知 id
    try {
      final routes = <String>[
        url,
        url.replaceFirst('https://huggingface.co/', 'https://hf-mirror.com/'),
        url.replaceFirst('https://huggingface.co/', 'https://hf.co/'),
      ];
      http.StreamedResponse? response;
      final errors = <String>[];
      for (final route in routes.take(3)) {
        for (var attempt = 1; attempt <= 3 && response == null; attempt++) {
          try {
            final request = http.Request('GET', Uri.parse(route));
            if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
            final candidate =
                await client.send(request).timeout(const Duration(minutes: 20));
            if (candidate.statusCode == 200 || candidate.statusCode == 206) {
              response = candidate;
            } else {
              errors.add('$route 第$attempt次 HTTP ${candidate.statusCode}');
              await candidate.stream.drain();
            }
          } catch (e) {
            errors.add('$route 第$attempt次 $e');
          }
        }
        if (response != null) break;
      }
      if (response == null) {
        throw HttpException('三条下载线路均失败（每条已重试三次）：${errors.join('；')}');
      }

      // A server that ignores Range returns 200. Restart safely instead of
      // appending a duplicate file.
      if (existing > 0 && response.statusCode == 200) {
        await part.delete();
        existing = 0;
        final request = http.Request('GET', Uri.parse(url));
        response =
            await client.send(request).timeout(const Duration(minutes: 20));
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('下载服务器返回 HTTP ${response.statusCode}');
      }

      knownTotal = response.contentLength == null
          ? 0
          : existing + response.contentLength!;
      sink =
          part.openWrite(mode: existing > 0 ? FileMode.append : FileMode.write);
      var received = existing;
      var lastPersisted = existing;
      final total = knownTotal;
      p.value = total > 0 ? received / total : 0.0;
      _receivedBytes[id] = received;
      _totalBytes[id] = total;
      onState?.call({
        'receivedBytes': received,
        'totalBytes': total,
        'downloading': true
      });
      await for (final bytes in response.stream) {
        if ((_cancelRequested[id] ?? false) || !(dl.value)) {
          throw const FileSystemException('下载已取消');
        }
        sink.add(bytes);
        received += bytes.length;
        if (received - lastPersisted >= 256 * 1024) {
          lastPersisted = received;
          p.value = total > 0 ? received / total : 0.0;
          _receivedBytes[id] = received;
          _totalBytes[id] = total;
          onState?.call({
            'receivedBytes': received,
            'totalBytes': total,
            'downloading': true
          });
          await _saveDownloadState(id, received, total);
          final percent = total > 0 ? (received * 100 / total).floor() : 0;
          await OpsManager().showDownloadProgress(
              notifId: notifId,
              percent: percent,
              body:
                  '$name · ${_mb(received)} / ${total > 0 ? _mb(total) : '?'} · $percent%',
              done: false);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onState?.call({
        'receivedBytes': received,
        'totalBytes': total,
        'downloading': true
      });

      if (!await part.exists() || await part.length() <= 1024 * 1024) {
        throw const FileSystemException('下载文件过小，已拒绝标记为已安装');
      }
      if (total > 0 && received != total) {
        throw const FileSystemException('下载不完整，将保留进度以便下次继续');
      }
      if (await target.exists()) await target.delete();
      if (await part.exists()) await part.delete();
      await part.rename(target.path);
      await _clearDownloadState(id);
      // 校验下载完成的 GGUF 头部魔数，防止损坏文件被误判为已安装。
      final magicOk = await _hasGgufMagic(target);
      if (!magicOk) {
        try {
          await target.delete();
        } catch (_) {}
        throw const FileSystemException('下载文件头部校验失败，已清理，请重新下载。');
      }
      dl.value = false;
      p.value = 1.0;
      _completed.add(id);
      await OpsManager().showDownloadProgress(
          notifId: notifId,
          percent: 100,
          body: '$name 已下载完成，可随时在聊天中选择使用',
          done: true);
      onState?.call({
        'installed': true,
        'downloading': false,
        'progress': 1.0,
        'receivedBytes': received,
        'totalBytes': received
      });
    } catch (e) {
      await sink?.flush();
      await sink?.close();
      final cancelled = (dl.value != true) || e.toString().contains('取消');
      final received = await part.exists() ? await part.length() : 0;
      if (!cancelled && knownTotal > 0) {
        await _saveDownloadState(id, received, knownTotal);
      }
      dl.value = false;
      if (knownTotal > 0) {
        p.value = (received / knownTotal).clamp(0.0, 1.0);
      }
      if (!cancelled) {
        onState?.call({
          'downloading': false,
          'receivedBytes': received,
          'error': e.toString()
        });
      } else {
        onState?.call({'downloading': false, 'receivedBytes': received});
      }
    } finally {
      client.close();
    }
  }

  Future<void> _saveDownloadState(String id, int received, int total) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_model_received_$id', received);
    if (total > 0) await prefs.setInt('local_model_total_$id', total);
  }

  Future<void> _clearDownloadState(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_model_received_$id');
    await prefs.remove('local_model_total_$id');
  }

  /// 校验 GGUF 文件头部前 4 字节是否为 "GGUF"。
  Future<bool> _hasGgufMagic(File file) async {
    try {
      final raf = await file.open();
      try {
        final head = await raf.read(4);
        return head.length == 4 &&
            head[0] == 0x47 &&
            head[1] == 0x47 &&
            head[2] == 0x55 &&
            head[3] == 0x46;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
