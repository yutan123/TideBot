import 'dart:io';
import 'dart:math';
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
  // Attachment is staged beside the composer and sent only after explicit confirmation.
  String? _pendingImage;
  String? _pendingDocument;
  String? _pendingMediaContext;

  // ===== 防抖/合并：请求代次 + 待重发队列 =====
  // 用户连续发送多条时，递增代次让在途请求的渲染结果作废，并把新文本并入
  // 队列；旧请求返回后若代次过期则拦截，再由 finally 用合并文本统一重发。
  int _requestGen = 0;
  String _queuedText = '';
  bool _queued = false;

  // ===== 主动回复调度（前台 UI 层）=====
  // 后台 isolate 无法使用 AIManager，因此主动回复放在聊天室前台通过 Timer 调度。
  Timer? _proactiveTimer;
  // 连续主动回复后用户未应答的次数；达到上限后暂停，等用户下次发言再恢复。
  int _proactiveUnanswered = 0;
  final Random _proactiveRng = Random();
  void _msgChanged() {
    if (mounted) setState(() => _hasText = _msgC.text.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bot = Map.from(widget.botData);
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
    _startProactiveReply();

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
    WidgetsBinding.instance.removeObserver(this);
    _messageSyncTimer?.cancel();
    _streamDisplayTimer?.cancel();
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
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
    if (state == AppLifecycleState.resumed) _syncLatestMessages();
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
      if (mounted) {
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

  Future<void> _syncLatestMessages() async {
    if (!mounted || _loading) return;
    try {
      final fresh = await DBManager()
          .queryMessages(_bot['id'] as String, limit: 80, descending: true);
      if (!mounted || fresh.isEmpty) return;
      final known = <String>{for (final m in _msgs) m['id']?.toString() ?? ''};
      final additions =
          fresh.where((m) => !known.contains(m['id']?.toString())).toList();
      if (additions.isEmpty) return;
      setState(() {
        _msgs.addAll(additions);
        _msgs.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0)
            .compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
      });
      _scrollDown(animated: false);
    } catch (_) {}
  }

  List<String> _splitReplySegments(String content) {
    final matches = RegExp(r'.*?[。？！~…]+|.+$', multiLine: true)
        .allMatches(content)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toList();
    return matches.isEmpty ? <String>[content] : matches;
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

  // ========== 主动回复调度 ==========
  String get _proactiveDueKey => 'proactive_due_at_${_bot['id']}';
  Future<void> _startProactiveReply() async {
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isEmpty) return;
    try {
      final db = DBManager();
      if (await db.getKV('proactive_reply') == 'false') return;
      final minMin =
          (int.tryParse(await db.getKV('proactive_min_minutes') ?? '') ?? 60)
              .clamp(1, 1440);
      final maxMin =
          (int.tryParse(await db.getKV('proactive_max_minutes') ?? '') ?? 90)
              .clamp(minMin, 1440);
      _proactiveUnanswered =
          (int.tryParse(await db.getKV('proactive_unanswered_$botId') ?? '') ??
                  0)
              .clamp(0, 5);
      final dueAt = int.tryParse(await db.getKV(_proactiveDueKey) ?? '');
      _scheduleProactive(minMin, maxMin, dueAt: dueAt);
    } catch (e) {
      debugPrint('[proactive] start failed: $e');
    }
  }

  void _scheduleProactive(int minMinutes, int maxMinutes, {int? dueAt}) {
    _proactiveTimer?.cancel();
    if (!mounted || _proactiveUnanswered >= 3) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final range = maxMinutes - minMinutes;
    final target = dueAt ??
        now +
            Duration(
                    minutes: minMinutes +
                        (range > 0 ? _proactiveRng.nextInt(range + 1) : 0))
                .inMilliseconds;
    DBManager().setKV(_proactiveDueKey, '$target');
    _proactiveTimer = Timer(
        Duration(milliseconds: (target - now).clamp(0, 604800000)),
        _fireProactive);
  }

  void _restartProactiveTimer(int minMinutes, int maxMinutes) =>
      _scheduleProactive(minMinutes, maxMinutes);
  void _onUserInteracted() {
    _proactiveUnanswered = 0;
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isNotEmpty) DBManager().setKV('proactive_unanswered_$botId', '0');
    _startProactiveReply();
  }

  Future<void> _fireProactive() async {
    _proactiveTimer = null;
    DBManager().setKV(_proactiveDueKey, '');
    final botId = _bot['id']?.toString() ?? '';
    if (!mounted || botId.isEmpty) return;
    // 连续 3 次主动回复用户都没回 → 暂停；等用户下次发言再由 _onUserInteracted 恢复。
    if (_proactiveUnanswered >= 3) {
      // 连续未回复达到上限后静默暂停，不打扰用户；下次用户发言时恢复。
      return;
    }
    // 上一个请求还没回完，这次主动回复顺延重排。
    if (_loading) {
      final minMin = (int.tryParse(
                  await DBManager().getKV('proactive_min_minutes') ?? '') ??
              60)
          .clamp(1, 1440);
      final maxMin = (int.tryParse(
                  await DBManager().getKV('proactive_max_minutes') ?? '') ??
              90)
          .clamp(minMin, 1440);
      _restartProactiveTimer(minMin, maxMin);
      return;
    }
    try {
      setState(() {
        _loading = true;
        _typing = true;
      });
      _scrollDown();
      final now = DateTime.now();
      final hour = now.hour;
      final part =
          hour < 6 ? '夜深了' : (hour < 12 ? '早上好' : (hour < 18 ? '下午好' : '晚上好'));
      final recent = _msgs.reversed
          .take(8)
          .map((m) =>
              '${m['role'] == 'user' ? '我' : _bot['name']}: ${m['content']}')
          .join('\n');
      final opener =
          '【主动回复】$part。请严格遵循你的系统人格、说话方式和分段习惯。根据最近对话决定：未结束就自然接着聊，已结束就开启一个合适的新话题。不要提及主动回复、指令或角色设置。回复分成 1-3 个短句，每句不超过 28 字，总字数不超过 80 字。最近对话：\n$recent';
      final result = await AIManager()
          .sendMessage(botId: botId, text: opener)
          .timeout(const Duration(minutes: 5));
      if (result['success'] == true && result['silent'] == true) {
        // 模型自行选择不打扰：不写空消息，也不记作未回应，重新持久化安排下次。
        final minMin = (int.tryParse(
                    await DBManager().getKV('proactive_min_minutes') ?? '') ??
                60)
            .clamp(1, 1440);
        final maxMin = (int.tryParse(
                    await DBManager().getKV('proactive_max_minutes') ?? '') ??
                90)
            .clamp(minMin, 1440);
        _restartProactiveTimer(minMin, maxMin);
        return;
      }
      if (result['success'] == true && mounted) {
        final aiMsg = <String, dynamic>{
          'id': result['message_id']?.toString() ??
              'm_${DateTime.now().millisecondsSinceEpoch}',
          'bot_id': botId,
          'role': 'assistant',
          'content': result['reply']?.toString() ?? '',
          'sources_json': null,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        setState(() => _msgs.add(aiMsg));
        final imagePath = result['image_path']?.toString();
        if (imagePath?.isNotEmpty == true) {
          setState(() => _msgs.add({
                'id': 'image_${DateTime.now().millisecondsSinceEpoch}',
                'bot_id': botId,
                'role': 'assistant',
                'type': 'image',
                'content': '',
                'file_path': imagePath,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              }));
        }
        // 一次主动回复后：未应答 +1 并持久化，重新计时（下一次若仍无人应答则累加）。
        _proactiveUnanswered++;
        DBManager()
            .setKV('proactive_unanswered_$botId', '$_proactiveUnanswered');
      }
    } catch (e, st) {
      debugPrint('[proactive] fire failed: $e');
      debugPrint(st.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _typing = false;
        });
        _scrollDown();
      }
      // 无论成功与否都重排下一轮；若已达上限则下次触发会自动暂停。
      final minMin = (int.tryParse(
                  await DBManager().getKV('proactive_min_minutes') ?? '') ??
              60)
          .clamp(1, 1440);
      final maxMin = (int.tryParse(
                  await DBManager().getKV('proactive_max_minutes') ?? '') ??
              90)
          .clamp(minMin, 1440);
      _restartProactiveTimer(minMin, maxMin);
    }
  }

  // ========== 发送消息 ==========
  Future<void> _send({
    String? img,
    String? document,
    String? mediaContext,
    // 合并防抖重发时置 true：不再新增用户气泡/入库，仅用当前文本向模型统一请求。
    bool noUserBubble = false,
  }) async {
    final text = _msgC.text.trim();
    img ??= _pendingImage;
    document ??= _pendingDocument;
    mediaContext ??= _pendingMediaContext;
    if (text.isEmpty &&
        img == null &&
        document == null &&
        mediaContext == null) {
      if (mounted) setState(() => _hasText = false);
      return;
    }

    // 用户主动发言：清零主动回复未应答计数并重置计时。
    _onUserInteracted();

    final botId = _bot['id']?.toString() ?? '';
    unawaited(EmotionStateService.instance.observeUserMessage(botId, text));
    final now = DateTime.now().millisecondsSinceEpoch;

    // ===== 防抖/合并 =====
    // 上一条请求还在飞（机器人尚未回完）时再发消息：不再像旧实现那样直接丢弃，
    // 而是作废在途请求的渲染（_requestGen++），把新文本并入待重发队列，先上屏
    // 气泡并入库存档；等旧请求 finally 结束后用合并文本统一重发一次。
    if (_loading) {
      final mergedMsg = <String, dynamic>{
        'id': 'm_${now}_q',
        'bot_id': botId,
        'role': 'user',
        'type':
            document != null ? 'document' : (img != null ? 'image' : 'text'),
        'content': text,
        'image': img,
        'file_path': document ?? img,
        'document_name': document?.split(Platform.pathSeparator).last,
        'timestamp': now,
      };
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
          _msgs.add(mergedMsg);
          _msgC.clear();
          _hasText = false;
        });
        _scrollDown();
      }
      try {
        await DBManager().insertMessage({
          'id': mergedMsg['id'],
          'bot_id': botId,
          'role': 'user',
          'type':
              document != null ? 'document' : (img == null ? 'text' : 'image'),
          'content': text,
          'file_path': document ?? img,
          'mood': null,
          'timestamp': now,
        }).timeout(const Duration(seconds: 12));
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

    late final Map<String, dynamic> msg;
    if (!noUserBubble) {
      msg = <String, dynamic>{
        'id': 'm_$now',
        'bot_id': botId,
        'role': 'user',
        'type':
            document != null ? 'document' : (img != null ? 'image' : 'text'),
        'content': text,
        'image': img,
        'file_path': document ?? img,
        'document_name': document?.split(Platform.pathSeparator).last,
        'timestamp': now,
      };

      // 先更新界面，确保点击后立即看到气泡并清空输入框。
      if (mounted) {
        setState(() {
          _loading = true;
          _typing = true;
          _msgsLoading = false;
          _msgs.add(msg);
          _msgC.clear();
          _pendingImage = null;
          _pendingDocument = null;
          _pendingMediaContext = null;
          _hasText = false;
        });
        _scrollDown();
      }
    }

    try {
      if (!noUserBubble) {
        try {
          // chat_history 的真实字段是 type / file_path，不能把 UI 专用 image
          // 字段直接写库；否则 SQLite 会因“no column named image”静默失败。
          await DBManager().insertMessage({
            'id': msg['id'],
            'bot_id': botId,
            'role': 'user',
            'type': document != null
                ? 'document'
                : (img == null ? 'text' : 'image'),
            'content': text,
            'file_path': document ?? img,
            'mood': null,
            'timestamp': now,
          }).timeout(const Duration(seconds: 12));
        } catch (e) {
          debugPrint('[send] persist user message failed: $e');
        }
      }
      final cm = _bot['chat_model']?.toString().trim() ?? '';
      final localModelId = (await SharedPreferences.getInstance().then(
                  (prefs) => prefs.getString('local_chat_model_$botId')) ??
              '')
          .trim();
      if (cm.isEmpty && localModelId.isEmpty) {
        final providers = await DBManager().queryChatProviders();
        if (providers.isEmpty) {
          throw StateError('未配置聊天模型，请在 API 设置中添加远程模型或选择本地 GGUF 后再发送');
        }
      }

      final documentNotice = document == null
          ? null
          : await MediaPreprocessor().documentText(document);
      final preparedContext = mediaContext ?? documentNotice;
      final modelText = preparedContext == null
          ? text
          : (text.isEmpty ? preparedContext : '$text\n$preparedContext');

      final history = _msgs
          .where((m) => (m['content'] as String?)?.isNotEmpty == true)
          .map((m) {
        final isCurrent = !noUserBubble && m['id'] == msg['id'];
        final content = isCurrent ? modelText : _modelReadableContent(m);
        return {'role': m['role'], 'content': content};
      }).toList();
      // 合并重发（noUserBubble）时不新增用户气泡，仅把合并后的完整文本作为
      // 本次用户请求追加到上下文末尾，机器人统一回复一次。
      if (noUserBubble || (preparedContext != null && text.isEmpty)) {
        history.add({'role': 'user', 'content': modelText});
      }

      var imgB64 = '';
      if (img != null) {
        imgB64 = base64Encode(await File(img).readAsBytes());
      }

      debugPrint('[send] request start bot=$botId model=$cm');
      final db = DBManager();
      final segmentedReply =
          (await db.getKV('segmented_reply_enabled')) != 'false';
      // 分段回复需要等到完整文本才能按句子拆分，避免与流式字符气泡互相覆盖。
      // 分段与流式展示可以共存：流式气泡用于等待首句，完整回复回来后
      // 再按句落库并依次展示，不能因为开启分段就把流式功能关闭。
      final streamEnabled = (await db.getKV('streaming_output')) != 'false';
      Map<String, dynamic>? streamingMessage;
      var pendingDisplay = '';
      if (streamEnabled && localModelId.isEmpty && mounted) {
        streamingMessage = <String, dynamic>{
          'id': 'stream_${DateTime.now().millisecondsSinceEpoch}',
          'bot_id': botId,
          'role': 'assistant',
          'type': 'text',
          'content': '',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        final speed =
            (int.tryParse(await DBManager().getKV('streaming_speed') ?? '') ??
                    50)
                .clamp(1, 100);
        final interval = Duration(milliseconds: 30 + ((100 - speed) * 7));
        final batch = (1 + speed ~/ 18).clamp(1, 6);
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
      // First local GGUF load and CPU generation can legitimately take longer
      // than a remote HTTP request. Keep the short timeout for providers while
      // allowing local inference enough time to finish.
      // 远程模型首 token、工具调用或冷启动可能超过 30 秒；30 秒会把仍在执行的
      // 正常请求误判为失败。网络请求本身仍由 AI 层设置连接/空闲超时。
      final requestTimeout = localModelId.isEmpty
          ? const Duration(minutes: 2)
          : const Duration(minutes: 5);
      final result = await AIManager()
          .chatResult(
            botId: botId,
            messages: history,
            imageBase64: imgB64,
            persistResponse: persistThisReply,
            // UI intentionally waits for the complete, protocol-filtered response.
            // Raw provider deltas can contain internal mood/tool tags.
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
      final content = (result['reply']?.toString() ?? '').trim().isEmpty
          ? '[X] 模型返回了空内容，请检查模型名称和 API 配置'
          : result['reply'].toString();
      final aiMsg = <String, dynamic>{
        'id': result['message_id']?.toString() ??
            'm_${DateTime.now().millisecondsSinceEpoch}',
        'bot_id': botId,
        'role': 'assistant',
        'content': content,
        'sources_json':
            result['sources'] == null ? null : jsonEncode(result['sources']),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      // AIManager 已将本次 assistant 消息（含情绪/TTS 后台升级）持久化到 chat_history；
      // 这里仅追加内存气泡，避免同一回复被写入两次、重进页面后出现重复消息。

      // ===== 防抖/合并：代次拦截 =====
      // 请求期间用户又发了新消息（_requestGen 变化），本次回复已被合并覆盖：
      // 不再渲染、也不再落库（落库已由 persistThisReply 控制），交给 finally
      // 用合并后的文本统一重发一次。
      if (myGen != _requestGen) {
        _streamDisplayTimer?.cancel();
        _streamDisplayTimer = null;
        if (streamingMessage != null && mounted) {
          setState(() => _msgs.remove(streamingMessage));
        }
        return;
      }

      // ===== 模拟打字机（流式开启、非分段）=====
      // 用户需求：无论厂商是否回传 SSE 增量，前端都等服务商完整回复后再用打字机
      // 逐字渲染，而不是边生成边显示。完整 content 收到后统一喂给字幕定时器上屏，
      // 播完后定格为完整内容。
      final needsTypewriter =
          streamingMessage != null && !segmentedReply && content.isNotEmpty;
      if (needsTypewriter && mounted) {
        _streamDisplayTimer?.cancel();
        pendingDisplay = content;
        final tm = streamingMessage;
        final speed =
            (int.tryParse(await DBManager().getKV('streaming_speed') ?? '') ??
                    50)
                .clamp(1, 100);
        final interval = Duration(milliseconds: 30 + ((100 - speed) * 7));
        final batch = (1 + speed ~/ 18).clamp(1, 6);
        _streamDisplayTimer = Timer.periodic(interval, (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (pendingDisplay.isEmpty) {
            timer.cancel();
            _streamDisplayTimer = null;
            setState(() {
              tm['id'] = aiMsg['id'];
              tm['content'] = content;
              tm['timestamp'] = aiMsg['timestamp'];
            });
            _scrollDown(animated: false);
            return;
          }
          final take =
              pendingDisplay.length < batch ? pendingDisplay.length : batch;
          final chunk = pendingDisplay.substring(0, take);
          pendingDisplay = pendingDisplay.substring(take);
          setState(() => tm['content'] = '${tm['content']}$chunk');
          if (pendingDisplay.isEmpty ||
              tm['content'].toString().length % 80 < batch) {
            _scrollDown(animated: false);
          }
        });
      }

      if (mounted) {
        // 流式气泡已通过 SSE 增量逐字上屏。无论是否开启分段，都保留这个气泡并
        // 直接定格为完整回复——避免“整段文字先消失、再逐句重放”的观感，从而保证
        // 开启分段后流水输出依旧正常生效。分段的落库与句间节奏仍在分支内处理。
        if (streamingMessage != null) {
          if (segmentedReply) {
            // 分段开启：先移除流式占位气泡，首句立即出现，之后每句随机延迟
            // 0.5–1s（配合全局随机延迟叠加）逐条上屏，并逐句落库。
            _streamDisplayTimer?.cancel();
            _streamDisplayTimer = null;
            final segments = _splitReplySegments(content);
            final baseTimestamp = aiMsg['timestamp'] as int;
            // AIManager already persisted all segments before this UI-only animation.
            if (!mounted) return;
            setState(() => _msgs.remove(streamingMessage));
            for (var index = 0; index < segments.length; index++) {
              if (index > 0) await _applyRandomReplyDelay(db);
              if (!mounted) return;
              final segMsg = Map<String, dynamic>.from(aiMsg)
                ..['id'] = index == 0
                    ? aiMsg['id'].toString()
                    : '${aiMsg['id']}_segment_$index'
                ..['content'] = segments[index]
                ..['timestamp'] = baseTimestamp + index;
              setState(() => _msgs.add(segMsg));
              _scrollDown();
            }
          } else if (needsTypewriter) {
            // 模拟打字机正在逐字上屏（provider 整段返回、未触发真实 SSE）。
            // 这里不动气泡，由打字机定时器播完后再统一定格 id / 时间戳 / 完整内容。
          } else {
            // The bubble has already been updated from real SSE deltas. Keep its
            // in-memory identity but normalize its final text and database ID.
            setState(() {
              streamingMessage!['id'] = aiMsg['id'];
              streamingMessage['content'] = content;
              streamingMessage['timestamp'] = aiMsg['timestamp'];
            });
          }
        } else if (segmentedReply) {
          final segments = _splitReplySegments(content);
          final baseTimestamp = aiMsg['timestamp'] as int;
          // Below delays affect only the visible foreground animation.
          for (var index = 0; index < segments.length; index++) {
            // 句间自然等待：首句立即上屏（保证响应感），之后每句间 400–1000ms。
            if (index > 0) await _applyRandomReplyDelay(db);
            if (!mounted) return;
            final segId = index == 0
                ? aiMsg['id'].toString()
                : '${aiMsg['id']}_segment_$index';
            final segmentMessage = Map<String, dynamic>.from(aiMsg)
              ..['id'] = segId
              ..['content'] = segments[index]
              ..['timestamp'] = baseTimestamp + index;
            setState(() => _msgs.add(segmentMessage));
            _scrollDown();
          }
        } else {
          await _applyRandomReplyDelay(db);
          if (!mounted) return;
          setState(() => _msgs.add(aiMsg));
        }
        final imagePath = result['image_path']?.toString();
        if (imagePath?.isNotEmpty == true) {
          setState(() => _msgs.add({
                'id': 'image_${DateTime.now().millisecondsSinceEpoch}',
                'bot_id': botId,
                'role': 'assistant',
                'type': 'image',
                'content': '',
                'file_path': imagePath,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              }));
        }
        final sticker = result['sticker'];
        if (sticker is Map) {
          // sticker 已由 AIManager 落库；content 只用于内部分类，不能作为
          // 可见正文展示，避免把“开心/表情包类型”等协议泄漏给用户。
          setState(() => _msgs.add({
                'id': 'msg_s_${(aiMsg['timestamp'] as int) + 1000}',
                'bot_id': botId,
                'role': 'assistant',
                'type': 'sticker',
                'content': '',
                'file_path': sticker['file_path']?.toString(),
                'timestamp': (aiMsg['timestamp'] as int) + 1000,
              }));
          _scrollDown();
        }
      }
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

  Future<void> _transcribeRecordedAudio(
    Map<String, dynamic> message,
    String audioPath,
  ) async {
    final botId = _bot['id']?.toString() ?? '';
    if (botId.isEmpty) return;

    final transcript = await AIManager()
        .transcribeAudio(botId: botId, audioPath: audioPath)
        .timeout(const Duration(seconds: 50), onTimeout: () => null);
    if (transcript == null || transcript.isEmpty) return;

    try {
      await DBManager()
          .updateMessageContent(message['id'].toString(), transcript);
    } catch (e) {
      debugPrint('[stt] persist transcript failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() => message['content'] = transcript);

    // Only a successful, persisted transcript is sent to the chat model.
    // The original audio row remains type=audio with file_path intact.
    _msgC.text = transcript;
    _msgChanged();
    await _send();
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
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
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
      final p = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (p != null) {
        final fixed = await _fixHeic(p.path);
        if (mounted) setState(() => _pendingImage = fixed);
      }
    } else if (r == 'file') {
      try {
        await Permission.storage.request();
      } catch (_) {}
      final fp = await FilePicker.platform.pickFiles();
      final path = fp?.files.single.path;
      if (path == null || path.isEmpty) return;
      final extension = path.split('.').last.toLowerCase();
      const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
      const videoExtensions = {'mp4', 'm4v', 'mov', 'webm', '3gp'};
      const audioExtensions = {'m4a', 'mp3', 'wav', 'aac', 'ogg', 'opus'};
      if (imageExtensions.contains(extension)) {
        if (mounted) setState(() => _pendingImage = path);
      } else if (videoExtensions.contains(extension)) {
        if (mounted) setState(() => _pendingDocument = path);
      } else if (audioExtensions.contains(extension)) {
        final transcript = await AIManager().transcribeAudio(
          botId: _bot['id']?.toString() ?? '',
          audioPath: path,
        );
        await _send(
          document: path,
          mediaContext: transcript == null || transcript.isEmpty
              ? '[已附加音频：${path.split(Platform.pathSeparator).last}。未配置 STT 模型或转写失败，无法向文本模型提供语音内容。]'
              : '[音频转写]\\n$transcript',
        );
      } else {
        if (mounted) setState(() => _pendingDocument = path);
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
    String curStt = prefs.getString('stt_model_$botId') ?? '';
    String curTts = prefs.getString('tts_model_$botId') ??
        ((_bot['tts_model'] as String?)?.isNotEmpty == true
            ? _bot['tts_model'] as String
            : '');
    int curTok = prefs.getInt('max_token_$botId') ??
        (_bot['max_tokens'] as int? ?? 10000);

    final localDir = await getApplicationDocumentsDirectory();
    final localFiles = (await localDir
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.gguf'))
            .toList())
        .whereType<File>()
        .toList();
    String localChatId =
        (prefs.getString('local_chat_model_$botId') ?? '').trim();
    String localBackupId =
        (prefs.getString('local_backup_model_$botId') ?? '').trim();

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
                setSt(() {});
              }

              return TideDialogSurface(
                  backgroundColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  content: TideDialogs
                      .glassContent(context: ctx, maxWidth: 0.9, children: [
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
                      _chatModelPicker(
                        ctx,
                        providers,
                        localFiles,
                        curChat,
                        localChatId,
                        onRemotePick: (v) async {
                          curChat = v;
                          localChatId = '';
                          await prefs.remove('local_chat_model_$botId');
                          await pickModel('chat_model_$botId', v);
                        },
                        onLocalPick: (id) async {
                          localChatId = id;
                          curChat = '';
                          await prefs.setString('local_chat_model_$botId', id);
                          await pickModel('chat_model_$botId', '');
                        },
                      ),
                      // 备用模型可同时选择远程 Provider 或已下载的本地 GGUF。
                      _mLabel('备用模型'),
                      _chatModelPicker(
                        ctx,
                        providers,
                        localFiles,
                        curBak,
                        localBackupId,
                        onRemotePick: (v) async {
                          curBak = v;
                          localBackupId = '';
                          await prefs.remove('local_backup_model_$botId');
                          await pickModel('backup_model_$botId', v);
                        },
                        onLocalPick: (id) async {
                          localBackupId = id;
                          curBak = '';
                          await prefs.setString(
                              'local_backup_model_$botId', id);
                          await pickModel('backup_model_$botId', '');
                        },
                      ),
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
                      _mLabel('STT模型'),
                      _modelPicker(ctx, providers, curStt, (v) async {
                        curStt = v;
                        await pickModel('stt_model_$botId', v);
                      }),
                      // TTS 模型独立：从 tts_provider_list 读取，额外展示音色字段（可选，不配置则纯文字回复）
                      _mLabel('TTS模型'),
                      _modelPicker(ctx, ttsProviders, curTts, (v) async {
                        curTts = v;
                        await pickModel('tts_model_$botId', v, isTts: true);
                      }),
                      _mLabel('最大上下文Token'),
                      _tokenField(ctx, curTok, (v) async {
                        curTok = v;
                        await prefs.setInt('max_token_$botId', v);
                        await DBManager().updateBot(botId, {'max_tokens': v});
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

  Widget _chatModelPicker(
    BuildContext ctx,
    List<Map<String, dynamic>> providers,
    List<File> localFiles,
    String remoteId,
    String localId, {
    required Future<void> Function(String value) onRemotePick,
    required Future<void> Function(String id) onLocalPick,
  }) {
    final remote = providers.firstWhereOrNull((p) => p['id'] == remoteId);
    final localFile = localFiles.firstWhereOrNull(
      (file) =>
          file.path
              .split(Platform.pathSeparator)
              .last
              .replaceFirst(RegExp(r'\.gguf$'), '') ==
          localId,
    );
    final display = localFile != null
        ? '本地 · $localId'
        : remote != null
            ? '${_providerTitle(remote)} · ${remote['model']?.toString().trim().isNotEmpty == true ? remote['model'].toString().trim() : '未填写模型名'}'
            : providers.isEmpty && localFiles.isEmpty
                ? '无可用模型'
                : '未选择';

    return GestureDetector(
      onTap: () {
        showTideSheet(
          context: ctx,
          height: 420,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: const Text('不选择',
                    style: TextStyle(fontFamily: 'TideFont', fontSize: 14)),
                subtitle: const Text('清除当前聊天模型配置',
                    style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                trailing: remoteId.isEmpty && localId.isEmpty
                    ? Icon(Icons.check, color: TideTheme.of(ctx).primary)
                    : null,
                onTap: () async {
                  await onLocalPick('');
                  Navigator.pop(ctx);
                },
              ),
              if (localFiles.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('已下载的本地模型',
                      style: TextStyle(
                          fontFamily: 'TideFont', fontWeight: FontWeight.w600)),
                ),
                for (final file in localFiles)
                  Builder(builder: (context) {
                    final id = file.path
                        .split(Platform.pathSeparator)
                        .last
                        .replaceFirst(RegExp(r'\.gguf$'), '');
                    return ListTile(
                      leading: const Icon(Icons.memory_rounded),
                      title: Text(id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'TideFont', fontSize: 14)),
                      subtitle: Text(
                        '本地 GGUF · ${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB',
                        style: const TextStyle(
                            fontFamily: 'TideFont', fontSize: 12),
                      ),
                      trailing: localId == id
                          ? Icon(Icons.check, color: TideTheme.of(ctx).primary)
                          : null,
                      onTap: () async {
                        await onLocalPick(id);
                        Navigator.pop(ctx);
                      },
                    );
                  }),
              ],
              if (providers.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('API 模型',
                      style: TextStyle(
                          fontFamily: 'TideFont', fontWeight: FontWeight.w600)),
                ),
                for (final provider in providers)
                  ListTile(
                    title: Text(_providerTitle(provider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'TideFont', fontSize: 14)),
                    subtitle: Text(_providerSub(provider),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'TideFont', fontSize: 12)),
                    trailing: localId.isEmpty && remoteId == provider['id']
                        ? Icon(Icons.check, color: TideTheme.of(ctx).primary)
                        : null,
                    onTap: () async {
                      await onRemotePick(provider['id'] as String);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ],
          ),
        );
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: TideTheme.of(ctx).surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: TideTheme.of(ctx).textStrong,
                  fontFamily: 'TideFont')),
        ),
      ),
    );
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
                        await DBManager().deleteMessages(_bot['id'] as String);
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
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: isUser
            ? TideTheme.of(context).primary
            : TideTheme.of(context).buttonSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _toggleAudio(path),
            icon: Icon(
              active && _audioPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: foreground,
              size: 28,
            ),
          ),
          SizedBox(
            width: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  min: 0,
                  max: max,
                  value: value,
                  onChanged: !active || duration.inMilliseconds <= 0
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
                    Text(_formatAudioTime(duration),
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
      height: 230,
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
          _inputBar()
        ]),
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
    final hasStt = (prefs.getString('stt_model_$botId') ?? '').isNotEmpty;
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
    final detail = switch (code?.toString().toLowerCase()) {
      '400' => '请求参数错误：检查模型名称、消息格式、附件类型和请求体限制。',
      '401' || '403' => '鉴权或权限失败：检查 API Key、授权范围，以及 Base URL 是否属于该密钥对应的服务。',
      '402' => '服务余额不足：请到模型提供商后台充值或更换有可用余额的 API Key。',
      '404' => '接口或模型不存在：检查 Base URL 是否包含多余路径，并确认所填模型名称可用。',
      '408' || 'timeout' => '请求超时：检查网络和服务端状态，降低附件大小或生成长度后重试。',
      '409' => '请求冲突：检查是否重复提交，等待上一请求结束后再试。',
      '429' => '请求过于频繁或触发限流：稍后重试，降低发送频率，或换用备用模型。',
      '500' || '502' || '503' || '504' => '模型服务暂时不可用：稍后重试，检查服务商状态页，或切换备用模型。',
      'network' ||
      'dns' ||
      'connection refused' =>
        '网络连接失败：检查设备网络、Base URL、DNS、代理、防火墙和模型服务状态。',
      'ssl' ||
      'tls' ||
      'certificate' =>
        '安全连接失败：检查 Base URL 的 HTTPS 证书、系统时间和代理证书配置。',
      'empty response' ||
      'invalid response' =>
        '服务端返回为空或格式异常：检查接口兼容性、模型名称和服务端日志。',
      _ => '请检查聊天模型、Base URL、API Key、模型名称、附件和网络配置。',
    };
    return '$detail\\n\\n如果按照提示检查后仍然持续失败，可以复制完整日志联系作者。';
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

  String _modelReadableContent(Map<String, dynamic> message) {
    if (message['type']?.toString() != 'shared_post') {
      return message['content']?.toString() ?? '';
    }
    try {
      final raw = jsonDecode(message['content']?.toString() ?? '');
      if (raw is Map) {
        final author = raw['author']?.toString().trim() ?? '匿名';
        final content = raw['content']?.toString().trim() ?? '';
        final imagePath = raw['image_path']?.toString().trim() ?? '';
        final timestamp = raw['timestamp'];
        return '用户分享了一条动态。作者：$author；发布时间：${timestamp ?? '未知'}；文字：$content；'
            '图片：${imagePath.isEmpty ? '无' : '已附带本地图片，路径为 $imagePath'}。请像看到了这条动态一样自然回应。';
      }
    } catch (_) {}
    return '用户分享了一条动态：${message['content'] ?? ''}';
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
                child: Image.file(File(imagePath),
                    width: double.infinity, height: 150, fit: BoxFit.cover)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        final documentName =
            m['document_name']?.toString().trim().isNotEmpty == true
                ? m['document_name'].toString()
                : (documentPath?.split(Platform.pathSeparator).last ?? '文档');
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
                          if (hasDocument)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? TideTheme.of(context).primary
                                    : TideTheme.of(context).buttonSecondary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.insert_drive_file_rounded,
                                      color: isUser
                                          ? Colors.white
                                          : TideTheme.of(context).primary),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      documentName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isUser
                                            ? Colors.white
                                            : TideTheme.of(context).textStrong,
                                        fontFamily: 'TideFont',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // 图片
                          if (hasImg && File(imagePath!).existsSync())
                            GestureDetector(
                                onTap: () => _previewImg(imagePath),
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Image.file(
                                          File(imagePath),
                                          fit: BoxFit.cover,
                                          width: isSticker ? 112 : 180,
                                          height: isSticker ? 112 : null,
                                          cacheWidth: isSticker ? 224 : 360,
                                        )))),
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
    final source = sources.last;
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: source['title'] ?? '打开来源',
        child: InkWell(
          onTap: () => launchUrl(Uri.parse(source['url']!),
              mode: LaunchMode.externalApplication),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.only(top: 6, left: 8),
            child: Icon(Icons.language_rounded,
                size: 16, color: TideTheme.of(context).primary),
          ),
        ),
      ),
    );
  }

// 音频时长由播放器进度组件统一显示。

  // 富文本解析：旁白括号灰化
  Widget _parseText(String text, bool isUser) {
    final spans = <TextSpan>[];
    final reg = RegExp(r'\(.*?\)');
    int last = 0;
    for (var m in reg.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(
            text: text.substring(last, m.start),
            style: TextStyle(
                color: isUser ? Colors.white : TideTheme.of(context).textStrong,
                fontSize: 14,
                fontFamily: 'TideFont')));
      }
      spans.add(TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
              color: isUser
                  ? Colors.white.withValues(alpha: 0.6)
                  : TideTheme.of(context).textWeak,
              fontSize: 12,
              fontFamily: 'TideFont',
              fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(
          text: text.substring(last),
          style: TextStyle(
              color: isUser ? Colors.white : TideTheme.of(context).textStrong,
              fontSize: 14,
              fontFamily: 'TideFont')));
    }
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isUser
                ? TideTheme.of(context).primary
                : TideTheme.of(context).bubbleAi,
            borderRadius: BorderRadius.circular(16)),
        child: RichText(text: TextSpan(children: spans)));
  }

  Widget _inputBar() {
    final theme = TideTheme.of(context);
    return SafeArea(
      top: false,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _bottomBarCtrl, curve: Curves.easeOutCubic)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasBg
                      ? theme.glass.withValues(alpha: 0.72)
                      : theme.surfaceVariant.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.transparent),
                  boxShadow: theme.isDark
                      ? null
                      : [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '添加图片或文件',
                      onPressed: _pickMedia,
                      icon: Icon(Icons.add_rounded,
                          size: 24, color: theme.iconMuted),
                    ),
                    if (_pendingImage != null || _pendingDocument != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InputChip(
                          avatar: Icon(
                              _pendingImage != null
                                  ? Icons.image_rounded
                                  : Icons.attach_file_rounded,
                              size: 18),
                          label: SizedBox(
                              width: 82,
                              child: Text(
                                  (_pendingImage ?? _pendingDocument!)
                                      .split(Platform.pathSeparator)
                                      .last,
                                  overflow: TextOverflow.ellipsis)),
                          onDeleted: () => setState(() {
                            _pendingImage = null;
                            _pendingDocument = null;
                            _pendingMediaContext = null;
                          }),
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        focusNode: _inputFocus,
                        controller: _msgC,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: TextStyle(
                            fontSize: 15,
                            fontFamily: 'TideFont',
                            color: theme.textStrong),
                        decoration: InputDecoration(
                          hintText: '发送新消息...',
                          hintStyle: TextStyle(
                              color: theme.textFaint,
                              fontSize: 14,
                              fontFamily: 'TideFont'),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _isRecording ? '结束录音' : '录音',
                      onPressed: _toggleRec,
                      icon: Icon(Icons.mic_rounded,
                          size: 24,
                          color: _isRecording ? Colors.red : theme.iconMuted),
                    ),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        tooltip: '发送',
                        splashRadius: 24,
                        onPressed: _send,
                        icon: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.primary.withValues(
                                alpha: (_hasText ||
                                        _pendingImage != null ||
                                        _pendingDocument != null)
                                    ? 1
                                    : 0.48),
                            boxShadow: [
                              BoxShadow(
                                  color: theme.primary.withValues(
                                      alpha: _hasText ? 0.38 : 0.12),
                                  blurRadius: 8)
                            ],
                          ),
                          child: const Icon(Icons.arrow_upward_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
