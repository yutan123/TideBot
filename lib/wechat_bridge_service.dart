import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';

class WechatBridgeState {
  const WechatBridgeState({
    required this.connected,
    required this.binding,
    required this.botId,
    required this.replyEnabled,
    required this.proactiveSyncEnabled,
    this.qrUrl,
    this.status = '未连接',
  });

  final bool connected;
  final bool binding;
  final String botId;
  final bool replyEnabled;
  final bool proactiveSyncEnabled;
  final String? qrUrl;
  final String status;
}

class WechatBridgeService {
  WechatBridgeService._();
  static final instance = WechatBridgeService._();

  static const _baseUrl = 'https://dns-bottles-labour-oral.trycloudflare.com';
  static const _socketUrl =
      'wss://dns-bottles-labour-oral.trycloudflare.com/v1/socket';
  static const _deviceIdKey = 'openclaw_device_id';
  static const _deviceTokenKey = 'openclaw_device_token';
  static const _expiresAtKey = 'openclaw_expires_at';
  static const _enabledKey = 'wechat_bridge_enabled';
  static const _botIdKey = 'wechat_bridge_bot_id';
  static const _replyEnabledKey = 'wechat_bridge_reply_enabled';
  static const _proactiveSyncKey = 'wechat_bridge_proactive_sync_enabled';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final StreamController<WechatBridgeState> _states =
      StreamController<WechatBridgeState>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  bool _bindingRequested = false;
  bool _authenticated = false;
  bool _binding = false;
  String? _qrUrl;
  String _status = '未连接';

  Stream<WechatBridgeState> get states => _states.stream;

  Future<WechatBridgeState> currentState() async {
    final db = DBManager();
    return WechatBridgeState(
      connected: _socket != null,
      binding: _binding,
      botId: await db.getKV(_botIdKey) ?? '',
      replyEnabled: await db.getKV(_replyEnabledKey) != 'false',
      proactiveSyncEnabled: await db.getKV(_proactiveSyncKey) != 'false',
      qrUrl: _qrUrl,
      status: _status,
    );
  }

  Future<void> configure({
    required String botId,
    required bool replyEnabled,
    required bool proactiveSyncEnabled,
  }) async {
    final db = DBManager();
    await db.setKV(_botIdKey, botId);
    await db.setKV(_replyEnabledKey, '$replyEnabled');
    await db.setKV(_proactiveSyncKey, '$proactiveSyncEnabled');
    await _publish();
  }

  Future<void> connect({bool requestBinding = false}) async {
    _manualDisconnect = false;
    _bindingRequested = requestBinding;
    _authenticated = false;
    _reconnectTimer?.cancel();
    final db = DBManager();
    final botId = await db.getKV(_botIdKey) ?? '';
    if (botId.isEmpty) {
      _status = '请先选择回复机器人';
      await _publish();
      return;
    }
    await db.setKV(_enabledKey, 'true');
    try {
      _status = '正在获取设备凭据';
      await _publish();
      final credentials = await _credentials();
      _status = '正在连接 OpenClaw';
      await _publish();
      await _socketSubscription?.cancel();
      await _socket?.close();
      final socket = await WebSocket.connect(_socketUrl)
          .timeout(const Duration(seconds: 20));
      _socket = socket;
      _socketSubscription = socket.listen(
        _onFrame,
        onDone: _onSocketClosed,
        onError: (Object error, StackTrace stack) => _onSocketError(error),
        cancelOnError: false,
      );
      _send('authenticate', {
        'deviceId': credentials['deviceId'],
        'deviceToken': credentials['deviceToken'],
        'expiresAt': credentials['expiresAt'],
      });
      _status = '已连接，正在认证';
      await _publish();
    } catch (error) {
      _status = '连接失败：$error';
      AppLogService.instance.add('WECHAT', _status);
      await _publish();
      _scheduleReconnect();
    }
  }

  Future<void> startBinding() async {
    _bindingRequested = true;
    if (_socket == null) {
      await connect(requestBinding: true);
      return;
    }
    if (!_authenticated) {
      _status = '等待 OpenClaw 认证完成';
      await _publish();
      return;
    }
    _binding = true;
    _qrUrl = null;
    _status = '正在请求微信绑定二维码';
    _send('bind.start', const <String, dynamic>{});
    await _publish();
  }

  Future<void> disconnect({bool clearCredentials = false}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    await DBManager().setKV(_enabledKey, 'false');
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    _binding = false;
    _qrUrl = null;
    _status = '未连接';
    if (clearCredentials) {
      await _secure.delete(key: _deviceIdKey);
      await _secure.delete(key: _deviceTokenKey);
      await _secure.delete(key: _expiresAtKey);
    }
    await _publish();
  }

  Future<Map<String, dynamic>> _credentials() async {
    final deviceId = await _secure.read(key: _deviceIdKey);
    final token = await _secure.read(key: _deviceTokenKey);
    final expiresAt = await _secure.read(key: _expiresAtKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiry = int.tryParse(expiresAt ?? '') ?? 0;
    if (deviceId?.isNotEmpty == true &&
        token?.isNotEmpty == true &&
        (expiry == 0 || expiry > now + 30000)) {
      return {'deviceId': deviceId, 'deviceToken': token, 'expiresAt': expiry};
    }
    final response = await http.post(
      Uri.parse('$_baseUrl/v1/bootstrap'),
      headers: const {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('bootstrap HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        decoded['deviceId']?.toString().isEmpty != false ||
        decoded['deviceToken']?.toString().isEmpty != false) {
      throw StateError('bootstrap 返回的设备凭据无效');
    }
    final result = <String, dynamic>{
      'deviceId': decoded['deviceId'].toString(),
      'deviceToken': decoded['deviceToken'].toString(),
      'expiresAt': int.tryParse(decoded['expiresAt']?.toString() ?? '') ?? 0,
    };
    await _secure.write(key: _deviceIdKey, value: result['deviceId'] as String);
    await _secure.write(
        key: _deviceTokenKey, value: result['deviceToken'] as String);
    await _secure.write(key: _expiresAtKey, value: '${result['expiresAt']}');
    return result;
  }

  void _send(String type, Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(jsonEncode({
      'type': type,
      'requestId': '${DateTime.now().microsecondsSinceEpoch}-${type.hashCode}',
      if (payload.isNotEmpty) 'payload': payload,
    }));
  }

  Future<void> _onFrame(dynamic raw) async {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final type = decoded['type']?.toString() ?? '';
      final payload = decoded['payload'];
      if (type == 'bind.qr' && payload is Map) {
        _qrUrl = payload['qrUrl']?.toString();
        _binding = _qrUrl?.isNotEmpty == true;
        _status = _binding ? '请使用微信扫码绑定' : '未收到有效二维码';
        await _publish();
        return;
      }
      if (type.contains('bind') &&
          (type.contains('success') ||
              type.contains('bound') ||
              type.contains('complete'))) {
        _binding = false;
        _qrUrl = null;
        _status = '微信已绑定';
        await _publish();
        return;
      }
      if (type == 'wechat.message' && payload is Map) {
        await _replyWechatMessage(Map<String, dynamic>.from(payload));
        return;
      }
      if (type == 'authenticated' || type == 'authenticate.ok') {
        _authenticated = true;
        _status = '已连接';
        await _publish();
        if (_bindingRequested) await startBinding();
      }
    } catch (error) {
      AppLogService.instance.add('WECHAT', '无法处理服务器事件：$error');
    }
  }

  Future<void> _replyWechatMessage(Map<String, dynamic> message) async {
    final db = DBManager();
    if (await db.getKV(_replyEnabledKey) == 'false') {
      AppLogService.instance.add('WECHAT', '收到微信消息，自动回复已关闭');
      return;
    }
    final botId = await db.getKV(_botIdKey) ?? '';
    final text = message['text']?.toString().trim() ?? '';
    final conversationId = message['conversationId']?.toString() ?? '';
    final messageId = message['id']?.toString() ?? '';
    if (botId.isEmpty || text.isEmpty || conversationId.isEmpty) {
      AppLogService.instance.add('WECHAT', '忽略缺少机器人、正文或 conversationId 的微信消息');
      return;
    }
    if (messageId.isNotEmpty &&
        await db.getKV('wechat_message_done_$messageId') == 'true') {
      AppLogService.instance.add('WECHAT', '忽略重复微信消息：$messageId');
      return;
    }
    AppLogService.instance.add('WECHAT', '收到微信消息，交给机器人 $botId 回复');
    final reply = await AIManager()
        .sendMessage(botId: botId, text: text, persistResponse: true);
    final answer = reply['reply']?.toString().trim() ?? '';
    if (reply['success'] != true || answer.isEmpty) {
      AppLogService.instance
          .add('WECHAT', 'AI 回复失败：${reply['error'] ?? '空回复'}');
      return;
    }
    _send('message.send', {'conversationId': conversationId, 'text': answer});
    if (messageId.isNotEmpty) {
      await db.setKV('wechat_message_done_$messageId', 'true');
    }
    AppLogService.instance.add('WECHAT', '已回传微信回复，长度 ${answer.length}');
  }

  void _onSocketError(Object error) {
    _status = '连接异常：$error';
    AppLogService.instance.add('WECHAT', _status);
    _publish();
  }

  void _onSocketClosed() {
    _socket = null;
    _socketSubscription = null;
    if (!_manualDisconnect) {
      _status = '连接已断开，等待重连';
      _publish();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 10), () async {
      _reconnectTimer = null;
      if (await DBManager().getKV(_enabledKey) == 'true') await connect();
    });
  }

  Future<void> restore() async {
    if (await DBManager().getKV(_enabledKey) == 'true') await connect();
  }

  Future<void> _publish() async {
    if (!_states.isClosed) _states.add(await currentState());
  }
}
