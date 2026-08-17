import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceCapabilityService {
  DeviceCapabilityService._();
  static final instance = DeviceCapabilityService._();
  static const _channel = MethodChannel('tidebot.native.channel');

  static const contextFeature = 'extra_context';
  static const proactiveFeature = 'operation_proactive';
  static const controlFeature = 'device_control';

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

  Future<bool> accessibilityEnabled() async {
    final state =
        await _channel.invokeMapMethod<String, dynamic>('accessibilityState');
    return state?['enabled'] == true;
  }

  Future<bool> requestControl({
    required String botId,
    required String action,
    int? x,
    int? y,
    String? text,
    String? packageName,
    String? selector,
  }) async {
    if (!await isAuthorized(controlFeature, botId)) return false;
    if (!(await whitelist(controlFeature)).contains(action)) return false;
    final result =
        await _channel.invokeMethod<bool>('executeAccessibilityAction', {
      'action': action,
      'x': x,
      'y': y,
      'text': text,
      'packageName': packageName,
      'selector': selector,
    });
    return result == true;
  }

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

  String encodeContext(Map<String, dynamic> context) => jsonEncode(context);
}
