import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'global_notice.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'db.dart';
import 'ai.dart';
import 'ui_components.dart';
import 'theme.dart';
import 'app_permissions.dart';
import 'media_preprocessor.dart';
// Device control has been removed; device context remains in the AI layer.
import 'emotion_state_service.dart';
import 'ui_call.dart';

class ChatRoomPage extends StatefulWidget {
  final Map<String, dynamic> botData;
  const ChatRoomPage({super.key, required this.botData});
  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _msgC = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollC = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  bool _isRecording = false;
  bool _loading = false;
  bool _typing = false;
  bool _msgsLoading = true;
  final AudioRecorder _rec = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<Duration>? _audioDurationSub;
  StreamSubscription<PlayerState>? _audioStateSub;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  String? _playingAudioPath;
  bool _audioPlaying = false;
  Timer? _recTimer;
  int _recSecs = 0;
  String? _customBg;
  bool _showMessageTime = true;
  bool _showChatAvatar = false;
  bool _showSearchSources = false;
  late Map<String, dynamic> _bot;

  late AnimationController _bottomBarCtrl;
  bool _hasText = false;
  // Attachments are staged above the composer and sent together on confirmation.
  final List<String> _pendingImages = [];
  final List<String> _pendingDocuments = [];
  String? _pendingMediaContext;

  // ===== 防抖/合并：请求代次 + 待重发队列 =====
  // 用户连续发送多条时，递增代次让在途请求的渲染结果作废，并把新文本并入
  // 队列；旧请求返回后若代次过期则拦截，再由 finally 用合并文本统一重发。
  int _requestGen = 0;
  String _queuedText = '';
  bool _queued = false;

  void _msgChanged() {
    if (mounted) setState(() => _hasText = _msgC.text.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bot = Map.from(widget.botData);
    unawaited(DBManager().markBotRead(_bot['id']?.toString() ?? ''));
    _msgC.addListener(_msgChanged);
    _inputFocus.addListener(_handleInputFocus);
    _audioPositionSub = _player.onPositionChanged.listen((v) {
      if (!mounted) return;
      setState(() => _audioPosition = v);
    });
    _audioDurationSub = _player.onDurationChanged.listen((v) {
      if (!mounted) return;
      setState(() => _audioDuration = v);
    });
    _audioStateSub = _player.onPlayerStateChanged.listen((v) {
      if (!mounted) return;
      setState(() {
        _audioPlaying = v == PlayerState.playing;
        if (v == PlayerState.completed) {
          _audioPlaying = false;
          _playingAudioPath = null;
          _audioPosition = Duration.zero;
          _audioDuration = Duration.zero;
        }
      });
    });
    _loadMsgs();
    _messageSyncTimer = Timer.periodic(
        const Duration(seconds: 4), (_) => _syncLatestMessages());
    _loadBg();
    _loadChatPreferences();
    // Proactive replies are scheduled by the persistent background service.
    // The chat page only refreshes persisted results.

    // 底部栏动画控制器
    _bottomBarCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200)); // 减慢动画速度
    // 首帧后启动进场动画，否则 SlideTransition 会一直停在向下偏移 25% 的位置，
    // 这就是输入框一直偏下、"怎么调 padding 都不动"的根因。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bottomBarCtrl.forward();
    });
  }

  @override
  void dispose() {
    unawaited(DBManager().markBotRead(_bot['id']?.toString() ?? ''));
    WidgetsBinding.instance.removeObserver(this);
    _messageSyncTimer?.cancel();
    _streamDisplayTimer?.cancel();
    _deferredPersistedMessageIds.clear();
    _msgC.removeListener(_msgChanged);
    _inputFocus.removeListener(_handleInputFocus);
    _inputFocus.dispose();
    _msgC.dispose();
    _scrollC.dispose();
    _rec.dispose();
    _audioPositionSub?.cancel();
    _audioDurationSub?.cancel();
    _audioStateSub?.cancel();
    _player.dispose();
    _recTimer?.cancel();
    _bottomBarCtrl.dispose(); // 添加动画控制器释放
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncLatestMessages();
      return;
    }
    // Typewriter animation belongs to the visible chat only. The complete reply
    // is already persisted, so leaving the app stops animation and the next
    // foreground sync adopts the final rows directly.
    _streamDisplayTimer?.cancel();
    _streamDisplayTimer = null;
    _deferredPersistedMessageIds.clear();
  }

  void _loadBg() async {
    final prefs = await SharedPreferences.getInstance();
    final bg = prefs.getString('chat_bg_${_bot['id']}');
    if (mounted) setState(() => _customBg = bg);
  }

  void _loadChatPreferences() async {
    final db = DBManager();
    final showTime = await db.getKV('show_message_time');
    final showAvatar = await db.getKV('show_chat_avatar');
    final showSources = await db.getKV('show_web_search_sources');
    if (mounted) {
      setState(() {
        _showMessageTime = showTime != 'false';
        _showChatAvatar = showAvatar == 'true';
        _showSearchSources = showSources == 'true';
      });
    }
  }

  void _loadMsgs() async {
    final revision = _messagesRevision;
    print('_loadMsgs called with bot ID: ${_bot['id']}');
    try {
      final db = DBManager();
      // 不要用 limit 截断历史：导出记录里明明存在，但前端只加载最近 100 条，
      // 导致打开长聊天后大量消息“消失”。这里拿全量，UI 侧用 reverse 只渲染最近一段。
      final msgs = await db.queryMessages(_bot['id'] as String);
      // 引用功能已废弃：不再为 reply_to_id 逐条补查历史消息，避免打开长聊天时
      // 触发大量顺序数据库查询并造成列表首帧卡顿。
      print('_loadMsgs success: got ${msgs.length} messages');
      // 初始数据库查询可能在用户已发送消息后才返回。不能直接覆盖 _msgs，      // 否则刚刚上屏的用户气泡会被旧查询结果抹掉，界面只剩“正在输入中”。
      if (mounted && revision == _messagesRevision) {
        setState(() {
          final byId = <String, Map<String, dynamic>>{
            for (final m in msgs)
              m['id']?.toString() ?? 'db_${m['timestamp']}': m,
          };
          for (final m in _msgs) {
            byId.putIfAbsent(
                m['id']?.toString() ?? 'local_${m['timestamp']}', () => m);
          }
          _msgs = byId.values.toList()
            ..sort((a, b) => ((a['timestamp'] as int?) ?? 0)
                .compareTo((b['timestamp'] as int?) ?? 0));
          _msgsLoading = false;
        });
      }
    } catch (e) {
      print('_loadMsgs error: $e');
      if (mounted) setState(() => _msgsLoading = false);
    }
    // The list uses reverse layout, so its initial scroll position is already at
    // the newest message. Do not schedule a visible post-frame jump here.
  }

  void _handleInputFocus() {
    if (!_inputFocus.hasFocus) return;
    // 等键盘 inset 完成布局后再定位，末条消息会和输入栏一起露出，且不触发进场跳动。
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (mounted && _inputFocus.hasFocus) _scrollDown(animated: false);
    });
  }

  void _scrollDown({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollC.hasClients) return;
      final target = _scrollC.position.minScrollExtent;
      if (animated) {
        _scrollC.animateTo(target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic);
      } else {
        _scrollC.jumpTo(target);
      }
    });
  }

  Timer? _streamDisplayTimer;
  Timer? _messageSyncTimer;
  int _messagesRevision = 0;
  // IDs already persisted for the current foreground reply but not yet owned by
  // a visible bubble. The periodic database refresh must not append them early.
  final Set<String> _deferredPersistedMessageIds = <String>{};

  Future<void> _syncLatestMessages() async {
    if (!mounted || _loading) return;
    try {
      final botId = _bot['id']?.toString() ?? '';
      if (botId.isEmpty) return;
      final revision = _messagesRevision;
      final fresh = await DBManager().queryMessages(botId);
      if (!mounted || revision != _messagesRevision) return;
      final freshById = <String, Map<String, dynamic>>{
        for (final message in fresh) message['id']?.toString() ?? '': message,
      };
      final existingIds = <String>{
        for (final message in _msgs) message['id']?.toString() ?? '',
      };
      final additions = fresh.where((message) {
        final id = message['id']?.toString() ?? '';
        return !existingIds.contains(id) &&
            !_deferredPersistedMessageIds.contains(id);
      }).toList();
      var changed = false;
      setState(() {
        for (final message in _msgs) {
          final replacement = freshById[message['id']?.toString()];
          if (replacement != null &&
              message['is_streaming'] != true &&
              replacement['content']?.toString() !=
                  message['content']?.toString()) {
            message['content'] = replacement['content'];
            changed = true;
          }
        }
        if (additions.isNotEmpty) {
          _msgs.addAll(additions);
          _msgs.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0)
              .compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
          changed = true;
        }
      });
      if (changed) _scrollDown(animated: false);
      await DBManager().markBotRead(botId);
    } catch (_) {}
  }

  /// 分段回复的句间自然等待。
  /// 基础延迟固定 500–1000ms（每句随机，模拟真人打字/阅读节奏）。
  /// 若用户在设置中开启了全局随机延迟（random_reply_delay_enabled），则在
  /// 基础延迟之上再叠加一段自定义随机延迟。
  Future<void> _applyRandomReplyDelay(DBManager db) async {
    // 基础分段延迟：500–1000ms。
    final baseMs = 500 + DateTime.now().microsecond.remainder(1000 - 500 + 1);
    var totalMs = baseMs;
    final enabled = await db.getKV('random_reply_delay_enabled') == 'true';
    if (enabled) {
      var minS = int.tryParse(
              await db.getKV('random_reply_delay_min_seconds') ?? '') ??
          0;
      var maxS = int.tryParse(
              await db.getKV('random_reply_delay_max_seconds') ?? '') ??
          2;
      final extraMin = (minS.clamp(0, 60)) * 1000;
      var extraMax = (maxS.clamp(minS, 60)) * 1000;
      if (extraMax < extraMin) extraMax = extraMin;
      final extraDelay = extraMin +
          DateTime.now().microsecond.remainder(extraMax - extraMin + 1);
      totalMs += extraDelay;
    }
    if (totalMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: totalMs));
    }
  }

  bool get _hasBg => _customBg != null && _customBg!.isNotEmpty;

  // The persistent Android service is the sole proactive scheduler. The chat
  // page only clears the unanswered counter after an actual user interaction.
  void _onUserInteracted() {
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isNotEmpty) {
      unawaited(DBManager().setKV('proactive_unanswered_$botId', '0'));
    }
  }

  // 手机操控确认流程已移除。

  // ========== 发送消息 ==========
  Future<void> _send({
    List<String>? images,
    List<String>? documents,
    String? mediaContext,
    bool forceSingleReply = false,
    // 合并防抖重发时置 true：不再新增用户气泡/入库，仅用当前文本向模型统一请求。
    bool noUserBubble = false,
  }) async {
    final text = _msgC.text.trim();
    images ??= List<String>.from(_pendingImages);
    documents ??= List<String>.from(_pendingDocuments);
    mediaContext ??= _pendingMediaContext;
    if (text.isEmpty &&
        images.isEmpty &&
        documents.isEmpty &&
        mediaContext == null) {
      if (mounted) setState(() => _hasText = false);
      return;
    }
    final botId = _bot['id']?.toString() ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final userMessages = _buildAttachmentMessages(
      botId: botId,
      timestamp: now,
      text: text,
      images: images,
      documents: documents,
    );

    // 用户主动发言：清零主动回复未应答计数并重置计时。
    _onUserInteracted();
    unawaited(EmotionStateService.instance.observeUserMessage(botId, text));

    // ===== 防抖/合并 =====
    // 上一条请求还在飞（机器人尚未回完）时再发消息：不再像旧实现那样直接丢弃，
    // 而是作废在途请求的渲染（_requestGen++），把新文本并入待重发队列，先上屏
    // 气泡并入库存档；等旧请求 finally 结束后用合并文本统一重发一次。
    if (_loading) {
      final queuedMessages = userMessages;
      if (_queued) {
        // 已有待重发队列，合并进同一批文本，避免产生多余第三次请求。
        final prev = _queuedText;
        _queuedText =
            text.isEmpty ? prev : (prev.isEmpty ? text : '$prev\n$text');
      } else {
        _queuedText = text;
      }
      _queued = true;
      _requestGen++; // 作废在途请求的渲染结果
      if (mounted) {
        setState(() {
          _msgs.addAll(queuedMessages);
          _msgC.clear();
          _hasText = false;
        });
        _scrollDown();
      }
      try {
        for (final queuedMessage in queuedMessages) {
          await DBManager().insertMessage({
            'id': queuedMessage['id'],
            'bot_id': botId,
            'role': 'user',
            'type': queuedMessage['type'],
            'content': queuedMessage['content'],
            'file_path': queuedMessage['file_path'],
            'mood': null,
            'timestamp': queuedMessage['timestamp'],
          }).timeout(const Duration(seconds: 12));
        }
      } catch (e) {
        debugPrint('[send] persist queued user message failed: $e');
      }
      return;
    }

    // 本次请求的代次快照；若请求期间用户又发了新消息（_requestGen 变化），
    // 渲染前检测到过期则拦截本次结果，交由 finally 用合并文本统一重发。
    final myGen = _requestGen;
    // 被合并拦截的过期请求不再落库，避免聊天记录顺序混乱。
    final persistThisReply = myGen == _requestGen;

    final msg = userMessages.first;
    if (!noUserBubble) {
      setState(() {
        _loading = true;
        _typing = true;
        _msgsLoading = false;
        _msgs.addAll(userMessages);
        _msgC.clear();
        _pendingImages.clear();
        _pendingDocuments.clear();
        _pendingMediaContext = null;
        _hasText = false;
      });
    } else if (mounted) {
      setState(() {
        _loading = true;
        _typing = true;
        _msgsLoading = false;
        _msgC.clear();
        _hasText = false;
      });
    }
    _scrollDown();

    try {
      if (!noUserBubble) {
        try {
          // chat_history 的真实字段是 type / file_path，不能把 UI 专用 image
          // 字段直接写库；否则 SQLite 会因“no column named image”静默失败。
          for (final userMessage in userMessages) {
            await DBManager().insertMessage({
              'id': userMessage['id'],
              'bot_id': botId,
              'role': 'user',
              'type': userMessage['type'],
              'content': userMessage['content'],
              'file_path': userMessage['file_path'],
              'mood': null,
              'timestamp': userMessage['timestamp'],
            }).timeout(const Duration(seconds: 12));
          }
        } catch (e) {
          debugPrint('[send] persist user message failed: $e');
        }
      }
      final cm = _bot['chat_model']?.toString().trim() ?? '';
      if (cm.isEmpty) {
        final providers = await DBManager().queryChatProviders();
        if (providers.isEmpty) {
          throw StateError('未配置聊天模型，请先在 API 设置中添加远程模型');
        }
      }

      final documentNotices = <String>[];
      for (final path in documents) {
        documentNotices.add(await MediaPreprocessor().documentText(path));
      }
      final attachmentNotice =
          documentNotices.isEmpty ? null : documentNotices.join('\n\n');
      final preparedContext = mediaContext ?? attachmentNotice;
      final modelText = preparedContext == null
          ? text
          : (text.isEmpty ? preparedContext : '$text\n$preparedContext');

      // AIManager reads persisted, role-typed chat_history itself. _msgs contains
      // stream placeholders and animation-only segments, so it must not be reused
      // as a model transcript.
      debugPrint('[send] request start bot=$botId model=$cm');
      final db = DBManager();
      final streamEnabled = (await db.getKV('streaming_output')) != 'false';
      Map<String, dynamic>? streamingMessage;
      var pendingDisplay = '';
      if (streamEnabled && mounted) {
        streamingMessage = <String, dynamic>{
          'id': 'stream_${DateTime.now().millisecondsSinceEpoch}',
          'bot_id': botId,
          'role': 'assistant',
          'type': 'text',
          'content': '',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_streaming': true,
        };
        final speed =
            (int.tryParse(await DBManager().getKV('streaming_speed') ?? '') ??
                    50)
                .clamp(1, 100);
        // 50 is deliberately readable: roughly 14 characters per second, not a full sentence in one second.
        final interval = Duration(milliseconds: 8 + ((100 - speed) * 2));
        final batch = (speed >= 85 ? 2 : 1);
        _streamDisplayTimer?.cancel();
        final displayMessage = streamingMessage;
        _streamDisplayTimer = Timer.periodic(interval, (_) {
          if (!mounted || pendingDisplay.isEmpty) return;
          final take =
              pendingDisplay.length < batch ? pendingDisplay.length : batch;
          final chunk = pendingDisplay.substring(0, take);
          pendingDisplay = pendingDisplay.substring(take);
          setState(() =>
              displayMessage['content'] = '${displayMessage['content']}$chunk');
          // Do not animate on every streamed chunk: repeated animateTo calls
          // cause layout churn, dropped frames and heat during long replies.
          if (pendingDisplay.isEmpty ||
              displayMessage['content'].toString().length % 80 < batch) {
            _scrollDown(animated: false);
          }
        });
        setState(() => _msgs.add(streamingMessage!));
      }
      // Remote provider cold starts and tool calls can legitimately exceed 30 seconds.
      const requestTimeout = Duration(minutes: 2);
      final result = await AIManager()
          .sendMessage(
            botId: botId,
            text: modelText,
            imagePaths: images,
            persistResponse: persistThisReply,
            forceSingleReply: forceSingleReply,
            onDelta: null,
          )
          .timeout(requestTimeout);

      if (result['success'] != true) {
        _streamDisplayTimer?.cancel();
        _streamDisplayTimer = null;
        if (streamingMessage != null && mounted) {
          setState(() => _msgs.remove(streamingMessage));
        }
        final errorText = result['error']?.toString() ?? '模型请求失败，请检查配置和网络';
        final errorLog = result['error_log']?.toString() ?? errorText;
        if (!noUserBubble) {
          msg['error_log'] = errorLog;
          msg['error_code'] = result['error_code']?.toString();
          msg['error_text'] = errorText;
        }
        if (mounted) setState(() {});
        if (!noUserBubble) {
          try {
            await DBManager()
                .updateMessageError(
                  msg['id'].toString(),
                  errorLog: errorLog,
                  errorCode: result['error_code']?.toString(),
                  errorMessage: errorText,
                )
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
        return;
      }

      if (result['silent'] == true) {
        _streamDisplayTimer?.cancel();
        _streamDisplayTimer = null;
        if (streamingMessage != null && mounted)
          setState(() => _msgs.remove(streamingMessage));
        return;
      }
      final persisted = (result['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((message) => Map<String, dynamic>.from(message))
          .toList();
      final audioReply = result['audio_path']?.toString().isNotEmpty == true;
      final animate = streamEnabled && !audioReply && persisted.isNotEmpty;
      final persistedIds = persisted
          .map((message) => message['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      _deferredPersistedMessageIds.addAll(persistedIds);
      if (myGen != _requestGen) {
        _deferredPersistedMessageIds.removeAll(persistedIds);
        if (streamingMessage != null && mounted) {
          setState(() => _msgs.remove(streamingMessage));
        }
        return;
      }

      Future<void> reveal(Map<String, dynamic> row) async {
        if (!mounted || myGen != _requestGen) return;
        if (!animate || row['type'] != 'text') {
          setState(() => _msgs.add(row));
          _scrollDown();
          return;
        }
        final bubble = Map<String, dynamic>.from(row)..['content'] = '';
        bubble['is_streaming'] = true;
        setState(() => _msgs.add(bubble));
        final complete = row['content']?.toString() ?? '';
        var offset = 0;
        final speed =
            (int.tryParse(await db.getKV('streaming_speed') ?? '') ?? 50)
                .clamp(1, 100);
        final interval = Duration(milliseconds: 8 + ((100 - speed) * 2));
        final batch = speed >= 85 ? 2 : 1;
        final done = Completer<void>();
        _streamDisplayTimer?.cancel();
        _streamDisplayTimer = Timer.periodic(interval, (timer) {
          if (!mounted || myGen != _requestGen) {
            timer.cancel();
            if (!done.isCompleted) done.complete();
            return;
          }
          if (offset >= complete.length) {
            timer.cancel();
            bubble.remove('is_streaming');
            if (!done.isCompleted) done.complete();
            return;
          }
          final end = (offset + batch).clamp(0, complete.length);
          setState(() => bubble['content'] = complete.substring(0, end));
          offset = end;
          if (offset % 80 < batch || offset == complete.length) {
            _scrollDown(animated: false);
          }
        });
        await done.future;
      }

      if (streamingMessage != null && mounted) {
        setState(() => _msgs.remove(streamingMessage));
      }
      for (var index = 0; index < persisted.length; index++) {
        if (index > 0 && persisted[index]['reply_group_id'] != null) {
          await _applyRandomReplyDelay(db);
        }
        await reveal(persisted[index]);
      }
      _deferredPersistedMessageIds.removeAll(persistedIds);
      // Images and stickers are included in `messages` after being persisted by
      // AIManager. Rendering result metadata again would duplicate the same
      // media in the visible conversation.
      if (mounted) unawaited(DBManager().markBotRead(botId));
    } catch (e, st) {
      debugPrint('[send] failed: $e');
      debugPrint(st.toString());
      final errorText = '请求处理失败：${e.toString()}';
      final errorLog = '${e.toString()}\n${st.toString()}';
      if (!noUserBubble) {
        msg['error_log'] = errorLog;
        msg['error_code'] = 'local';
        msg['error_text'] = errorText;
      }
      if (mounted) setState(() {});
      if (!noUserBubble) {
        try {
          await DBManager()
              .updateMessageError(
                msg['id'].toString(),
                errorLog: errorLog,
                errorCode: 'local',
                errorMessage: errorText,
              )
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _typing = false;
        });
        _scrollDown();
      }
      // ===== 防抖/合并：统一重发 =====
      // 请求期间用户又发了消息被并入 _queuedText。等待队列后，用合并后的完整
      // 文本向模型统一请求一次，不再新增用户气泡（用户消息已各自上屏入库）。
      if (_queued && _queuedText.trim().isNotEmpty && mounted) {
        final mergedText = _queuedText;
        _queuedText = '';
        _queued = false;
        _msgC.text = mergedText;
        _requestGen++; // 维持最新代次，使本次重发为唯一有效请求
        await _send(noUserBubble: true);
      }
    }
  }

  Future<void> _retryMessage(Map<String, dynamic> message) async {
    if (_loading) return;
    final text = message['content']?.toString().trim() ?? '';
    if (text.isEmpty) return;
    message.remove('error_log');
    message.remove('error_code');
    message.remove('error_message');
    message.remove('error_text');
    await DBManager().clearMessageError(message['id'].toString());
    if (!mounted) return;
    setState(() {
      _msgC.text = text;
      _hasText = true;
    });
    await _send(noUserBubble: true);
  }

  List<Map<String, dynamic>> _buildAttachmentMessages({
    required String botId,
    required int timestamp,
    required String text,
    required List<String> images,
    required List<String> documents,
  }) {
    final attachments = <Map<String, String>>[
      for (final path in images) {'type': 'image', 'path': path},
      for (final path in documents) {'type': 'document', 'path': path},
    ];
    if (attachments.isEmpty) {
      return [
        {
          'id': 'm_$timestamp',
          'bot_id': botId,
          'role': 'user',
          'type': 'text',
          'content': text,
          'file_path': null,
          'timestamp': timestamp,
        }
      ];
    }
    return [
      for (var index = 0; index < attachments.length; index++)
        {
          'id': 'm_$timestamp' '_$index',
          'bot_id': botId,
          'role': 'user',
          'type': attachments[index]['type'],
          // Keep user text exactly once so history and model context do not repeat it.
          'content': index == 0 ? text : '',
          'file_path': attachments[index]['path'],
          'document_name': attachments[index]['type'] == 'document'
              ? attachments[index]['path']!.split(Platform.pathSeparator).last
              : null,
          'timestamp': timestamp + index,
        }
    ];
  }

  Future<void> _transcribeRecordedAudio(
    Map<String, dynamic> message,
    String audioPath,
  ) async {
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isEmpty || _loading) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _typing = true;
      });
      _scrollDown();
    }

    try {
      final transcript = await AIManager()
          .transcribeAudio(botId: botId, audioPath: audioPath)
          .timeout(const Duration(seconds: 50), onTimeout: () => null);
      final modelContext = transcript == null || transcript.trim().isEmpty
          ? '[用户发送了一段语音，但当前未配置可用的语音识别服务或转写失败。你听不到具体内容，请自然说明并结合上下文回应，可以请用户重发或改用文字；不要假装听懂。]'
          : '[用户刚发送的语音转写]\n${transcript.trim()}';

      if (transcript != null && transcript.trim().isNotEmpty) {
        try {
          await DBManager().updateMessageContent(
              message['id'].toString(), transcript.trim());
          if (mounted) setState(() => message['content'] = transcript.trim());
        } catch (e) {
          debugPrint('[stt] persist transcript failed: $e');
        }
      }
      if (mounted) setState(() => _loading = false);
      // The audio message has already been persisted and rendered. Send only
      // the transcript as model context so no duplicate document bubble exists.
      await _send(
        mediaContext: modelContext,
        noUserBubble: true,
        forceSingleReply: true,
      );
    } finally {
      if (mounted && !_loading) setState(() => _typing = false);
    }
  }

  // ========== 录音 ==========
  Future<void> _toggleRec() async {
    try {
      if (_isRecording) {
        _recTimer?.cancel();
        final duration = _recSecs;
        final path = await _rec.stop();
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recSecs = 0;
          });
        }
        if (path != null && path.isNotEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final m = <String, dynamic>{
            'id': 'm_$now',
            'bot_id': _bot['id'],
            'role': 'user',
            'type': 'audio',
            'content': '',
            'audio': path,
            'file_path': path,
            'mood': null,
            'duration': duration,
            'timestamp': now,
          };
          try {
            await DBManager().insertMessage({
              'id': m['id'],
              'bot_id': m['bot_id'],
              'role': 'user',
              'type': 'audio',
              'content': '',
              'file_path': path,
              'mood': null,
              'duration': duration,
              'timestamp': now,
            }).timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('[record] persist failed: $e');
          }
          if (mounted) {
            setState(() => _msgs.add(m));
            _scrollDown();
          }
          // A missing/failed STT setup simply leaves a playable audio message.
          unawaited(_transcribeRecordedAudio(m, path));
        }
        return;
      }

      if (!await AppPermissions.microphone(context)) return;

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 128000,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() => _isRecording = true);
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted && _isRecording) {
          setState(() => _recSecs++);
        } else {
          t.cancel();
        }
      });
    } catch (e, st) {
      debugPrint('[record] failed: $e');
      debugPrint(st.toString());
      _recTimer?.cancel();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recSecs = 0;
        });
        GlobalNotice.show('[X] 录音不可用：$e', color: const Color(0xFFE74C3C));
      }
    }
  }

  Future<void> _sendPickedAudio(String path) async {
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isEmpty || _loading) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final message = <String, dynamic>{
      'id': 'm_$now',
      'bot_id': botId,
      'role': 'user',
      'type': 'audio',
      'content': '',
      'audio': path,
      'file_path': path,
      'mood': null,
      'duration': 0,
      'timestamp': now,
    };
    try {
      await DBManager().insertMessage({
        'id': message['id'],
        'bot_id': botId,
        'role': 'user',
        'type': 'audio',
        'content': '',
        'file_path': path,
        'mood': null,
        'duration': 0,
        'timestamp': now,
      }).timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() => _msgs.add(message));
        _scrollDown();
      }
      // Files chosen from the picker follow the same presentation path as
      // recordings: the source audio is never rendered as a document bubble.
      unawaited(_transcribeRecordedAudio(message, path));
    } catch (e) {
      debugPrint('[audio] persist selected file failed: $e');
      if (mounted) GlobalNotice.show('发送音频失败', color: const Color(0xFFE74C3C));
    }
  }

  // ========== 选择图片/文件 ==========
  void _pickMedia() async {
    final r = await showTideSheet<String>(
        context: context,
        height: 180,
        child: Column(children: [
          const SizedBox(height: 10),
          ListTile(
              leading: Icon(Icons.photo_library_rounded,
                  color: TideTheme.of(context).primary),
              title: const Text('相册', style: TextStyle(fontFamily: 'TideFont')),
              onTap: () => Navigator.pop(context, 'img')),
          ListTile(
              leading: Icon(Icons.insert_drive_file_rounded,
                  color: TideTheme.of(context).primary),
              title: const Text('文件', style: TextStyle(fontFamily: 'TideFont')),
              onTap: () => Navigator.pop(context, 'file')),
        ]));
    if (r == 'img') {
      if (!await AppPermissions.photos(context, feature: '选择图片')) return;
      final selected = await ImagePicker().pickMultiImage();
      if (selected.isNotEmpty) {
        final fixed = <String>[];
        for (final image in selected) {
          fixed.add(await _fixHeic(image.path));
        }
        if (mounted) setState(() => _pendingImages.addAll(fixed));
      }
    } else if (r == 'file') {
      try {
        await Permission.storage.request();
      } catch (_) {}
      final fp = await FilePicker.platform.pickFiles(allowMultiple: true);
      final paths = fp?.files
              .map((file) => file.path)
              .whereType<String>()
              .where((path) => path.isNotEmpty)
              .toList() ??
          const <String>[];
      if (paths.isEmpty) return;
      final stagedImages = <String>[];
      final stagedDocuments = <String>[];
      for (final path in paths) {
        final extension = path.split('.').last.toLowerCase();
        const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
        const audioExtensions = {'m4a', 'mp3', 'wav', 'aac', 'ogg', 'opus'};
        if (imageExtensions.contains(extension)) {
          stagedImages.add(path);
        } else if (audioExtensions.contains(extension)) {
          await _sendPickedAudio(path);
        } else {
          stagedDocuments.add(path);
        }
      }
      if (mounted && (stagedImages.isNotEmpty || stagedDocuments.isNotEmpty)) {
        setState(() {
          _pendingImages.addAll(stagedImages);
          _pendingDocuments.addAll(stagedDocuments);
        });
      }
    }
  }

  Future<String> _fixHeic(String path) async {
    final l = path.toLowerCase();
    if (l.endsWith('.heic') || l.endsWith('.heif')) {
      try {
        final converted = await HeifConverter.convert(path);
        if (converted != null) return converted;
      } catch (_) {}
    }
    return path;
  }

  // ========== 图片预览 ==========
  Future<void> _saveImageToGallery(String path) async {
    try {
      final permission = await Permission.photos.request();
      if (!permission.isGranted && !permission.isLimited) {
        GlobalNotice.show('没有相册保存权限');
        return;
      }
      final dir = Directory('/storage/emulated/0/Pictures/TideBot');
      await dir.create(recursive: true);
      final ext = path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final target = File(
          '${dir.path}/tidebot_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(path).copy(target.path);
      GlobalNotice.show('图片已保存到手机相册');
    } catch (e) {
      GlobalNotice.show('保存图片失败');
    }
  }

  void _previewImg(String path) {
    Navigator.push(
        context,
        PageRouteBuilder(
            pageBuilder: (c, a, s) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    actions: [
                      IconButton(
                          onPressed: () => _saveImageToGallery(path),
                          icon: const Icon(Icons.download_rounded,
                              color: Colors.white),
                          tooltip: '保存到相册')
                    ],
                    leading: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, color: Colors.white))),
                body: Center(
                    child: InteractiveViewer(
                        child: Image.file(File(path), fit: BoxFit.contain)))),
            transitionsBuilder: (c, a, s, child) =>
                FadeTransition(opacity: a, child: child)));
  }

  // ========== 机器人信息弹窗 ==========
  void _showBotInfo() {
    final n = TextEditingController(text: _bot['name']);
    final d = TextEditingController(text: _bot['desc']);
    final p = TextEditingController(text: _bot['prompt']);
    String avatar = _bot['avatar']?.toString() ?? '';
    TideDialogs.show(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
              // 更换头像：从相册选择并复制到应用目录
              Future<void> pickNewAvatar() async {
                try {
                  final picker = ImagePicker();
                  final img = await picker.pickImage(
                      source: ImageSource.gallery, maxWidth: 512);
                  if (img != null) {
                    String path = img.path;
                    if (path.toLowerCase().endsWith('.heic') ||
                        path.toLowerCase().endsWith('.heif')) {
                      try {
                        final converted = await HeifConverter.convert(path);
                        if (converted != null) path = converted;
                      } catch (_) {}
                    }
                    final dir = await getApplicationDocumentsDirectory();
                    final dest =
                        '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
                    await File(path).copy(dest);
                    if (mounted) setSt(() => avatar = dest);
                  }
                } catch (_) {}
              }

              return TideDialogSurface(
                  backgroundColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  content: TideDialogs.glassContent(context: ctx, children: [
                    const Center(
                        child: Text('机器人信息',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'TideFont'))),
                    const SizedBox(height: 14),
                    // 头像更换
                    Center(
                        child: GestureDetector(
                            onTap: pickNewAvatar,
                            child: Stack(children: [
                              Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(36),
                                      color: const Color(0xFFE8E8F0)),
                                  child: avatar.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(36),
                                          child: Image.file(File(avatar),
                                              fit: BoxFit.cover))
                                      : const Center(
                                          child: Icon(Icons.person_rounded,
                                              color: Color(0xFF8E8E93),
                                              size: 30))),
                              Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: TideTheme.of(ctx).primary),
                                      child: const Icon(Icons.edit_rounded,
                                          size: 14, color: Colors.white))),
                            ]))),
                    const SizedBox(height: 8),
                    const Center(
                        child: Text('点按头像可更换',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8E8E93),
                                fontFamily: 'TideFont'))),
                    const SizedBox(height: 8),
                    _mLabel('名字'), _mField(n),
                    const SizedBox(height: 10), _mLabel('人格设定'),
                    _mField(d, h: 80),
                    const SizedBox(height: 10), _mLabel('说话方式'),
                    _mField(p, h: 100),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: TideDialogs.glassButton('保存', onTap: () async {
                          final botId = _bot['id'] as String;
                          _bot['name'] = n.text;
                          _bot['desc'] = d.text;
                          _bot['prompt'] = p.text;
                          _bot['avatar'] = avatar;
                          await DBManager().updateBot(botId, {
                            'name': n.text,
                            'desc': d.text,
                            'prompt': p.text,
                            'avatar': avatar,
                          });
                          Navigator.pop(ctx);
                          setState(() {});
                        })),
                  ]));
            }));
  }

  // ========== 模型设置弹窗 ==========
  // 需求#5显示模型名 / #6 TTS分开+音色 / #7 token实时反馈：统一改为 StatefulBuilder + 本地状态，点击即刷新
  void _showModelSettings() async {
    final providers = await DBManager().queryChatProviders();
    final sttProviders = await DBManager().querySttProviders();
    final ttsProviders = await DBManager().queryTtsProviders();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final botId = _bot['id'] as String;
    // 当前选择（只读读取 DB，作为初始值；弹窗内实时状态交给 setSt 维护）
    // 聊天模型必须由用户明确选择；不能因为列表有 provider 就静默选中第一个。
    String curChat = prefs.getString('chat_model_$botId') ??
        ((_bot['chat_model'] as String?)?.trim() ?? '');
    String curBak = prefs.getString('backup_model_$botId') ?? '';
    String curVision = prefs.getString('vision_model_$botId') ?? '';
    String curImageGen = prefs.getString('image_gen_model_$botId') ?? '';
    String curStt = prefs.getString('stt_model_$botId') ??
        ((_bot['stt_model'] as String?)?.trim() ?? '');
    String curTts = prefs.getString('tts_model_$botId') ??
        ((_bot['tts_model'] as String?)?.isNotEmpty == true
            ? _bot['tts_model'] as String
            : '');
    int curTok = prefs.getInt('max_token_$botId') ??
        (_bot['max_tokens'] as int? ?? 10000);

    TideDialogs.show(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
              // 选中项实时更新到内存 & 持久化，让界面即时刷新
              Future<void> pickModel(String key, String val,
                  {bool isTts = false}) async {
                setSt(() {});
                await prefs.setString(key, val);
                if (!isTts && key == 'chat_model_$botId') {
                  _bot['chat_model'] = val;
                  await DBManager().updateBot(botId, {'chat_model': val});
                }
                if (isTts && key == 'tts_model_$botId') {
                  _bot['tts_model'] = val;
                  await DBManager().updateBot(botId, {'tts_model': val});
                }
                if (key == 'stt_model_$botId') {
                  _bot['stt_model'] = val;
                  await DBManager().updateBot(botId, {'stt_model': val});
                }
                setSt(() {});
              }

              return TideDialogSurface(
                  backgroundColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  content: TideDialogs.glassContent(
                      context: ctx,
                      maxWidth: 0.9,
                      children: [
                        const Center(
                            child: Text('模型设置',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'TideFont'))),
                        const SizedBox(height: 12),
                        Flexible(
                            child: SingleChildScrollView(
                                child: Column(children: [
                          _mLabel('聊天模型'),
                          _modelPicker(ctx, providers, curChat, (v) async {
                            curChat = v;
                            await pickModel('chat_model_$botId', v);
                          }),
                          _mLabel('备用模型'),
                          _modelPicker(ctx, providers, curBak, (v) async {
                            curBak = v;
                            await pickModel('backup_model_$botId', v);
                          }),
                          _mLabel('识图模型'),
                          _modelPicker(ctx, providers, curVision, (v) async {
                            curVision = v;
                            await pickModel('vision_model_$botId', v);
                          }),
                          _mLabel('生图模型'),
                          _modelPicker(ctx, providers, curImageGen, (v) async {
                            curImageGen = v;
                            await pickModel('image_gen_model_$botId', v);
                          }),
                          // TTS 模型独立：从 tts_provider_list 读取，额外展示音色字段（可选，不配置则纯文字回复）
                          _mLabel('STT模型'),
                          _modelPicker(ctx, sttProviders, curStt, (v) async {
                            curStt = v;
                            await pickModel('stt_model_$botId', v);
                          }),
                          _mLabel('TTS模型'),
                          _modelPicker(ctx, ttsProviders, curTts, (v) async {
                            curTts = v;
                            await pickModel('tts_model_$botId', v, isTts: true);
                          }),
                          _mLabel('最大上下文Token'),
                          _tokenField(ctx, curTok, (v) async {
                            curTok = v;
                            await prefs.setInt('max_token_$botId', v);
                            await DBManager()
                                .updateBot(botId, {'max_tokens': v});
                            setSt(() {});
                          }),
                        ]))),
                        const SizedBox(height: 12),
                        TideDialogs.glassButton('确定',
                            onTap: () => Navigator.pop(ctx)),
                      ]));
            }));
  }

  // token 选择字段，点击弹底部选择，选中后立即回调更新
  Widget _tokenField(
      BuildContext parentCtx, int cur, Future<void> Function(int) onPick) {
    Future<void> choose(int v) async {
      await onPick(v);
      if (mounted) setState(() {});
    }

    return GestureDetector(
        onTap: () {
          final c = TextEditingController(text: cur.toString());
          showTideSheet(
              context: parentCtx,
              height: 260,
              child: Column(children: [
                const SizedBox(height: 10),
                const Text('最大上下文',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 8),
                ListTile(
                    title: const Text('10,000 token',
                        style: TextStyle(fontFamily: 'TideFont')),
                    trailing: cur == 10000
                        ? Icon(Icons.check,
                            color: TideTheme.of(parentCtx).primary)
                        : null,
                    onTap: () {
                      Navigator.pop(parentCtx);
                      choose(10000);
                    }),
                ListTile(
                    title: const Text('20,000 token',
                        style: TextStyle(fontFamily: 'TideFont')),
                    trailing: cur == 20000
                        ? Icon(Icons.check,
                            color: TideTheme.of(parentCtx).primary)
                        : null,
                    onTap: () {
                      Navigator.pop(parentCtx);
                      choose(20000);
                    }),
                ListTile(
                    title: const Text('自定义...',
                        style: TextStyle(fontFamily: 'TideFont')),
                    onTap: () {
                      Navigator.pop(parentCtx);
                      TideDialogs.show(
                          context: parentCtx,
                          builder: (c2) => TideDialogSurface(
                              backgroundColor: Colors.transparent,
                              contentPadding: EdgeInsets.zero,
                              content: TideDialogs.glassContent(
                                  context: c2,
                                  children: [
                                    const Text('自定义Token',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'TideFont')),
                                    const SizedBox(height: 10),
                                    TextField(
                                        controller: c,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            hintText: '输入token数量',
                                            hintStyle: TextStyle(
                                                fontFamily: 'TideFont'),
                                            border: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(10)),
                                                borderSide: BorderSide.none),
                                            enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(10)),
                                                borderSide: BorderSide.none),
                                            focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                    Radius.circular(10)),
                                                borderSide: BorderSide.none))),
                                    const SizedBox(height: 12),
                                    TideDialogs.glassButton('确定', onTap: () {
                                      final v = int.tryParse(c.text);
                                      if (v != null && v > 0) choose(v);
                                      Navigator.pop(c2);
                                    }),
                                  ])));
                    }),
              ]));
        },
        child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: TideTheme.of(parentCtx).surfaceVariant,
                borderRadius: BorderRadius.circular(10)),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    cur >= 1000
                        ? '${cur.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (m) => ',')} token'
                        : '$cur token',
                    style: TextStyle(
                        fontSize: 14,
                        color: TideTheme.of(parentCtx).textStrong,
                        fontFamily: 'TideFont')))));
  }

  // 模型选择器：普通模型显示「名字 · 模型名」，TTS 额外显示「音色」
  Widget _modelPicker(BuildContext ctx, List<Map<String, dynamic>> providers,
      String cur, Function(String) onPick) {
    final sel = providers.firstWhereOrNull((p) => p['id'] == cur);
    final String disp;
    if (sel != null) {
      final name = sel['name']?.toString() ?? '未选择';
      final model = sel['model']?.toString().trim() ?? '';
      final voice = sel['voice']?.toString().trim() ?? '';
      if (voice.isNotEmpty) {
        disp = '$name · $model · 音色:$voice';
      } else {
        disp = model.isNotEmpty ? '$name · $model' : name;
      }
    } else {
      disp = providers.isEmpty ? '无可用模型' : '未选择';
    }
    return GestureDetector(
        onTap: () {
          showTideSheet(
              context: ctx,
              height: 380,
              child: ListView(children: [
                ListTile(
                  leading: const Icon(Icons.block_rounded),
                  title: const Text('不选择',
                      style: TextStyle(fontFamily: 'TideFont', fontSize: 14)),
                  subtitle: const Text('清除当前模型配置',
                      style: TextStyle(fontSize: 12, fontFamily: 'TideFont')),
                  trailing: cur.isEmpty
                      ? Icon(Icons.check, color: TideTheme.of(ctx).primary)
                      : null,
                  onTap: () {
                    onPick('');
                    Navigator.pop(ctx);
                  },
                ),
                for (var pv in providers)
                  ListTile(
                    title: Text(_providerTitle(pv),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'TideFont', fontSize: 14)),
                    subtitle: Text(_providerSub(pv),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'TideFont')),
                    trailing: cur == pv['id']
                        ? Icon(Icons.check, color: TideTheme.of(ctx).primary)
                        : null,
                    onTap: () {
                      onPick(pv['id'] as String);
                      Navigator.pop(ctx);
                    },
                  ),
              ]));
        },
        child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: TideTheme.of(ctx).surfaceVariant,
                borderRadius: BorderRadius.circular(10)),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(disp,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: TideTheme.of(ctx).textStrong,
                        fontFamily: 'TideFont')))));
  }

  String _providerTitle(Map<String, dynamic> p) {
    final name = p['name']?.toString() ?? '';
    return name;
  }

  String _providerSub(Map<String, dynamic> p) {
    final model = p['model']?.toString().trim() ?? '';
    final voice = p['voice']?.toString().trim() ?? '';
    if (voice.isNotEmpty) return '$model · 音色:$voice';
    return model;
  }

  // ========== 删除选项 ==========
  void _showDeleteOptions() {
    bool delMsgs = false;
    bool delMem = false;
    TideDialogs.show(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setSt) => TideDialogSurface(
                backgroundColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                content: TideDialogs.glassContent(context: ctx, children: [
                  const Text('清理数据',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'TideFont')),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                      value: delMsgs,
                      onChanged: (v) => setSt(() => delMsgs = v ?? false),
                      title: const Text('删除聊天记录',
                          style: TextStyle(fontFamily: 'TideFont')),
                      controlAffinity: ListTileControlAffinity.leading),
                  CheckboxListTile(
                      value: delMem,
                      onChanged: (v) => setSt(() => delMem = v ?? false),
                      title: const Text('删除底层记忆',
                          style: TextStyle(fontFamily: 'TideFont')),
                      controlAffinity: ListTileControlAffinity.leading),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TideDialogs.glassButton('取消',
                            onTap: () => Navigator.pop(ctx),
                            color: const Color(0xFFE8E8F0),
                            textColor: const Color(0xFF1C1C1E))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TideDialogs.glassButton('确认清除', onTap: () async {
                      if (delMsgs) {
                        _messagesRevision++;
                        await DBManager().deleteMessages(_bot['id'] as String);
                        if (mounted) {
                          setState(() {
                            _msgs.clear();
                            _deferredPersistedMessageIds.clear();
                          });
                        }
                      }
                      if (delMem) {
                        await DBManager().deleteMemories(_bot['id'] as String);
                      }
                      Navigator.pop(ctx);
                      _loadMsgs();
                    }, color: const Color(0xFFE74C3C))),
                  ]),
                ]))));
  }

  Future<void> _toggleAudio(String path) async {
    try {
      if (_playingAudioPath != path) {
        setState(() {
          _playingAudioPath = path;
          _audioPosition = Duration.zero;
          _audioDuration = Duration.zero;
        });
        await _player.play(DeviceFileSource(path));
        return;
      }
      if (_audioPlaying) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingAudioPath = null;
        _audioPlaying = false;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });
      GlobalNotice.show(
        '无法播放这条语音：$e',
        color: Theme.of(context).colorScheme.error,
      );
    }
  }

  String _formatAudioTime(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _audioBubble({
    required String path,
    required bool isUser,
    required int fallbackSeconds,
  }) {
    final active = _playingAudioPath == path;
    final position = active ? _audioPosition : Duration.zero;
    final duration = active && _audioDuration > Duration.zero
        ? _audioDuration
        : Duration(seconds: fallbackSeconds);
    final max =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();
    final foreground = isUser ? Colors.white : TideTheme.of(context).textStrong;
    final muted = isUser
        ? Colors.white.withValues(alpha: 0.78)
        : TideTheme.of(context).textWeak;
    final knownDuration = duration.inMilliseconds > 0;
    final width = MediaQuery.sizeOf(context).width.clamp(250.0, 420.0) - 175;
    return Container(
      constraints: BoxConstraints(minWidth: 154, maxWidth: width),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(7, 5, 8, 5),
      decoration: BoxDecoration(
        color: isUser
            ? TideTheme.of(context).primary
            : TideTheme.of(context).buttonSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: active && _audioPlaying ? '暂停语音' : '播放语音',
              onPressed: () => _toggleAudio(path),
              icon: Icon(
                active && _audioPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
                color: foreground,
                size: 25,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  min: 0,
                  max: max,
                  value: value,
                  onChanged: !active || !knownDuration
                      ? null
                      : (v) => _player.seek(Duration(milliseconds: v.round())),
                  activeColor: foreground,
                  inactiveColor: muted,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatAudioTime(position),
                        style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            fontFamily: 'TideFont')),
                    Text(knownDuration ? _formatAudioTime(duration) : '语音',
                        style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            fontFamily: 'TideFont')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 长按消息 ==========
  void _msgLongPress(Map<String, dynamic> msg) {
    final text = msg['content']?.toString() ?? '';
    showTideSheet(
      context: context,
      height: 300,
      child: Builder(
        builder: (sheetContext) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: [
            const Center(
              child: Text('消息操作',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont')),
            ),
            ListTile(
              leading: Icon(Icons.copy_rounded,
                  color: TideTheme.of(sheetContext).primary),
              title: const Text('复制', style: TextStyle(fontFamily: 'TideFont')),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(sheetContext);
              },
            ),
            if (msg['role'] == 'user' &&
                msg['error_log']?.toString().isNotEmpty == true)
              ListTile(
                leading: Icon(Icons.refresh_rounded,
                    color: TideTheme.of(sheetContext).primary),
                title: const Text('重新发送',
                    style: TextStyle(fontFamily: 'TideFont')),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _retryMessage(msg);
                },
              ),
            // 引用功能已移除，避免生成和维护 reply_to_id 关联。
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFE74C3C)),
              title: const Text('删除',
                  style: TextStyle(
                      fontFamily: 'TideFont', color: Color(0xFFE74C3C))),
              onTap: () async {
                await DBManager().deleteMessage(msg['id'].toString());
                if (mounted) {
                  setState(() => _msgs.removeWhere(
                      (item) => item['id'].toString() == msg['id'].toString()));
                }
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _replyPreview(Map<String, dynamic> message) {
    final text = message['content']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
    return switch (message['type']?.toString()) {
      'image' => '[图片]',
      'audio' => '[语音]',
      'document' => '[文档]',
      _ => '[消息]',
    };
  }

  Widget _replyCard(String replyId, bool isUser) {
    final original = _msgs.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id']?.toString() == replyId,
        orElse: () => null);
    final missing = original == null;
    final author = missing
        ? '原消息'
        : (original['role'] == 'user' ? '你' : _bot['name']?.toString() ?? 'TA');
    final preview = missing ? '[原消息已删除]' : _replyPreview(original);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: isUser
            ? Colors.white.withValues(alpha: 0.16)
            : TideTheme.of(context).surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(
                color: isUser ? Colors.white70 : TideTheme.of(context).primary,
                width: 3)),
      ),
      child: Text('$author：$preview',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              color: isUser ? Colors.white : TideTheme.of(context).textWeak,
              fontFamily: 'TideFont')),
    );
  }

  // ========== 构建UI ==========
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    // 背景优先级：单机器人自定义 > 全局主题背景 > 主题底色
    final String? effBg =
        _hasBg ? _customBg : (theme.chatBg.isNotEmpty ? theme.chatBg : null);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // 背景：与主界面一致的主题底色 + 柔光光斑(不再用强烈渐变)，避免黑屏/割裂
        Positioned.fill(
          child: effBg != null
              ? Image.file(File(effBg), fit: BoxFit.cover)
              : DecoratedBox(
                  decoration: BoxDecoration(color: theme.bgColor),
                  child: Stack(children: [
                    Positioned(
                        left: -80,
                        top: -60,
                        child: IgnorePointer(
                            child: Container(
                                width: 240,
                                height: 240,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(colors: [
                                      theme.primaryLight
                                          .withValues(alpha: 0.25),
                                      Colors.transparent
                                    ]))))),
                    Positioned(
                        right: -60,
                        bottom: 120,
                        child: IgnorePointer(
                            child: Container(
                                width: 260,
                                height: 260,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(colors: [
                                      theme.primary.withValues(alpha: 0.15),
                                      Colors.transparent
                                    ]))))),
                  ]),
                ),
        ),
        Column(children: [
          _chatHeader(),
          Expanded(child: _chatBody()),
        ]),
        Positioned(left: 0, right: 0, bottom: 0, child: _inputBar()),
      ]),
    );
  }

  Widget _chatHeader() {
    return ClipRRect(
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: _hasBg
                ? TideTheme.of(context).glass.withValues(alpha: 0.15)
                : TideTheme.of(context).glass.withValues(alpha: 0.55),
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.arrow_back_ios_rounded,
                              size: 20,
                              color: TideTheme.of(context).textStrong))),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(_bot['name'] as String? ?? '',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'TideFont',
                                color: TideTheme.of(context).textStrong)),
                        if (_typing)
                          Text('正在输入中...',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: TideTheme.of(context).primary,
                                  fontFamily: 'TideFont')),
                      ])),
                  // 电话按钮
                  IconButton(
                      icon: Icon(Icons.call_rounded,
                          size: 20, color: TideTheme.of(context).primary),
                      onPressed: _openCallPreparation),
                  // 删除按钮
                  IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 20, color: TideTheme.of(context).iconMuted),
                      onPressed: _showDeleteOptions),
                  // 设置按钮
                  IconButton(
                      icon: Icon(Icons.settings_rounded,
                          size: 20, color: TideTheme.of(context).iconMuted),
                      onPressed: _showModelSettings),
                  // 信息按钮
                  IconButton(
                      icon: Icon(Icons.menu_rounded,
                          size: 20, color: TideTheme.of(context).iconMuted),
                      onPressed: _showBotInfo),
                ]),
              ),
            ),
          )),
    );
  }

  Future<void> _openCallPreparation() async {
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isEmpty) return;

    // 这里只校验已选择的配置；当前没有实时 STT/TTS 运行时，
    // 因而不会开始录音、转写或播放伪造的通话音频。
    final prefs = await SharedPreferences.getInstance();
    final hasStt = (prefs.getString('stt_model_$botId') ??
            (_bot['stt_model']?.toString() ?? ''))
        .isNotEmpty;
    final hasTts = (prefs.getString('tts_model_$botId') ??
            (_bot['tts_model']?.toString() ?? ''))
        .isNotEmpty;

    if (!mounted || !await AppPermissions.microphone(context) || !mounted) {
      return;
    }

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallPage(
        bot: _bot,
        hasStt: hasStt,
        hasTts: hasTts,
        onOpenSettings: () {
          Navigator.of(context).pop();
          _showModelSettings();
        },
      ),
    ));
  }

  String _errorSolution(dynamic code) {
    final raw = code?.toString().toLowerCase() ?? '';
    final detail = switch (raw) {
      '400' =>
        '请求格式不被接口接受：核对模型名称；兼容接口地址应以 /v1 结尾而不是再填写 /chat/completions；移除该模型不支持的图片、工具调用或超长字段后重试。',
      '401' => '密钥无效：重新粘贴完整 API Key，确认没有前后空格、过期密钥或把其他平台的 Key 填到了当前服务商。',
      '403' => '当前 Key 没有该模型或服务权限：到服务商控制台开通模型并确认账户/项目空间正确。',
      '402' => '账户余额或配额不足：到服务商后台检查余额、免费额度和并发配额，充值或切换已开通模型。',
      '404' =>
        '地址或模型不存在：检查 Base URL 是否重复包含 /v1、/chat/completions，确认模型 ID 与服务商控制台完全一致。',
      '408' ||
      'timeout' =>
        '请求超时：检查网络和服务端排队；降低回复长度或附件尺寸。主模型持续超时时，还要分别测试备用模型的 URL、Key 与模型名。',
      '409' => '请求与正在进行的任务冲突：等待当前请求结束后再发送，不要连续重复点击发送。',
      '413' => '请求内容过大：减少图片、文件文本或历史上下文，并确认最大上下文不超过模型实际窗口。',
      '422' => '字段语义校验失败：通常是模型不支持工具调用、视觉消息或指定音色。先用纯文本测试，再逐项开启功能。',
      '429' => '触发限流：等待服务商冷却时间，降低并发和发送频率；必要时切换备用模型。',
      '500' ||
      '502' ||
      '503' ||
      '504' =>
        '服务商侧异常：查看服务商状态页并稍后重试；若备用模型也失败，请分别测试其连接。',
      'network' ||
      'dns' ||
      'connection refused' =>
        '无法建立网络连接：确认设备联网、DNS/代理可用、域名可解析，并检查 Base URL 不是网页或内网地址。',
      'ssl' || 'tls' || 'certificate' => 'HTTPS 证书校验失败：检查设备时间、证书有效性和代理是否注入证书。',
      'empty response' ||
      'invalid response' =>
        '服务端返回格式不是 OpenAI 兼容响应：检查接口类型和路径；部分模型需关闭工具调用或改用专用接口。',
      _ => '请打开完整日志定位 HTTP 状态与响应体，再按对应状态检查模型、接口地址、密钥、账户配额、网络或功能兼容性。',
    };
    return '$detail\n\n仍无法解决时，请复制完整日志，并同时提供服务商名称、模型名和发生时间。';
  }

  void _showErrorDetails(Map<String, dynamic> message) {
    final log = message['error_log']?.toString().trim();
    final content = message['error_text']?.toString() ??
        message['error_message']?.toString() ??
        message['content']?.toString() ??
        '请求失败';

    TideDialogs.show(
      context: context,
      builder: (ctx) => TideDialogSurface(
        title: const Text('请求错误详情', style: TextStyle(fontFamily: 'TideFont')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(content, style: const TextStyle(fontFamily: 'TideFont')),
              const SizedBox(height: 14),
              const Text('完整报错日志',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SelectableText(log?.isNotEmpty == true ? log! : '历史错误未保存完整日志。',
                  style:
                      const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              const SizedBox(height: 14),
              const Text('解决方法', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_errorSolution(message['error_code']),
                  style: const TextStyle(fontFamily: 'TideFont')),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制日志'),
            onPressed: () {
              final copyText = log?.isNotEmpty == true
                  ? log!
                  : '$content\n\n${_errorSolution(message['error_code'])}';
              Clipboard.setData(ClipboardData(text: copyText));
              GlobalNotice.show('完整错误日志已复制');
            },
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Map<String, dynamic>? _sharedPostPayload(Map<String, dynamic> message) {
    if (message['type']?.toString() != 'shared_post') return null;
    try {
      final raw = jsonDecode(message['content']?.toString() ?? '');
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (_) {
      return null;
    }
  }

  Widget _sharedPostCard(Map<String, dynamic> payload, bool isUser) {
    final theme = TideTheme.of(context);
    final author = payload['author']?.toString().trim().isNotEmpty == true
        ? payload['author'].toString()
        : '匿名';
    final content = payload['content']?.toString() ?? '';
    final imagePath = payload['image_path']?.toString() ?? '';
    final timestamp = (payload['timestamp'] as num?)?.toInt();
    final imageExists = imagePath.isNotEmpty && File(imagePath).existsSync();
    final foreground = isUser ? Colors.white : theme.textStrong;
    final muted =
        isUser ? Colors.white.withValues(alpha: 0.76) : theme.textWeak;
    return Container(
      width: 245,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser
            ? theme.primary.withValues(alpha: 0.92)
            : theme.buttonSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.dynamic_feed_rounded, size: 17, color: foreground),
          const SizedBox(width: 6),
          Expanded(
              child: Text('分享的动态',
                  style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont'))),
        ]),
        const SizedBox(height: 8),
        Text(author,
            style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontFamily: 'TideFont')),
        if (timestamp != null) ...[
          const SizedBox(height: 2),
          Text(fmtTime(timestamp),
              style: TextStyle(
                  color: muted, fontSize: 11, fontFamily: 'TideFont')),
        ],
        if (content.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(content,
              style: TextStyle(
                  color: foreground, height: 1.35, fontFamily: 'TideFont')),
        ],
        if (imageExists) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _previewImg(imagePath),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 144,
                height: 144,
                child: Image.file(File(imagePath), fit: BoxFit.cover),
              ),
            ),
          ),
        ] else if (imagePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('图片已失效或不可访问',
              style: TextStyle(
                  color: muted, fontSize: 12, fontFamily: 'TideFont')),
        ],
      ]),
    );
  }

  Widget _chatBody() {
    if (_msgsLoading) {
      return Center(
          child:
              CircularProgressIndicator(color: TideTheme.of(context).primary));
    }
    return ListView.builder(
      key: const PageStorageKey<String>('chat_messages'),
      controller: _scrollC,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // The composer is overlaid on the stack; reserve its full height so the last bubble is never covered.
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 84),
      itemCount: _msgs.length,
      itemBuilder: (ctx, i) {
        final m = _msgs[_msgs.length - 1 - i];
        final isUser = m['role'] == 'user';
        // 内存消息使用 image/audio；数据库历史使用 type/file_path，统一兼容两种来源。
        final filePath = m['file_path']?.toString();
        final imagePath = m['image']?.toString() ??
            ((m['type'] == 'image' || m['type'] == 'sticker')
                ? filePath
                : null);
        final audioPath =
            m['audio']?.toString() ?? (m['type'] == 'audio' ? filePath : null);
        final documentPath = m['type'] == 'document' ? filePath : null;
        final hasImg = imagePath?.isNotEmpty == true;
        final hasAudio = audioPath?.isNotEmpty == true;
        final hasDocument = documentPath?.isNotEmpty == true;
        final hasPreviousDocument = i < _msgs.length - 1 &&
            _msgs[_msgs.length - 2 - i]['type'] == 'document';
        final documentName =
            m['document_name']?.toString().trim().isNotEmpty == true
                ? m['document_name'].toString()
                : (documentPath?.split(Platform.pathSeparator).last ?? '文档');
        final documentExt = documentName.contains('.')
            ? documentName.split('.').last.toUpperCase()
            : '文件';
        final isSticker = m['type'] == 'sticker';
        // 表情包的 content 是内部情绪分类，绝不能作为正文显示。
        final txt = isSticker ? '' : ((m['content'] as String?) ?? '');
        final sharedPost = _sharedPostPayload(m);
        final replyId = m['reply_to_id']?.toString();
        final sources = _decodeSources(m['sources_json']);
        final ts = m['timestamp'] as int? ?? 0;
        // 流式占位气泡（id 以 stream_ 开头）会先用空内容上屏，之后才填充真实文字。
        // 它的时间不应展示，否则会出现“先出时间、后出内容”“一条消息两个时间”的观感。
        final isStreamingPlaceholder =
            (m['id']?.toString() ?? '').startsWith('stream_');
        // 只有气泡真正渲染出可见内容时才显示时间：图片/贴纸必须文件真实存在，
        // 文本必须非空，避免生成图片或分段等待时时间先出、内容后到。
        final hasVisibleContent = isUser ||
            txt.isNotEmpty ||
            (hasImg && File(imagePath!).existsSync()) ||
            hasAudio ||
            hasDocument ||
            replyId?.isNotEmpty == true ||
            sharedPost != null;
        final showTimeHere =
            _showMessageTime && !isStreamingPlaceholder && hasVisibleContent;

        return GestureDetector(
          onLongPress: () => _msgLongPress(m),
          child: Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser && m['error_log']?.toString().isNotEmpty == true)
                    GestureDetector(
                      onTap: () => _showErrorDetails(m),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, right: 6),
                        child: Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red.shade400,
                          size: 22,
                        ),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    child: Column(
                        crossAxisAlignment: isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (_showChatAvatar)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: isUser
                                  ? CircleAvatar(
                                      radius: 14,
                                      backgroundColor: TideTheme.of(context)
                                          .primary
                                          .withValues(alpha: 0.15),
                                      child: Icon(Icons.person_rounded,
                                          size: 16,
                                          color: TideTheme.of(context).primary),
                                    )
                                  : TideBotAvatar(
                                      name:
                                          _bot['name']?.toString() ?? 'TideBot',
                                      path: _bot['avatar']?.toString(),
                                      size: 28,
                                    ),
                            ),
                          if (hasDocument) ...[
                            if (hasPreviousDocument)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 4),
                                child: Divider(
                                    height: 1,
                                    color: TideTheme.of(context).border),
                              ),
                            GestureDetector(
                              onTap: () async {
                                if (documentPath != null &&
                                    await File(documentPath).exists()) {
                                  final opened = await launchUrl(
                                    Uri.file(documentPath),
                                    mode: LaunchMode.externalApplication,
                                  );
                                  if (!opened && mounted) {
                                    GlobalNotice.show('没有可打开此文件的应用');
                                  }
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? TideTheme.of(context).primary
                                      : TideTheme.of(context).buttonSecondary,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isUser
                                        ? Colors.white.withValues(alpha: .28)
                                        : TideTheme.of(context).border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 42,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isUser
                                            ? Colors.white
                                                .withValues(alpha: .18)
                                            : TideTheme.of(context)
                                                .primary
                                                .withValues(alpha: .12),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.insert_drive_file_rounded,
                                              size: 20,
                                              color: isUser
                                                  ? Colors.white
                                                  : TideTheme.of(context)
                                                      .primary),
                                          Text(documentExt,
                                              style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w700,
                                                  color: isUser
                                                      ? Colors.white
                                                      : TideTheme.of(context)
                                                          .primary,
                                                  fontFamily: 'TideFont')),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(documentName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: isUser
                                                      ? Colors.white
                                                      : TideTheme.of(context)
                                                          .textStrong,
                                                  fontFamily: 'TideFont')),
                                          const SizedBox(height: 3),
                                          Text('文件附件 · 点击选择应用打开',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: isUser
                                                      ? Colors.white70
                                                      : TideTheme.of(context)
                                                          .textWeak,
                                                  fontFamily: 'TideFont')),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (hasImg && File(imagePath!).existsSync())
                            GestureDetector(
                              onTap: () => _previewImg(imagePath),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: isSticker ? 112 : 144,
                                  height: isSticker ? 112 : 144,
                                  child: Image.file(
                                    File(imagePath),
                                    fit: BoxFit.cover,
                                    cacheWidth: isSticker ? 224 : 288,
                                  ),
                                ),
                              ),
                            ),
                          // 音频卡片：同一结构兼容用户与机器人语音；转写文字会显示在卡片下方。
                          if (hasAudio)
                            _audioBubble(
                              path: audioPath!,
                              isUser: isUser,
                              fallbackSeconds: m['duration'] as int? ?? 0,
                            ),
                          // STT 结果放在语音卡片下；无转写时不渲染空白文字。
                          if (hasAudio && txt.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _parseText(txt, isUser)),
                          if (replyId != null && replyId.isNotEmpty)
                            _replyCard(replyId, isUser),
                          // 动态分享使用独立卡片，JSON 负载不会直接暴露为聊天正文。
                          if (sharedPost != null)
                            _sharedPostCard(sharedPost, isUser),
                          // 普通文字气泡
                          if (sharedPost == null && !hasAudio && txt.isNotEmpty)
                            _parseText(txt, isUser),
                          if (_showSearchSources && sources.isNotEmpty)
                            _sourceCards(sources),
                          if (showTimeHere)
                            Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(fmtTime(ts),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: TideTheme.of(context).textFaint,
                                        fontFamily: 'TideFont'))),
                        ]),
                  ),
                ],
              )),
        );
      },
    );
  }

  List<Map<String, String>> _decodeSources(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return [];
    try {
      final values = jsonDecode(raw.toString());
      if (values is! List) return [];
      return values
          .whereType<Map>()
          .map((item) => <String, String>{
                'title': item['title']?.toString() ?? '网页来源',
                'url': item['url']?.toString() ?? '',
              })
          .where((item) => item['url']!.startsWith('http'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Widget _sourceCards(List<Map<String, String>> sources) {
    final theme = TideTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.link_rounded, size: 16, color: theme.primary),
        title: Text('参考 ${sources.length} 个来源',
            style: TextStyle(
                fontSize: 12, color: theme.textWeak, fontFamily: 'TideFont')),
        children: sources.map((source) {
          final uri = Uri.tryParse(source['url'] ?? '');
          final domain = uri?.host.replaceFirst('www.', '') ?? '';
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 4, right: 2),
            title: Text(source['title'] ?? '网页来源',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: theme.textStrong,
                    fontFamily: 'TideFont')),
            subtitle: Text(domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.textFaint,
                    fontFamily: 'TideFont')),
            trailing:
                Icon(Icons.open_in_new_rounded, size: 14, color: theme.primary),
            onTap: uri == null
                ? null
                : () => launchUrl(uri, mode: LaunchMode.externalApplication),
          );
        }).toList(),
      ),
    );
  }

// 音频时长由播放器进度组件统一显示。

  // 富文本解析：旁白括号灰化
  Widget _parseText(String text, bool isUser) {
    final baseStyle = TextStyle(
      color: isUser ? Colors.white : TideTheme.of(context).textStrong,
      fontSize: 14,
      fontFamily: 'TideFont',
      height: 1.5,
    );
    final spans = <TextSpan>[];
    final reg = RegExp(r'\(.*?\)');
    int last = 0;
    for (var m in reg.allMatches(text)) {
      if (m.start > last) {
        spans.add(
            TextSpan(text: text.substring(last, m.start), style: baseStyle));
      }
      spans.add(TextSpan(
          text: text.substring(m.start, m.end),
          style: baseStyle.copyWith(
              color: isUser
                  ? Colors.white.withValues(alpha: 0.6)
                  : TideTheme.of(context).textWeak,
              fontSize: 12,
              fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isUser
                ? TideTheme.of(context).primary
                : TideTheme.of(context).bubbleAi,
            borderRadius: BorderRadius.circular(16)),
        child: RichText(
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            text: TextSpan(children: spans)));
  }

  Widget _attachmentPreview(dynamic theme) {
    final paths = [..._pendingImages, ..._pendingDocuments];
    if (paths.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final path = paths[index];
          final isImage = _pendingImages.contains(path);
          return SizedBox(
            width: isImage ? 62 : 140,
            child: Stack(children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: isImage
                      ? Image.file(File(path), fit: BoxFit.cover)
                      : Container(
                          color: theme.surfaceVariant,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            path.split(Platform.pathSeparator).last,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.textWeak,
                                fontFamily: 'TideFont'),
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() {
                      _pendingImages.remove(path);
                      _pendingDocuments.remove(path);
                    }),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _inputBar() {
    final theme = TideTheme.of(context);
    // One clean capsule like the reference: no outer dark outline/card.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _bottomBarCtrl, curve: Curves.easeOutCubic)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          decoration: BoxDecoration(
            color: theme.surfaceVariant.withValues(alpha: _hasBg ? .92 : 1),
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingImages.isNotEmpty || _pendingDocuments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: _attachmentPreview(theme),
                ),
              Row(children: [
                IconButton(
                    tooltip: '添加图片或文件',
                    onPressed: _pickMedia,
                    icon: Icon(Icons.add_rounded,
                        size: 23, color: theme.iconMuted)),
                Expanded(
                    child: TextField(
                  focusNode: _inputFocus,
                  controller: _msgC,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'TideFont',
                      color: theme.textStrong),
                  decoration: InputDecoration(
                      hintText: '发消息...',
                      hintStyle: TextStyle(
                          color: theme.textFaint,
                          fontSize: 14,
                          fontFamily: 'TideFont'),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10)),
                )),
                IconButton(
                    tooltip: _isRecording ? '结束录音' : '录音',
                    onPressed: _toggleRec,
                    icon: Icon(Icons.mic_rounded,
                        size: 22,
                        color: _isRecording ? Colors.red : theme.iconMuted)),
                SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      tooltip: '发送',
                      splashRadius: 22,
                      onPressed: _send,
                      icon: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.primary.withValues(
                                  alpha: (_hasText ||
                                          _pendingImages.isNotEmpty ||
                                          _pendingDocuments.isNotEmpty)
                                      ? 1
                                      : .42)),
                          child: const Icon(Icons.arrow_upward_rounded,
                              size: 18, color: Colors.white)),
                    )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mLabel(String t) {
    final theme = TideTheme.of(context);
    return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 12, color: theme.textWeak, fontFamily: 'TideFont')));
  }

  Widget _mField(TextEditingController c, {double h = 40}) {
    final theme = TideTheme.of(context);
    return Container(
        height: h,
        decoration: BoxDecoration(
            color: theme.surfaceVariant,
            borderRadius: BorderRadius.circular(10)),
        child: TextField(
            controller: c,
            maxLines: null,
            expands: h > 50,
            style: TextStyle(
                fontSize: 14, color: theme.textStrong, fontFamily: 'TideFont'),
            decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(10), border: InputBorder.none)));
  }
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    try {
      return firstWhere(test);
    } catch (_) {
      return null;
    }
  }
}
