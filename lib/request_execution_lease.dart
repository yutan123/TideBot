import 'dart:async';
import 'native_background_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps an in-flight UI request eligible for background execution on Android.
/// The native service owns bounded leases, so engine loss cannot leak a service.
class RequestExecutionLease {
  RequestExecutionLease._(this._id);
  static const _channel = MethodChannel('tidebot.native.channel');
  static int _sequence = 0;
  final String? _id;
  Timer? _renewal;
  bool _released = false;

  static Future<RequestExecutionLease> acquire() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return RequestExecutionLease._(null);
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    try {
      await _channel.invokeMethod<void>('beginRequestExecution', {'id': id});
      final lease = RequestExecutionLease._(id);
      lease._renewal = Timer.periodic(const Duration(minutes: 1), (_) async {
        try {
          await _channel
              .invokeMethod<void>('renewRequestExecution', {'id': id});
        } catch (error) {
          debugPrint('Request protection renewal failed: $error');
        }
      });
      return lease;
    } on MissingPluginException {
      // Background Flutter engines already run inside their own foreground service.
      return RequestExecutionLease._(null);
    } on PlatformException catch (error) {
      debugPrint('Request protection unavailable: ${error.code}');
      return RequestExecutionLease._(null);
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
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
      } catch (error) {
        debugPrint('Request protection release failed: $error');
      }
    }
  }
}
