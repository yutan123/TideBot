import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import 'app_navigation.dart';

class OpsManager {
  static final OpsManager _instance = OpsManager._internal();
  factory OpsManager() => _instance;
  OpsManager._internal();

  static const MethodChannel _nativeChannel =
      MethodChannel('tidebot.native.channel');

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _notificationInitialization;

  Future<void> init() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  /// Initializes the shared notification plugin once for all message alerts.
  /// The payload is a bot id and is resolved against the database on tap.
  Future<void> initializeNotifications() {
    return _notificationInitialization ??= _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const channel = AndroidNotificationChannel(
      'tide_bot_msg',
      'TideBot 消息通知',
      description: '机器人回复与未读消息提醒',
      importance: Importance.high,
    );
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        openChatFromNotificationPayload(response.payload);
      },
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final launch = await _notifications.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openChatFromNotificationPayload(response.payload);
      });
    }
  }

  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath =
            '${directory.path}/tide_audio_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
          ),
          path: filePath,
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      return path;
    } catch (e) {
      return null;
    }
  }

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

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  Future<File?> pickAndProcessImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (image == null) return null;

    String finalPath = image.path;
    final String extension = finalPath.split('.').last.toLowerCase();

    if (extension == 'heic' || extension == 'heif') {
      final String? jpegPath = await HeifConverter.convert(finalPath);
      if (jpegPath != null) {
        finalPath = jpegPath;
      }
    }

    return File(finalPath);
  }

  Future<File?> pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'json', 'jpg', 'png', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  Future<void> showSystemNotification({
    required int id,
    required String title,
    required String body,
    String? botId,
  }) async {
    await initializeNotifications();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tide_bot_msg',
        'TideBot 消息通知',
        channelDescription: '机器人回复与未读消息提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _notifications.show(id, title, body, details, payload: botId);
  }

  /// 本地模型下载：在通知栏展示带百分比的进度（可平滑更新），下载完成后常驻提示。
  /// 与聊天通知共用消息通道，payload 为空即可，点击不跳转。
  Future<void> showDownloadProgress({
    required int notifId,
    required int percent,
    required String body,
    required bool done,
    String botId = '',
  }) async {
    await initializeNotifications();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tide_bot_msg',
        'TideBot 消息通知',
        channelDescription: '机器人回复与未读消息提醒',
        importance: Importance.high,
        priority: Priority.high,
        onlyAlertOnce: true,
        showProgress: !done,
        progress: percent.clamp(0, 100),
        maxProgress: 100,
        indeterminate: false,
        ongoing: !done,
        autoCancel: done,
        visibility: NotificationVisibility.public,
      ),
    );
    await _notifications.show(notifId, done ? '下载完成' : '本地模型下载中', body, details,
        payload: botId);
  }

  Future<String> executeAccessibilityCommand(
      String action, Map<String, dynamic> payload) async {
    try {
      final String result =
          await _nativeChannel.invokeMethod('executeAccessibilityAction', {
        'action': action,
        'payload': payload,
      });
      return result;
    } on PlatformException catch (e) {
      return "Native Bridge Error: '${e.message}'.";
    }
  }

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
