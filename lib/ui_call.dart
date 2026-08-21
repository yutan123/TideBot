import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'app_permissions.dart';
import 'call_wave_painter.dart';

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
    _autoStopTimer?.cancel();
    _stopAmpMonitor();
    if (!_recording) return;
    if (mounted) setState(() => _recording = false);
    try {
      final path = await _recorder.stop();
      AppLogService.instance
          .add('VOICE_CALL', path == null ? '录音未生成文件' : '录音已停止：$path');
      if (mounted) {
        setState(() {
          _recordingPath = path;
        });
      }
      _vadActive = false;
      _speechDetected = false;
      if (path != null && path.isNotEmpty) await _runVoiceTurn();
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '录音停止失败：$error');
      if (mounted) setState(() => _caption = '录音处理失败：$error');
    }
  }

  Future<void> _runVoiceTurn() async {
    if (_processing || _recordingPath == null) return;
    if (!widget.hasStt) {
      AppLogService.instance.add('VOICE_CALL', 'STT 不可用，无法识别本次录音');
      if (mounted) setState(() => _caption = '未配置语音识别服务，可在设置中启用 STT');
      return;
    }
    setState(() {
      _processing = true;
      _caption = '正在识别语音…';
    });
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
    if (widget.hasStt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startListening();
      });
    }
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _stopAmpMonitor();
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
                padding: const EdgeInsets.fromLTRB(28, 60, 28, 34),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _wave,
                      builder: (context, _) => SizedBox(
                        width: 230,
                        height: 230,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_recording)
                              CustomPaint(
                                size: const Size.square(230),
                                painter: CallWavePainter(
                                  phase: _wave.value,
                                  strength: ((_soundLevel + 58) / 45).clamp(
                                    0.08,
                                    1.0,
                                  ),
                                  color: theme.primary,
                                ),
                              ),
                            CircleAvatar(
                              radius: 57,
                              backgroundColor:
                                  theme.primary.withValues(alpha: 0.16),
                              backgroundImage: avatar.isNotEmpty
                                  ? FileImage(File(avatar))
                                  : null,
                              child: avatar.isEmpty
                                  ? Icon(
                                      Icons.smart_toy_rounded,
                                      size: 56,
                                      color: theme.primary,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      name,
                      style: TextStyle(
                        color: theme.textStrong,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'TideFont',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ready ? '语音通话准备就绪' : '还需要完成语音能力配置',
                      style: TextStyle(
                        color: ready ? theme.primary : theme.textWeak,
                        fontSize: 14,
                        fontFamily: 'TideFont',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ready
                          ? (_caption.isEmpty ? '正在自动监听，请直接说话' : _caption)
                          : '缺少：${widget.hasStt ? '' : 'STT 转写模型'}${!widget.hasStt ? '' : ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.textFaint,
                        fontSize: 13,
                        height: 1.5,
                        fontFamily: 'TideFont',
                      ),
                    ),
                    if (!ready && widget.onOpenSettings != null) ...[
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: widget.onOpenSettings,
                        icon:
                            Icon(Icons.settings_rounded, color: theme.primary),
                        label: Text(
                          '配置语音模型',
                          style: TextStyle(
                            color: theme.primary,
                            fontFamily: 'TideFont',
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (ready) _callActionButton(theme),
                    const SizedBox(height: 18),
                    SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 78,
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
                                },
                              ),
                            ),
                            _roundButton(
                              icon: Icons.call_end_rounded,
                              label: '挂断',
                              color: const Color(0xFFE74C3C),
                              iconColor: Colors.white,
                              onTap: _endCall,
                            ),
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
                                },
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

  Widget _callActionButton(TideTheme theme) {
    final speaking = _botSpeaking;
    final listening = _recording;
    return FilledButton.icon(
      onPressed: !(speaking || listening)
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
