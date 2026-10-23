import 'dart:async';
import 'native_background_coordinator.dart';
import 'app_log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps an in-flight UI request eligible for background execution on Android.
/// The native service owns bounded leases, so engine loss cannot leak a service.
class RequestExecutionLease with WidgetsBindingObserver {
  RequestExecutionLease._(this._id);
  static const _channel = MethodChannel('tidebot.native.channel');
  static int _sequence = 0;
  final String? _id;
  Timer? _renewal;
  bool _released = false;
  bool _renewing = false;

  static Future<RequestExecutionLease> acquire() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return RequestExecutionLease._(null);
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'beginRequestExecution',
        {'id': id},
      );
      final lease = RequestExecutionLease._(id);
      WidgetsBinding.instance.addObserver(lease);
      AppLogService.instance.add('REQUEST_PROTECTION',
          '请求后台保护已启动 id=$id foreground=${status?['foreground'] == true}');
      lease._renewal = Timer.periodic(const Duration(minutes: 1), (_) {
        unawaited(lease._renew());
      });
      return lease;
    } on MissingPluginException {
      // Background Flutter engines already run inside their own foreground service.
      return RequestExecutionLease._(null);
    } on PlatformException catch (error) {
      AppLogService.instance.add('REQUEST_PROTECTION_ERROR',
          '请求后台保护启动失败：${error.code} ${error.message}');
      debugPrint(
          'Request protection unavailable: ${error.code} ${error.message}');
      return RequestExecutionLease._(null);
    }
  }

  // Refresh on the lifecycle transition as well as the timer. In particular,
  // resume checks whether Android stopped the service while Flutter was paused.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      unawaited(_renew());
    }
  }

  Future<void> _renew() async {
    if (_released || _renewing || _id == null) return;
    _renewing = true;
    try {
      await _channel.invokeMapMethod<String, dynamic>(
        'renewRequestExecution',
        {'id': _id},
      );
    } catch (error) {
      AppLogService.instance
          .add('REQUEST_PROTECTION_ERROR', '请求后台保护续期失败 id=$_id：$error');
      debugPrint('Request protection renewal failed: $error');
    } finally {
      _renewing = false;
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    WidgetsBinding.instance.removeObserver(this);
    _renewal?.cancel();
    _renewal = null;
    if (_id == null) return;
    try {
      // Persist the next deadline before dropping request protection.
      await NativeBackgroundCoordinator.synchronize()
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Request deadline handoff failed: $error');
    } finally {
      try {
        await _channel.invokeMethod<void>('endRequestExecution', {'id': _id});
        AppLogService.instance.add('REQUEST_PROTECTION', '请求后台保护已释放 id=$_id');
      } catch (error) {
        debugPrint('Request protection release failed: $error');
      }
    }
  }
}
