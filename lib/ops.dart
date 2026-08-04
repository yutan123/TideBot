import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

class OpsManager {
  static final OpsManager _instance = OpsManager._internal();
  factory OpsManager() => _instance;
  OpsManager._internal();

  static const MethodChannel _nativeChannel = MethodChannel('tidebot.native.channel');
  
  final Record _audioRecorder = Record();
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> init() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/tide_audio_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          path: filePath,
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
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
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    
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