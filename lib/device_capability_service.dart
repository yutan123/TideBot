import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceCapabilityService {
  DeviceCapabilityService._();
  static final instance = DeviceCapabilityService._();
  static const _channel = MethodChannel('tidebot.native.channel');

  static const contextFeature = 'extra_context';
  static const proactiveFeature = 'operation_proactive';

  Future<String?> boundBot(String feature) async =>
      (await SharedPreferences.getInstance()).getString('${feature}_bot_id');

  Future<void> bindBot(String feature, String botId) async {
    await (await SharedPreferences.getInstance())
        .setString('${feature}_bot_id', botId);
  }

  Future<Set<String>> whitelist(String feature) async {
    final values = (await SharedPreferences.getInstance())
            .getStringList('${feature}_whitelist') ??
        const <String>[];
    return values.toSet();
  }

  Future<void> setWhitelist(String feature, Set<String> values) async {
    await (await SharedPreferences.getInstance())
        .setStringList('${feature}_whitelist', values.toList()..sort());
  }

  Future<bool> enabled(String feature) async =>
      (await SharedPreferences.getInstance()).getBool('${feature}_enabled') ??
      false;

  Future<bool> isAuthorized(String feature, String botId) async =>
      await enabled(feature) && await boundBot(feature) == botId;

  Future<Map<String, dynamic>> contextFor(String botId) async {
    if (!await isAuthorized(contextFeature, botId)) return const {};
    final allowed = await whitelist(contextFeature);
    if (allowed.isEmpty) return const {};
    final raw = await _channel.invokeMapMethod<String, dynamic>(
          'deviceContext',
          {'allowed': allowed.toList()},
        ) ??
        const {};
    return Map<String, dynamic>.fromEntries(
      raw.entries.where((entry) => allowed.contains(entry.key)),
    );
  }

  Future<Map<String, dynamic>> accessibilityState() async =>
      await _channel.invokeMapMethod<String, dynamic>('accessibilityState') ??
      const {};

  /// Whether Android has enabled TideBot in Accessibility settings. The native
  /// service may still be reconnecting, so this must not depend only on an
  /// in-process service instance.
  Future<bool> accessibilityEnabled() async {
    final state = await accessibilityState();
    return state['enabled'] == true;
  }

  Future<bool> accessibilityConnected() async {
    final state = await accessibilityState();
    return state['connected'] == true;
  }

  // 手机操控接口已移除。

  Future<Map<String, dynamic>> capabilityState() async =>
      await _channel.invokeMapMethod<String, dynamic>('capabilityState') ??
      const {};

  Future<Map<String, dynamic>> latestDeviceEvent() async =>
      await _channel.invokeMapMethod<String, dynamic>('latestDeviceEvent') ??
      const {};

  Future<List<Map<String, dynamic>>> installedApps() async {
    final raw =
        await _channel.invokeListMethod<dynamic>('installedApps') ?? const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  Future<void> openUsageAccessSettings() =>
      _channel.invokeMethod<void>('openUsageAccessSettings');

  Future<void> openNotificationListenerSettings() =>
      _channel.invokeMethod<void>('openNotificationListenerSettings');

  Future<void> openLocationSettings() =>
      _channel.invokeMethod<void>('openLocationSettings');

  // 悬浮窗接口已移除。

  String encodeContext(Map<String, dynamic> context) => jsonEncode(context);
}
