import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android runtime permission gateway.
/// ImagePicker's Android photo picker can work without broad storage access on
/// newer systems, but requesting first keeps the app compatible with devices
/// that still require READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE.
class AppPermissions {
  static Future<bool> photos(BuildContext context,
      {String feature = '选择图片'}) async {
    PermissionStatus status = await Permission.photos.status;
    if (!status.isGranted && !status.isLimited) {
      status = await Permission.photos.request();
    }
    if (status.isGranted || status.isLimited) return true;
    if (!context.mounted) return false;
    _showDenied(context, '需要相册权限才能$feature', status.isPermanentlyDenied);
    return false;
  }

  static Future<bool> microphone(BuildContext context) async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (!context.mounted) return false;
    _showDenied(context, '需要麦克风权限才能录音或通话', status.isPermanentlyDenied);
    return false;
  }

  static Future<bool> notifications(BuildContext context) async {
    var status = await Permission.notification.status;
    if (!status.isGranted) status = await Permission.notification.request();
    if (status.isGranted) return true;
    if (!context.mounted) return false;
    _showDenied(context, '需要通知权限才能接收未读消息和运行状态通知', status.isPermanentlyDenied);
    return false;
  }

  static void _showDenied(
      BuildContext context, String message, bool permanentlyDenied) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(permanentlyDenied ? '$message，请在系统设置中开启' : message,
          style: const TextStyle(fontFamily: 'TideFont')),
      action: permanentlyDenied
          ? SnackBarAction(label: '去设置', onPressed: openAppSettings)
          : null,
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFE74C3C),
    ));
  }
}
