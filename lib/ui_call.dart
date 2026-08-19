import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'app_permissions.dart';

import 'package:flutter/material.dart';
import 'theme.dart';
import 'ui_components.dart';
import 'ai.dart';
import 'app_log_service.dart';

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
  StreamSubscription<Amplitude>? _ampSub;

  /// 机器人语音播放完成（或被分贝打断）的状态门闩；每次播放前重置。
  Completer<void>? _playDone;
  StreamSubscription<void>? _playSub;

  /// 是否启用分贝打断（仅机器人说话期间监听用户是否插话）。
  bool _vadActive = false;

  /// 分贝阈值（dBFS），人声通常高于此值。
  static const double _vadThreshold = -32;

  /// 连续静默多少次后认为用户已说完，自动结束录音（约 1~1.8 秒）。
  static const int _silentStopTicks = 6;
  int _silentTicks = 0;
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
    // 打断阶段
    if (_vadActive) {
      if (amp.current > _vadThreshold) {
        _vadActive = false;
        // 先取消播放完成订阅，避免 stop 触发 onPlayerComplete 造成双重 complete。
        _playSub?.cancel();
        _playSub = null;
        if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
        _player.stop();
      }
      return;
    }
    // 监听用户说话阶段
    if (_recording && !_processing) {
      if (amp.current > _vadThreshold) {
        _silentTicks = 0;
      } else {
        _silentTicks++;
        if (_silentTicks >= _silentStopTicks) {
          _finishListening();
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
    if (!await AppPermissions.microphone(context)) return;
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
    _ensureAutoStopTimer();
    if (mounted) {
      setState(() {
        _recording = true;
        _caption = '正在聆听，请说话…';
      });
    }
  }

  Future<void> _finishListening() async {
    _autoStopTimer?.cancel();
    _stopAmpMonitor();
    if (!_recording) return;
    final path = await _recorder.stop();
    if (mounted) {
      setState(() {
        _recording = false;
        _recordingPath = path;
      });
    }
    _vadActive = false;
    if (path != null && path.isNotEmpty) await _runVoiceTurn();
  }

  Future<void> _runVoiceTurn() async {
    if (_processing || !widget.hasStt || _recordingPath == null) return;
    setState(() {
      _processing = true;
      _caption = '正在识别语音…';
    });
    AppLogService.instance.add('VOICE_CALL', '开始识别 ${_recordingPath!}');
    try {
      final text = await AIManager()
          .transcribeAudio(
              botId: widget.bot['id'].toString(), audioPath: _recordingPath!)
          .timeout(const Duration(seconds: 45));
      if (text == null || text.trim().isEmpty) {
        if (mounted) setState(() => _caption = '没有识别到语音');
        return;
      }
      if (mounted) setState(() => _caption = text);
      final reply = await AIManager()
          .sendMessage(botId: widget.bot['id'].toString(), text: text)
          .timeout(const Duration(minutes: 2));
      final answer =
          reply['reply']?.toString() ?? reply['content']?.toString() ?? '';
      if (answer.isEmpty) {
        if (mounted)
          setState(() => _caption = reply['error']?.toString() ?? '机器人没有返回回复');
        return;
      }
      if (mounted) setState(() => _caption = answer);
      final ttsId = widget.bot['tts_model']?.toString() ?? '';
      if (ttsId.isNotEmpty) {
        final audioPath = await AIManager().generateTTS(answer, ttsId);
        if (audioPath != null && audioPath.isNotEmpty) {
          if (mounted) setState(() => _caption = '正在说话…');
          await _playBotReply(audioPath);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _caption = '语音通话失败：$e');
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
    await _playSub?.cancel();
    _playSub = null;
    await stateSub.cancel();
    _stopAmpMonitor();
    await _recorder.stop();
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
                onPressed: () => Navigator.pop(context),
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
                      builder: (context, child) {
                        final amount = 0.82 + _wave.value * 0.18;
                        return SizedBox(
                          width: 230,
                          height: 230,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              for (var i = 0; i < 3; i++)
                                Transform.scale(
                                  scale: amount - i * 0.11,
                                  child: Container(
                                    width: 220 - i * 38,
                                    height: 220 - i * 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.primary.withValues(
                                        alpha: ready ? 0.08 + i * 0.025 : 0.035,
                                      ),
                                    ),
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
                        );
                      },
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _roundButton(
                          icon: _muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: _muted ? '已静音' : '静音',
                          color: theme.surfaceVariant,
                          iconColor: theme.textStrong,
                          onTap: () async {
                            TideHaptics.tap();
                            if (_muted) {
                              // 取消静音：重新开启自动监听
                              setState(() => _muted = false);
                              await _startListening();
                            } else {
                              // 静音：停止录音，不再监听
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
                        const SizedBox(width: 24),
                        _roundButton(
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
                        const SizedBox(width: 24),
                        _roundButton(
                          icon: Icons.call_end_rounded,
                          label: '挂断',
                          color: const Color(0xFFE74C3C),
                          iconColor: Colors.white,
                          onTap: () {
                            TideHaptics.tap();
                            Navigator.pop(context);
                          },
                        ),
                      ],
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
