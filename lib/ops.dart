import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// 系统底层执行引擎 (ops.dart)
/// 负责所有的硬件调用、文件处理、音视频流、以及与 Android 原生底层的通信
class OpsManager {
  // 单例模式
  static final OpsManager _instance = OpsManager._internal();
  factory OpsManager() => _instance;
  OpsManager._internal();

  // 与 Android 原生底层的通信通道
  static const MethodChannel _nativeChannel = MethodChannel('tidebot.native.channel');
  
  // 录音与播放引擎
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 初始化方法
  Future<void> init() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  // ==========================================
  // 多模态硬件调用：录音与播放 (TTS/STT 支持)
  // ==========================================

  /// 开始流式录音
  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/tide_audio_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
          path: filePath,
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 结束录音并返回文件路径
  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      return path;
    } catch (e) {
      return null;
    }
  }

  /// 播放语音 (TTS结果)
  Future<void> playAudio(String fileUrlOrPath) async {
    try {
      if (fileUrlOrPath.startsWith('http')) {
        await _audioPlayer.play(UrlSource(fileUrlOrPath));
      } else {
        await _audioPlayer.play(DeviceFileSource(fileUrlOrPath));
      }
    } catch (e) {
      print("Audio play error: $e");
    }
  }

  /// 停止播放语音
  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  // ==========================================
  // 文件与图像处理：选择器与 HEIC 适配
  // ==========================================

  /// 选取图片并自动处理 HEIC 转换
  Future<File?> pickAndProcessImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    
    if (image == null) return null;

    String finalPath = image.path;
    final String extension = finalPath.split('.').last.toLowerCase();

    // 严密适配 iOS/Android 高效图片格式
    if (extension == 'heic' || extension == 'heif') {
      final String? jpegPath = await HeifConverter.convert(finalPath);
      if (jpegPath != null) {
        finalPath = jpegPath;
      }
    }

    return File(finalPath);
  }

  /// 选取文档 (支持 txt, md, csv, json)
  Future<File?> pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'json'],
    );

    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  // ==========================================
  // 原生指令与无障碍服务 (Agent 底层触达)
  // ==========================================

  /// 下发系统通知
  Future<void> showSystemNotification({required int id, required String title, required String body}) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'tide_bot_msg', 'TideBot 消息通知',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(id, title, body, platformChannelSpecifics);
  }

  /// 触达 Android 底层 AccessibilityService (无障碍屏幕抓取与操控)
  Future<String> executeAccessibilityCommand(String action, Map<String, dynamic> payload) async {
    try {
      final String result = await _nativeChannel.invokeMethod('executeAccessibilityAction', {
        'action': action,
        'payload': payload,
      });
      return result;
    } on PlatformException catch (e) {
      return "Native Bridge Error: '${e.message}'.";
    }
  }

  /// 设定底层系统闹钟 (真实调用 Android AlarmManager)
  Future<bool> setSystemAlarm(int hour, int minute, String message) async {
    try {
      final bool result = await _nativeChannel.invokeMethod('setAlarmManager', {
        'hour': hour,
        'minute': minute,
        'message': message,
      });
      return result;
    } on PlatformException {
      return false;
    }
  }
}
