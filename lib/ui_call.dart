import 'dart:async';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'call_message.dart';
import 'app_permissions.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'ui_components.dart';
import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';

/// 全屏语音通话界面；通过 AIManager 串联 STT、聊天和 TTS。
class CallPage extends StatefulWidget {
  final Map<String, dynamic> bot;
  final bool hasStt;
  final bool hasTts;
  final VoidCallback? onOpenSettings;

  const CallPage({
    super.key,
    required this.bot,
    required this.hasStt,
    required this.hasTts,
    this.onOpenSettings,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;
  bool _muted = false;
  bool _speakerMuted = false;
  bool _processing = false;
  String _caption = '';
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _recordingPath;
  bool _recording = false;
  bool _finishingRecording = false;
  bool _botSpeaking = false;
  bool _speechDetected = false;
  double _soundLevel = 0;
  double? _noiseFloor;
  StreamSubscription<Amplitude>? _ampSub;

  /// 机器人语音播放完成（或被分贝打断）的状态门闩；每次播放前重置。
  Completer<void>? _playDone;
  StreamSubscription<void>? _playSub;
  final DateTime _startedAt = DateTime.now();
  final List<String> _transcript = [];
  final List<CallMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final ScrollController _messageController = ScrollController();
  bool _showTextComposer = false;
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;
  bool _ending = false;

  /// 是否启用分贝打断（仅机器人说话期间监听用户是否插话）。
  bool _vadActive = false;

  // A fixed dBFS threshold breaks across microphones and misses whispering.
  // Speech must rise above the measured room floor for several samples.
  static const int _speechStartTicks = 3;
  static const int _silentStopTicks = 9;
  static const double _minimumVoiceLevel = -52;
  static const double _speechOverNoise = 9;
  int _silentTicks = 0;
  int _voiceTicks = 0;
  Timer? _autoStopTimer;

  void _appendMessage(String text, {required bool isUser}) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    setState(() => _messages.add(CallMessage(
          text: normalized,
          isUser: isUser,
          timestamp: DateTime.now(),
        )));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageController.hasClients) {
        _messageController.animateTo(
          _messageController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _processing || _ending) return;
    _textController.clear();
    _textFocusNode.unfocus();
    setState(() => _showTextComposer = false);
    await _runTextTurn(text);
  }

  void _openTextComposer() {
    if (_processing || _ending) return;
    setState(() => _showTextComposer = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  Future<void> _runTextTurn(String text) async {
    _appendMessage(text, isUser: true);
    _transcript.add('用户：$text');
    if (mounted)
      setState(() {
        _processing = true;
        _caption = '正在等待回复…';
      });
    try {
      final reply = await AIManager()
          .sendMessage(botId: widget.bot['id'].toString(), text: text)
          .timeout(const Duration(minutes: 2));
      final answer =
          reply['reply']?.toString() ?? reply['content']?.toString() ?? '';
      if (answer.trim().isEmpty) {
        if (mounted)
          setState(() => _caption = reply['error']?.toString() ?? '机器人没有返回回复');
        return;
      }
      _appendMessage(answer, isUser: false);
      _transcript.add('机器人：$answer');
      if (mounted) setState(() => _caption = answer);
      final ttsId = widget.bot['tts_model']?.toString() ?? '';
      if (widget.hasTts && ttsId.isNotEmpty) {
        final audioPath = await AIManager().generateTTS(answer, ttsId);
        if (audioPath?.isNotEmpty == true) await _playBotReply(audioPath!);
      }
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '文字轮次失败：$error');
      if (mounted) setState(() => _caption = '文字回复失败：$error');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// 开始监听录音振幅（前提是录音已在运行）。
  void _startAmpMonitor() {
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen(_onAmplitudeChanged);
  }

  void _stopAmpMonitor() {
    _ampSub?.cancel();
    _ampSub = null;
  }

  /// 分贝监听回调：
  /// - 机器人说话期间（_vadActive）：检测到人声即打断播放，让用户插话；
  /// - 监听用户期间：累积静默计数，连续静默一段时间后自动结束录音并进入识别。
  void _onAmplitudeChanged(Amplitude amp) {
    if (_muted) return;
    final level = amp.current.clamp(-80.0, 0.0).toDouble();
    if (mounted) setState(() => _soundLevel = level);
    final floor = _noiseFloor ?? level;
    if (!_speechDetected && !_vadActive) {
      _noiseFloor = floor * .86 + level * .14;
    }
    final gate = (_noiseFloor ?? floor) + _speechOverNoise;
    final isVoice = level >= _minimumVoiceLevel && level >= gate;
    if (_vadActive) {
      if (isVoice) {
        _vadActive = false;
        _playSub?.cancel();
        _playSub = null;
        if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
        unawaited(_player.stop());
        if (mounted) setState(() => _botSpeaking = false);
      }
      return;
    }
    if (_recording && !_processing) {
      if (isVoice) {
        _voiceTicks++;
        _silentTicks = 0;
        if (!_speechDetected && _voiceTicks >= _speechStartTicks) {
          if (mounted) {
            setState(() {
              _speechDetected = true;
              _caption = '已识别到你的声音';
            });
          }
          AppLogService.instance.add('VOICE_CALL', '已检测到用户语音');
        }
      } else {
        _voiceTicks = 0;
        if (_speechDetected) _silentTicks++;
        if (_speechDetected && _silentTicks >= _silentStopTicks) {
          unawaited(_finishListening());
        }
      }
    }
  }

  /// 监听时的兜底定时器：保证 amplitude 回调不触发时也能自动结束。
  void _ensureAutoStopTimer() {
    _autoStopTimer?.cancel();
    // Amplitude callbacks are authoritative. This only prevents an abandoned
    // recording from running forever on devices that do not emit amplitudes.
    _autoStopTimer = Timer(const Duration(seconds: 30), () {
      if (_recording && !_processing && !_muted && !_vadActive) {
        unawaited(_finishListening());
      }
    });
  }

  Future<void> _startListening() async {
    if (_muted || _processing || _recording) return;
    AppLogService.instance.add('VOICE_CALL', '请求麦克风权限');
    if (!await AppPermissions.microphone(context)) {
      AppLogService.instance.add('VOICE_CALL', '麦克风权限未授予');
      return;
    }
    try {
      // 停止任何正在播放的机器人语音后再聆听。
      if (_player.state == PlayerState.playing) await _player.stop();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );
      _startAmpMonitor();
      _silentTicks = 0;
      _voiceTicks = 0;
      _speechDetected = false;
      _noiseFloor = null;
      _ensureAutoStopTimer();
      AppLogService.instance.add('VOICE_CALL', '录音已启动：$path');
      if (mounted) {
        setState(() {
          _recording = true;
          _caption = '正在聆听，请说话';
        });
      }
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '录音启动失败：$error');
      if (mounted) setState(() => _caption = '无法开始录音：$error');
    }
  }

  Future<void> _finishListening() async {
    if (_finishingRecording) return;
    _finishingRecording = true;
    _autoStopTimer?.cancel();
    _stopAmpMonitor();
    if (!_recording) {
      _finishingRecording = false;
      return;
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _caption = '正在提交语音识别…';
      });
    }
    try {
      final path = await _recorder.stop();
      AppLogService.instance.add(
        'VOICE_CALL',
        path == null ? '录音未生成文件' : '录音已停止：$path，准备请求 STT',
      );
      _vadActive = false;
      _speechDetected = false;
      if (path == null || path.isEmpty) {
        if (mounted) setState(() => _caption = '录音文件为空，无法请求语音识别');
        return;
      }
      _recordingPath = path;
      await _runVoiceTurn();
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '录音停止或提交失败：$error');
      if (mounted) setState(() => _caption = '录音处理失败：$error');
    } finally {
      _finishingRecording = false;
    }
  }

  Future<void> _runVoiceTurn() async {
    if (_processing || _recordingPath == null) return;
    if (!widget.hasStt) {
      AppLogService.instance.add('VOICE_CALL', 'STT 不可用，无法识别本次录音');
      if (mounted) setState(() => _caption = '未配置语音识别服务，可在设置中启用 STT');
      return;
    }
    if (mounted) {
      setState(() {
        _processing = true;
        _caption = '正在识别语音…';
      });
    }
    AppLogService.instance.add('VOICE_CALL', 'STT 开始：${_recordingPath!}');
    try {
      final text = await AIManager()
          .transcribeAudio(
              botId: widget.bot['id'].toString(), audioPath: _recordingPath!)
          .timeout(const Duration(seconds: 45));
      if (text == null || text.trim().isEmpty) {
        AppLogService.instance.add('VOICE_CALL', 'STT 返回空文本');
        if (mounted) setState(() => _caption = '没有识别到语音');
        return;
      }
      AppLogService.instance
          .add('VOICE_CALL', 'STT 成功，文本长度 ${text.trim().length}');
      _transcript.add('用户：${text.trim()}');
      _appendMessage(text, isUser: true);
      if (mounted) setState(() => _caption = text);
      AppLogService.instance.add('VOICE_CALL', 'AI 请求开始');
      final reply = await AIManager()
          .sendMessage(botId: widget.bot['id'].toString(), text: text)
          .timeout(const Duration(minutes: 2));
      final answer =
          reply['reply']?.toString() ?? reply['content']?.toString() ?? '';
      if (answer.isEmpty) {
        AppLogService.instance
            .add('VOICE_CALL', 'AI 返回空回复：${reply['error'] ?? 'unknown'}');
        if (mounted) {
          setState(() => _caption = reply['error']?.toString() ?? '机器人没有返回回复');
        }
        return;
      }
      AppLogService.instance.add('VOICE_CALL', 'AI 回复成功，文本长度 ${answer.length}');
      _transcript.add('机器人：$answer');
      _appendMessage(answer, isUser: false);
      if (mounted) setState(() => _caption = answer);
      final ttsId = widget.bot['tts_model']?.toString() ?? '';
      if (ttsId.isEmpty || !widget.hasTts) {
        AppLogService.instance.add('VOICE_CALL', 'TTS 不可用，保留文字回复');
        return;
      }
      AppLogService.instance.add('VOICE_CALL', 'TTS 生成开始：$ttsId');
      final audioPath = await AIManager().generateTTS(answer, ttsId);
      if (audioPath == null || audioPath.isEmpty) {
        AppLogService.instance.add('VOICE_CALL', 'TTS 未生成音频，保留文字回复');
        return;
      }
      AppLogService.instance.add('VOICE_CALL', 'TTS 生成成功，开始播放');
      if (mounted) setState(() => _caption = '正在说话…');
      await _playBotReply(audioPath);
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '语音轮次失败：$error');
      if (mounted) setState(() => _caption = '语音通话失败：$error');
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        if (!_muted) await _startListening();
      }
    }
  }

  /// 播放机器人回复；播放期间监听录音，检测到用户声音（超过分贝阈值）即打断，
  /// 让用户随时插话。
  Future<void> _playBotReply(String audioPath) async {
    AppLogService.instance.add('VOICE_CALL', '开始播放 TTS 音频');
    final dir = await getApplicationDocumentsDirectory();
    final vadPath =
        '${dir.path}/call_vad_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: vadPath,
    );
    _playDone = Completer<void>();
    _startAmpMonitor();
    _vadActive = true;
    if (mounted) setState(() => _botSpeaking = true);
    _playSub?.cancel();
    _playSub = _player.onPlayerComplete.listen((event) {
      if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
    });
    // 兜底：若插件不触发 onPlayerComplete，则通过状态监听 stopped 结束本次播放。
    final stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!_vadActive) return; // 打断路径已由 _onAmplitudeChanged 处理，避免误结束
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
      }
    });
    await _player.setVolume(_speakerMuted ? 0 : 1);
    await _player.play(DeviceFileSource(audioPath));
    await _playDone?.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {},
    );
    _vadActive = false;
    if (mounted) setState(() => _botSpeaking = false);
    await _playSub?.cancel();
    _playSub = null;
    await stateSub.cancel();
    _stopAmpMonitor();
    await _recorder.stop();
    AppLogService.instance.add('VOICE_CALL', 'TTS 播放结束，VAD 录音已释放');
  }

  Future<void> _pauseBotReply() async {
    if (!_botSpeaking) return;
    _vadActive = false;
    if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
    await _player.stop();
    if (mounted) setState(() => _botSpeaking = false);
    AppLogService.instance.add('VOICE_CALL', '用户手动暂停机器人语音');
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    _autoStopTimer?.cancel();
    _vadActive = false;
    _stopAmpMonitor();
    final wasRecording = _recording;
    _recording = false;
    _botSpeaking = false;
    try {
      if (wasRecording) await _recorder.stop();
      await _player.stop();
    } catch (_) {}

    final duration = DateTime.now().difference(_startedAt);
    if (duration.inMilliseconds < 1000) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final botId = widget.bot['id']?.toString() ?? '';
    if (botId.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final durationText = _formatDuration(duration);
    var summary = '本次通话未获取到有用信息。';
    var failed = false;
    if (_transcript.isNotEmpty) {
      try {
        final result = await AIManager().sendMessage(
          botId: botId,
          text:
              '这是内部通话总结任务，不要和用户聊天。通话时长：$durationText。根据以下真实通话记录，写一份详细、自然的摘要，保留双方重点、结论、待办和未解决问题；不得编造。只输出摘要正文。\n\n${_transcript.join('\n')}',
          persistResponse: false,
          includeChatHistory: false,
          enableAutoSummary: false,
          skipLifeState: true,
          allowTools: false,
          forceSingleReply: true,
        );
        final generated = result['reply']?.toString().trim() ?? '';
        if (result['success'] == true && generated.isNotEmpty) {
          summary = generated;
        } else {
          failed = true;
          summary = '通话摘要生成失败：${result['error']?.toString() ?? '未知错误'}';
        }
      } catch (error) {
        failed = true;
        summary = '通话摘要生成失败：$error';
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await DBManager().insertMessage({
      'id': 'call_$now',
      'bot_id': botId,
      'role': 'assistant',
      'type': 'call_summary',
      'content': summary,
      'duration': duration.inSeconds,
      'mood': failed ? 'failed' : 'complete',
      'timestamp': now,
    });
    AppLogService.instance
        .add('VOICE_CALL', '通话结束：$durationText，摘要${failed ? '失败' : '已保存'}');
    if (mounted) Navigator.pop(context);
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final parts = <String>[];
    if (hours > 0) parts.add('$hours 小时');
    if (minutes > 0 || hours > 0) parts.add('$minutes 分钟');
    parts.add('$seconds 秒');
    return parts.join(' ');
  }

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted)
        setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
    if (widget.hasStt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startListening();
      });
    }
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _durationTimer?.cancel();
    _stopAmpMonitor();
    _textController.dispose();
    _textFocusNode.dispose();
    _messageController.dispose();
    _recorder.dispose();
    _player.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final ready = widget.hasStt;
    final name = widget.bot['name']?.toString().trim().isNotEmpty == true
        ? widget.bot['name'].toString()
        : 'TideBot';
    final avatar = widget.bot['avatar']?.toString() ?? '';

    return Scaffold(
      backgroundColor: theme.bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: _endCall,
                icon: Icon(Icons.close_rounded, color: theme.iconMuted),
                tooltip: '结束通话',
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 34, 28, 20),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _wave,
                      builder: (context, _) => SizedBox(
                        width: 150,
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_recording || _botSpeaking)
                              Container(
                                width: 124 + (_wave.value * 8),
                                height: 124 + (_wave.value * 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.primary.withValues(alpha: .22),
                                    width: 2,
                                  ),
                                ),
                              ),
                            TideBotAvatar(name: name, path: avatar, size: 104),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(name,
                        style: TextStyle(
                            color: theme.textStrong,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 3),
                    Text('${_callStateLabel()}  ·  ${_formatClock(_elapsed)}',
                        style: TextStyle(
                            color: ready ? theme.primary : theme.textWeak,
                            fontSize: 14,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 8),
                    Expanded(child: _messageList(theme)),
                    if (_showTextComposer) ...[
                      _textComposer(theme),
                      const SizedBox(height: 8),
                    ],
                    if (!ready && widget.onOpenSettings != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                          onPressed: widget.onOpenSettings,
                          icon: Icon(Icons.settings_rounded,
                              color: theme.primary),
                          label: Text('配置语音模型',
                              style: TextStyle(
                                  color: theme.primary,
                                  fontFamily: 'TideFont'))),
                    ],
                    if (ready) ...[
                      const SizedBox(height: 8),
                      _callActionButton(theme),
                    ],
                    const SizedBox(height: 12),
                    SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 64,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Align(
                                alignment: Alignment.topLeft,
                                child: _roundButton(
                                    icon: _muted
                                        ? Icons.mic_off_rounded
                                        : Icons.mic_rounded,
                                    label: _muted ? '已静音' : '静音',
                                    color: theme.surfaceVariant,
                                    iconColor: theme.textStrong,
                                    onTap: () async {
                                      TideHaptics.tap();
                                      if (_muted) {
                                        setState(() => _muted = false);
                                        await _startListening();
                                      } else {
                                        _vadActive = false;
                                        _autoStopTimer?.cancel();
                                        _stopAmpMonitor();
                                        _silentTicks = 0;
                                        if (_recording) await _recorder.stop();
                                        setState(() {
                                          _muted = true;
                                          _recording = false;
                                        });
                                      }
                                    })),
                            _roundButton(
                                icon: Icons.call_end_rounded,
                                label: '挂断',
                                color: const Color(0xFFE74C3C),
                                iconColor: Colors.white,
                                onTap: _endCall),
                            Align(
                                alignment: Alignment.topRight,
                                child: _roundButton(
                                    icon: _speakerMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    label: _speakerMuted ? '声音关闭' : '声音开启',
                                    color: theme.surfaceVariant,
                                    iconColor: theme.textStrong,
                                    onTap: () async {
                                      TideHaptics.tap();
                                      final next = !_speakerMuted;
                                      setState(() => _speakerMuted = next);
                                      await _player.setVolume(next ? 0 : 1);
                                    })),
                            Positioned(
                              right: 72,
                              top: 2,
                              child: IconButton(
                                tooltip: '文字回复',
                                onPressed: _showTextComposer
                                    ? null
                                    : _openTextComposer,
                                icon: Icon(Icons.edit_rounded,
                                    color: theme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageList(TideTheme theme) {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          _caption.isEmpty ? '正在自动监听，请直接说话' : _caption,
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.textFaint, fontFamily: 'TideFont'),
        ),
      );
    }
    return ListView.separated(
      controller: _messageController,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      itemCount: _messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final message = _messages[index];
        final color = message.isUser ? theme.primary : theme.surfaceVariant;
        return Align(
          alignment:
              message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : theme.textStrong,
                fontFamily: 'TideFont',
                height: 1.35,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _textComposer(TideTheme theme) => Row(
        children: [
          Expanded(
            child: TextField(
              focusNode: _textFocusNode,
              controller: _textController,
              enabled: !_processing && !_ending,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(),
              decoration: InputDecoration(
                hintText: '输入回复',
                isDense: true,
                filled: true,
                fillColor: theme.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '发送文字回复',
            onPressed: _processing ? null : _submitText,
            icon: Icon(Icons.send_rounded, color: theme.primary),
          ),
        ],
      );

  String _formatClock(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String _callStateLabel() {
    if (!widget.hasStt) return '需要配置语音';
    if (_muted) return '已静音';
    if (_botSpeaking) return '机器人正在说话';
    if (_processing) return '正在识别';
    if (_recording) return '正在聆听';
    return '通话中';
  }

  Widget _callActionButton(TideTheme theme) {
    final speaking = _botSpeaking;
    final listening = _recording;
    return FilledButton.icon(
      onPressed: !(speaking || listening) || _finishingRecording
          ? null
          : () async {
              TideHaptics.tap();
              if (speaking) {
                await _pauseBotReply();
              } else {
                await _finishListening();
              }
            },
      icon: Icon(speaking ? Icons.pause_rounded : Icons.check_rounded),
      label: Text(speaking ? '暂停' : '说完了'),
      style: FilledButton.styleFrom(
        backgroundColor: speaking ? theme.primary : theme.surfaceVariant,
        foregroundColor: speaking ? Colors.white : theme.textStrong,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onTap,
          onLongPress: onLongPress,
          radius: 34,
          child: CircleAvatar(
            radius: 29,
            backgroundColor: color,
            child: Icon(icon, color: iconColor),
          ),
        ),
        const SizedBox(height: 7),
        Text(label,
            style: const TextStyle(fontFamily: 'TideFont', fontSize: 12)),
      ],
    );
  }
}
