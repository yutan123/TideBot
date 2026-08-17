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

  static const actionPolicyOff = 'off';
  static const actionPolicyAsk = 'ask';
  static const actionPolicyAllow = 'allow';

  Future<String> actionPolicy() async =>
      (await SharedPreferences.getInstance())
          .getString('device_action_policy') ??
      actionPolicyAsk;

  Future<void> setActionPolicy(String value) async {
    if (!const {actionPolicyOff, actionPolicyAsk, actionPolicyAllow}
        .contains(value)) return;
    await (await SharedPreferences.getInstance())
        .setString('device_action_policy', value);
  }

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

  Future<bool> overlayEnabled() async =>
      await _channel.invokeMethod<bool>('overlayEnabled') == true;

  Future<bool> overlayRunning() async =>
      await _channel.invokeMethod<bool>('overlayRunning') == true;

  Future<void> openOverlaySettings() =>
      _channel.invokeMethod<void>('openOverlaySettings');

  Future<bool> setAssistantOverlay({
    required bool enabled,
    String? botId,
    String? botName,
    String? avatarPath,
  }) async =>
      await _channel.invokeMethod<bool>('setAssistantOverlay', {
        'enabled': enabled,
        'botId': botId,
        'botName': botName,
        'avatarPath': avatarPath,
      }) ==
      true;

  String encodeContext(Map<String, dynamic> context) => jsonEncode(context);
}
