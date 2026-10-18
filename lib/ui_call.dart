import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'call_message.dart';
import 'app_permissions.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'ui_components.dart';
import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';
import 'video_call_overlay.dart';

enum CallFlowState {
  idle,
  requestingPermission,
  recording,
  speechDetected,
  transcribing,
  generatingReply,
  synthesizing,
  playing,
  failed,
}

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
  CallFlowState _flowState = CallFlowState.idle;
  String _caption = '';
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _recordingPath;
  bool _recording = false;
  bool _finishingRecording = false;
  bool _botSpeaking = false;
  bool _speechDetected = false;
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
  AICancellationToken? _turnToken;

  /// 是否启用分贝打断（仅机器人说话期间监听用户是否插话）。
  bool _vadActive = false;

  /// 本轮通话流式输出是否已失败（失败后降级到非流式）
  bool _streamFailedThisCall = false;

  /// STT/TTS 实际配置的 provider ID
  String _sttProviderId = '';
  String _ttsProviderId = '';

  /// STT/TTS 自动检测状态
  bool _hasStt = false;
  bool _hasTts = false;

  /// 视频通话状态
  bool _videoEnabled = false;
  String? _generatedImagePath;
  final List<String> _capturedFrames = [];
  final GlobalKey<VideoCallOverlayState> _videoOverlayKey =
      GlobalKey<VideoCallOverlayState>();
// Keep the gate tolerant of Android devices whose amplitude reporting is
  // conservative. A user can always finish the current turn explicitly.
  static const int _speechStartTicks = 2; // 降低到2（400ms），更快响应
  static const int _silentStopTicks = 7; // 降低到7（1.4秒静音），更快自动停止
  static const double _minimumVoiceLevel = -60; // 降低到-60（更敏感）
  static const double _speechOverNoise = 6; // 降低到6dB（更易触发）
  static const Duration _minimumRecordingDuration =
      Duration(milliseconds: 300);
  static const String _callSystemPrompt =
      '当前正在进行实时语音通话。只给出简短、自然、适合直接朗读的口语回复；不要使用 Markdown、标题、列表、协议标签或冗长说明。';
  static const String _videoCallSystemPrompt =
      '当前正在进行实时视频通话，对方可以看到你。如果对话涉及视觉内容、需要展示画面或你认为图片会有帮助，请调用 generate_image 工具生成图片。只给出简短、自然、适合直接朗读的口语回复；不要使用 Markdown、标题、列表、协议标签或冗长说明。';
  int _silentTicks = 0;
  int _voiceTicks = 0;
  DateTime? _recordingStartedAt;
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
    if (_showTextComposer) {
      _textFocusNode.unfocus();
      setState(() => _showTextComposer = false);
      return;
    }
    setState(() => _showTextComposer = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  AICancellationToken _beginTurn() {
    _turnToken?.cancel();
    final token = AICancellationToken();
    _turnToken = token;
    return token;
  }

  Future<void> _runTextTurn(String text) async {
    _appendMessage(text, isUser: true);
    _transcript.add('用户：$text');
    if (mounted)
      setState(() {
        _processing = true;
        _flowState = CallFlowState.generatingReply;
        _caption = '正在等待回复…';
      });
    try {
      final token = _beginTurn();
      // 视频通话：发送前截取当前摄像头画面
      final frame = _videoEnabled ? await _captureVideoFrame() : null;
      if (_ending) return;
      final systemPrompt =
          _videoEnabled ? _videoCallSystemPrompt : _callSystemPrompt;
      final reply = await AIManager()
          .sendMessage(
            botId: widget.bot['id'].toString(),
            text: text,
            imagePath: frame,
            allowTools: _videoEnabled,
            allowStickers: false,
            forceSingleReply: true,
            cancellationToken: token,
            extraSystemPrompt: systemPrompt,
            includeChatHistory: true,
          )
          .timeout(const Duration(seconds: 60));
      if (_ending) return;
      if (reply['success'] != true) {
        final reason = _replyFailureReason(reply);
        AppLogService.instance.add('VOICE_CALL', '文字 AI 请求失败：$reason');
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = reason;
          });
        }
        return;
      }
      final answer =
          reply['reply']?.toString() ?? reply['content']?.toString() ?? '';
      if (answer.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = '机器人没有返回回复';
          });
        }
        return;
      }
      _applyGeneratedImage(reply);
      _appendMessage(answer, isUser: false);
      _transcript.add('机器人：$answer');
      if (mounted) setState(() => _caption = answer);
      final ttsId = _ttsProviderId;
      if (_hasTts && ttsId.isNotEmpty) {
        await _synthesizeAndPlay(answer, ttsId);
      } else if (!_hasTts) {
        AppLogService.instance.add('VOICE_CALL', 'TTS 不可用，仅显示文字');
      }
    } on AICancelledException {
      return;
    } catch (error) {
      if (_ending) return;
      AppLogService.instance.add('VOICE_CALL', '文字轮次失败：$error');
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.failed;
          _caption = '文字回复失败：$error';
        });
      }
    } finally {
      if (mounted && !_ending) {
        setState(() {
          _processing = false;
          if (_flowState != CallFlowState.playing &&
              _flowState != CallFlowState.failed) {
            _flowState = CallFlowState.idle;
          }
        });
        // 文字回复完成后也恢复监听
        if (!_muted && _flowState != CallFlowState.playing) {
          unawaited(_startListening());
        }
      }
    }
  }

  String _replyFailureReason(Map<String, dynamic> reply) {
    final error = reply['error']?.toString().trim() ?? '';
    final code = reply['error_code']?.toString().trim() ?? '';
    final log = reply['error_log']?.toString().trim() ?? '';
    if (error.isNotEmpty) return error;
    if (code.isNotEmpty) return '请求失败：$code';
    if (log.isNotEmpty) {
      final firstLine = log.split(RegExp(r'\r?\n')).first.trim();
      return firstLine.length > 120
          ? '请求失败：${firstLine.substring(0, 120)}…'
          : '请求失败：$firstLine';
    }
    return '机器人回复失败';
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
    final floor = _noiseFloor ?? level;
    if (!_speechDetected && !_vadActive) {
      _noiseFloor = floor * .86 + level * .14;
    }
    final gate = (_noiseFloor ?? floor) + _speechOverNoise;
    final isVoice = level >= _minimumVoiceLevel && level >= gate;

    // 调试日志：监控振幅回调和语音检测
    if (_recording && !_processing && !_finishingRecording) {
      AppLogService.instance.add('VOICE_CALL_AMP',
          'level=$level gate=$gate isVoice=$isVoice speechDetected=$_speechDetected voiceTicks=$_voiceTicks silentTicks=$_silentTicks');
    }

    if (_vadActive) {
      if (isVoice) {
        _vadActive = false;
        _playSub?.cancel();
        _playSub = null;
        if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
        unawaited(_player.stop());
        if (mounted) {
          setState(() {
            _botSpeaking = false;
            _flowState = CallFlowState.idle;
            _caption = '已检测到你的声音';
          });
        }
      }
      return;
    }
    if (_recording && !_processing && !_finishingRecording) {
      if (isVoice) {
        _voiceTicks++;
        _silentTicks = 0;
        if (!_speechDetected && _voiceTicks >= _speechStartTicks) {
          if (mounted) {
            setState(() {
              _speechDetected = true;
              _flowState = CallFlowState.speechDetected;
              _caption = '已识别到你的声音';
            });
          }
          AppLogService.instance.add('VOICE_CALL', '已检测到用户语音');
        }
      } else {
        _voiceTicks = 0;
        _silentTicks++;
        // 兜底逻辑：即使未检测到明显语音，只要已录制足够时长且持续静音，也自动结束
        final recordingDuration = _recordingStartedAt == null
            ? Duration.zero
            : DateTime.now().difference(_recordingStartedAt!);
        if (recordingDuration.inSeconds >= 3 &&
            _silentTicks >= _silentStopTicks) {
          AppLogService.instance.add('VOICE_CALL',
              '录制${recordingDuration.inSeconds}秒后持续静音，自动结束录音（兜底）');
          unawaited(_finishListening());
        } else if (_speechDetected && _silentTicks >= _silentStopTicks) {
          AppLogService.instance
              .add('VOICE_CALL', '连续静音$_silentTicks个tick，自动结束录音');
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
    _autoStopTimer = Timer(const Duration(seconds: 10), () {
      if (_recording && !_processing && !_muted && !_vadActive) {
        AppLogService.instance
            .add('VOICE_CALL', '兜底定时器触发，10秒超时自动结束录音');
        unawaited(_finishListening());
      }
    });
  }

  Future<void> _startListening() async {
    if (_muted || _processing || _recording || _ending) return;
    AppLogService.instance.add('VOICE_CALL', '请求麦克风权限');
    if (mounted) {
      setState(() {
        _flowState = CallFlowState.requestingPermission;
        _caption = '正在请求麦克风权限…';
      });
    }
    if (!await AppPermissions.microphone(context)) {
      AppLogService.instance.add('VOICE_CALL', '麦克风权限未授予');
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.failed;
          _caption = '未获得麦克风权限';
        });
      }
      return;
    }
    try {
      // 停止任何正在播放的机器人语音后再聆听。
      if (_player.state == PlayerState.playing) await _player.stop();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.wav';
      // WAV（16kHz 单声道 PCM）是 Whisper、MiMo 和聊天模型 input_audio
      // 都接受的格式；m4a 在 input_audio 中通常不被支持。
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
        path: path,
      );
      _startAmpMonitor();
      _silentTicks = 0;
      _voiceTicks = 0;
      _speechDetected = false;
      _noiseFloor = null;
      _recordingStartedAt = DateTime.now();
      _ensureAutoStopTimer();
      AppLogService.instance.add('VOICE_CALL', '录音已启动：$path');
      if (mounted) {
        setState(() {
          _recording = true;
          _flowState = CallFlowState.recording;
          _caption = '正在聆听，请说话';
        });
      }
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '录音启动失败：$error');
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.failed;
          _caption = '无法开始录音：$error';
        });
      }
    }
  }

  Future<void> _finishListening() async {
    if (_finishingRecording || _ending) return;
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
        _flowState = CallFlowState.transcribing;
        _caption = '正在提交语音识别…';
      });
    }
    try {
      final path = await _recorder.stop();
      final recordingDuration = _recordingStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_recordingStartedAt!);
      _recordingStartedAt = null;
      AppLogService.instance.add(
        'VOICE_CALL',
        path == null ? '录音未生成文件' : '录音已停止：$path，准备请求 STT',
      );
      final speechDetected = _speechDetected;
      _vadActive = false;
      _speechDetected = false;
      if (path == null || path.isEmpty) {
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = '录音文件为空，无法请求语音识别';
          });
        }
        return;
      }
      final recordingFile = File(path);
      if (!await recordingFile.exists()) {
        AppLogService.instance.add('VOICE_CALL', '❌ 录音文件不存在：$path');
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = '录音文件生成失败，请检查麦克风权限';
          });
        }
        return;
      }
      final bytes = await recordingFile.length();
      AppLogService.instance.add(
        'VOICE_CALL',
        '录音校验：${recordingDuration.inMilliseconds}ms，$bytes bytes，检测到语音=$speechDetected',
      );
      if (recordingDuration < _minimumRecordingDuration) {
        AppLogService.instance.add(
          'VOICE_CALL',
          '❌ 录音时长不足：${recordingDuration.inMilliseconds}ms < ${_minimumRecordingDuration.inMilliseconds}ms',
        );
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption =
                '录音时间过短（${recordingDuration.inMilliseconds}ms），请至少说一句完整的话';
          });
        }
        return;
      }
      if (bytes < 512) {
        AppLogService.instance.add('VOICE_CALL', '❌ 录音文件过小：$bytes bytes');
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = '录音文件过小（$bytes bytes），可能麦克风未授权或被占用';
          });
        }
        return;
      }
      AppLogService.instance.add('VOICE_CALL', '✅ 录音校验通过，准备 STT');
      if (!speechDetected) {
        AppLogService.instance.add('VOICE_CALL', '⚠️ 未检测到语音分贝，但文件存在，继续尝试 STT');
      }
      _recordingPath = path;
      await _runVoiceTurn();
    } catch (error) {
      AppLogService.instance.add('VOICE_CALL', '录音停止或提交失败：$error');
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.failed;
          _caption = '录音处理失败：$error';
        });
      }
    } finally {
      _finishingRecording = false;
    }
  }

  Future<void> _runVoiceTurn() async {
    if (_processing || _recordingPath == null || _ending) return;
    if (!_hasStt) {
      AppLogService.instance.add('VOICE_CALL', 'STT 不可用，切换到手动输入');
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.failed;
          _caption = '未配置语音识别，请使用文字输入';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _processing = true;
        _flowState = CallFlowState.transcribing;
        _caption = '正在识别语音…';
      });
    }
    AppLogService.instance.add('VOICE_CALL', 'STT 开始：${_recordingPath!}');
    try {
      final token = _beginTurn();
      AppLogService.instance
          .add('VOICE_CALL', '调用 AIManager.transcribeAudio，超时45秒');
      final text = await AIManager()
          .transcribeAudio(
            botId: widget.bot['id'].toString(),
            audioPath: _recordingPath!,
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 45));
      if (_ending) return;
      AppLogService.instance.add(
          'VOICE_CALL',
          'STT 返回：${text == null ? 'null' : text.isEmpty ? '空字符串' : '长度 ${text.trim().length}'}');
      if (text == null || text.trim().isEmpty) {
        AppLogService.instance.add('VOICE_CALL',
            '❌ STT 返回空文本，可能原因：\n  1. 录音文件损坏\n  2. STT 服务配置错误\n  3. 音频格式不支持\n  4. 网络请求失败');
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption =
                '没有识别到有效语音。请检查：\n1. STT 模型是否配置\n2. 麦克风是否正常工作\n3. 录音文件：${_recordingPath!}';
          });
        }
        return;
      }
      AppLogService.instance
          .add('VOICE_CALL', 'STT 成功，文本长度 ${text.trim().length}');
      _transcript.add('用户：${text.trim()}');
      _appendMessage(text, isUser: true);

      // 视频通话：用户说完话后自动截取一帧摄像头画面随本轮发送
      final frame = _videoEnabled ? await _captureVideoFrame() : null;
      if (_ending) return;

      if (mounted) setState(() => _caption = text);
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.generatingReply;
          _caption = '正在生成回复…';
        });
      }
      AppLogService.instance.add('VOICE_CALL', 'AI 请求开始');

      String streamingReply = '';
      final systemPrompt =
          _videoEnabled ? _videoCallSystemPrompt : _callSystemPrompt;
      final reply = await AIManager()
          .sendMessage(
            botId: widget.bot['id'].toString(),
            text: text,
            imagePath: frame,
            allowTools: _videoEnabled,
            allowStickers: false,
            forceSingleReply: true,
            cancellationToken: token,
            extraSystemPrompt: systemPrompt,
            includeChatHistory: true,
            onDelta: (delta) {
              if (mounted) {
                setState(() {
                  streamingReply += delta;
                  _caption = streamingReply;
                });
              }
            },
          )
          .timeout(const Duration(seconds: 60));
      if (_ending) return;
      if (reply['success'] != true) {
        final reason = _replyFailureReason(reply);
        AppLogService.instance.add('VOICE_CALL', 'AI 请求失败：$reason');
        // 检测是否因流式失败，如果是则降级到非流式
        if (reason.contains('stream') ||
            reason.contains('流式') ||
            reason.contains('SSE')) {
          AppLogService.instance.add('VOICE_CALL', '流式输出失败，本轮通话降级到非流式');
          _streamFailedThisCall = true;
        }
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = reason;
          });
        }
        return;
      }
      final answer =
          reply['reply']?.toString() ?? reply['content']?.toString() ?? '';
      if (answer.trim().isEmpty) {
        AppLogService.instance.add('VOICE_CALL', 'AI 返回空回复');
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.failed;
            _caption = '机器人没有返回回复';
          });
        }
        return;
      }
      AppLogService.instance.add('VOICE_CALL', 'AI 回复成功，文本长度 ${answer.length}');
      _transcript.add('机器人：$answer');

      _applyGeneratedImage(reply);
      // 先不显示文字，等 TTS 生成后再同步显示和播放
      final ttsId = _ttsProviderId;
      if (ttsId.isEmpty || !_hasTts) {
        AppLogService.instance.add('VOICE_CALL', 'TTS 不可用，保留文字回复');
        _appendMessage(answer, isUser: false);
        if (mounted) setState(() => _caption = answer);
        return;
      }
      AppLogService.instance.add('VOICE_CALL', 'TTS 生成开始：$ttsId');
      // TTS 生成成功后在 _synthesizeAndPlay 里显示文字
      await _synthesizeAndPlay(answer, ttsId);
    } on AICancelledException {
      return;
    } catch (error) {
      if (_ending) return;
      AppLogService.instance.add('VOICE_CALL', '语音轮次失败：$error');
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.failed;
          _caption = '语音通话失败：$error';
        });
      }
    } finally {
      if (mounted && !_ending) {
        setState(() => _processing = false);
        // 任何错误都重新开始监听，不要卡住
        if (!_muted) {
          unawaited(_startListening());
        }
      }
    }
  }

  Future<void> _synthesizeAndPlay(String answer, String ttsId) async {
    // 立即显示回复文字（音画同步）
    _appendMessage(answer, isUser: false);
    if (mounted) {
      setState(() {
        _flowState = CallFlowState.synthesizing;
        _caption = answer; // 显示文字内容，而不是"正在生成语音"
      });
    }
    try {
      if (_ending) return;
      final audioPath = await AIManager().generateTTS(
        answer,
        ttsId,
        cancellationToken: _turnToken,
      );
      if (_ending) return;
      if (audioPath == null || audioPath.isEmpty) {
        AppLogService.instance.add('VOICE_CALL', 'TTS 未生成音频，保留文字回复');
        if (mounted) {
          setState(() {
            _flowState = CallFlowState.idle;
            _caption = '语音生成失败，已保留文字回复';
          });
        }
        return;
      }
      AppLogService.instance.add('VOICE_CALL', 'TTS 生成成功，开始播放');
      if (mounted) setState(() => _caption = '正在说话…');
      await _playBotReply(audioPath);
    } on AICancelledException {
      return;
    } catch (error) {
      if (_ending) return;
      AppLogService.instance.add('VOICE_CALL', 'TTS 或播放失败，保留文字回复：$error');
      if (mounted) {
        setState(() {
          _botSpeaking = false;
          _flowState = CallFlowState.idle;
          _caption = '语音播放失败，已保留文字回复';
        });
      }
    }
  }

  /// 播放机器人回复；使用扬声器模式，不再开录音监听插话。
  /// 用户想插话时可以点"暂停"按钮手动打断。
  Future<void> _playBotReply(String audioPath) async {
    AppLogService.instance.add('VOICE_CALL', '开始播放 TTS 音频（扬声器模式）');
    StreamSubscription<PlayerState>? stateSub;
    try {
      _playDone = Completer<void>();
      if (mounted) {
        setState(() {
          _flowState = CallFlowState.playing;
          _botSpeaking = true;
        });
      }
      await _playSub?.cancel();
      _playSub = _player.onPlayerComplete.listen((event) {
        if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
      });
      // Some player implementations do not emit onPlayerComplete reliably.
      stateSub = _player.onPlayerStateChanged.listen((state) {
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
    } finally {
      _vadActive = false;
      if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
      await _playSub?.cancel();
      _playSub = null;
      await stateSub?.cancel();
      if (mounted) {
        setState(() {
          _botSpeaking = false;
          if (!_processing) _flowState = CallFlowState.idle;
        });
      }
      AppLogService.instance.add('VOICE_CALL', 'TTS 播放结束');
      // 播放完成后继续监听
      if (mounted && !_ending && !_muted && !_processing) {
        unawaited(_startListening());
      }
    }
  }

  Future<void> _pauseBotReply() async {
    if (!_botSpeaking) return;
    _vadActive = false;
    if (!(_playDone?.isCompleted ?? true)) _playDone?.complete();
    await _player.stop();
    if (mounted) {
      setState(() {
        _botSpeaking = false;
        _flowState = CallFlowState.idle;
      });
    }
    AppLogService.instance.add('VOICE_CALL', '用户手动暂停机器人语音');
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    _turnToken?.cancel();
    _turnToken = null;
    _autoStopTimer?.cancel();
    _recordingStartedAt = null;
    _vadActive = false;
    _stopAmpMonitor();
    final wasRecording = _recording;
    _recording = false;
    _botSpeaking = false;

    final duration = DateTime.now().difference(_startedAt);
    final botId = widget.bot['id']?.toString() ?? '';
    final transcript = List<String>.from(_transcript);
    if (mounted) Navigator.pop(context);
    unawaited(_stopCallMedia(wasRecording));
    if (duration.inMilliseconds < 1000 || botId.isEmpty) return;
    unawaited(_persistCallSummary(
      botId: botId,
      duration: duration,
      transcript: transcript,
    ));
  }

  Future<void> _stopCallMedia(bool wasRecording) async {
    try {
      if (wasRecording) await _recorder.stop();
      await _player.stop();
    } catch (_) {}
    // 通话结束后删除临时截取的摄像头画面。
    final frames = List<String>.from(_capturedFrames);
    _capturedFrames.clear();
    for (final path in frames) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _persistCallSummary({
    required String botId,
    required Duration duration,
    required List<String> transcript,
  }) async {
    final durationText = _formatDuration(duration);
    var summary = '本次通话未获取到有用信息。';
    var failed = false;
    if (transcript.isNotEmpty) {
      try {
        final result = await AIManager().sendMessage(
          task: AIRequestTask.callSummary,
          botId: botId,
          text:
              '这是内部通话总结任务，不要和用户聊天。通话时长：$durationText。根据以下真实通话记录，以机器人第一人称写一份详细、自然的摘要，保留双方重点、结论、待办和未解决问题；不得编造。只输出摘要正文。\n\n${transcript.join('\n')}',
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
    final sessionId = 'call_$now';
    // 通话记录保存到独立的 call_messages 表，不插入到聊天历史
    final messages = <Map<String, dynamic>>[];
    for (var index = 0; index < transcript.length; index++) {
      final line = transcript[index];
      final isUser = line.startsWith('用户：');
      final content = line.replaceFirst(RegExp(r'^(用户|机器人)：'), '').trim();
      if (content.isEmpty) continue;
      messages.add({
        'id': '${sessionId}_$index',
        'session_id': sessionId,
        'role': isUser ? 'user' : 'assistant',
        'content': content,
        'timestamp': now + index,
      });
    }
    await DBManager().insertCallSession(
      session: {
        'id': sessionId,
        'bot_id': botId,
        'summary': summary,
        'duration': duration.inSeconds,
        'status': failed ? 'failed' : 'complete',
        'created_at': now,
      },
      messages: messages,
    );
    if (!failed && summary.isNotEmpty) {
      await DBManager().upsertMemoryItem(
        botId: botId,
        type: 'call_summary',
        title: '通话摘要',
        content: summary,
        category: 'event',
        importance: 4,
        timestamp: now,
      );
      // 插入通话摘要到聊天室
      await DBManager().insertMessage({
        'id': '${sessionId}_summary',
        'bot_id': botId,
        'role': 'assistant',
        'content': summary,
        'type': 'call_summary',
        'timestamp': now,
      });
    }
    AppLogService.instance
        .add('VOICE_CALL', '通话结束：$durationText，摘要${failed ? '失败' : '已保存'}');
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

    // 先用入口传入的判定渲染，避免异步读取前闪现"配置语音模型"
    _hasStt = widget.hasStt;
    _hasTts = widget.hasTts;
    // 再从 SharedPreferences 和 bot 记录中读取实际配置的 STT/TTS
    _loadSttTtsConfig();
  }

  Future<void> _loadSttTtsConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final botId = widget.bot['id']?.toString() ?? '';

    _sttProviderId = prefs.getString('stt_model_$botId')?.trim() ??
        widget.bot['stt_model']?.toString().trim() ??
        '';
    _ttsProviderId = prefs.getString('tts_model_$botId')?.trim() ??
        widget.bot['tts_model']?.toString().trim() ??
        '';

    if (!mounted) return;
    setState(() {
      _hasStt = _sttProviderId.isNotEmpty;
      _hasTts = _ttsProviderId.isNotEmpty;
    });

    AppLogService.instance.add(
      'VOICE_CALL',
      '通话初始化：STT=${_hasStt ? _sttProviderId : '不可用'}，TTS=${_hasTts ? _ttsProviderId : '不可用'}',
    );

    if (_hasStt && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startListening();
      });
    }
  }

  @override
  void dispose() {
    _turnToken?.cancel();
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

  Future<void> _toggleVideo() async {
    if (_videoEnabled) {
      setState(() {
        _videoEnabled = false;
        _generatedImagePath = null;
      });
      AppLogService.instance.add('VOICE_CALL', '视频通话已关闭');
    } else {
      if (!await AppPermissions.camera(context)) {
        AppLogService.instance.add('VOICE_CALL', '相机权限未授予');
        return;
      }
      setState(() {
        _videoEnabled = true;
        _generatedImagePath = null;
      });
      AppLogService.instance.add('VOICE_CALL', '视频通话已开启');
    }
  }

  /// 截取当前摄像头画面；摄像头未就绪时返回 null，本轮仅发送文字。
  Future<String?> _captureVideoFrame() async {
    final path = await _videoOverlayKey.currentState?.captureFrame();
    if (path != null) {
      _capturedFrames.add(path);
      AppLogService.instance.add('VOICE_CALL', '已截取视频帧');
    } else {
      AppLogService.instance.add('VOICE_CALL', '视频帧截取失败，本轮仅发送文字');
    }
    return path;
  }

  /// 机器人通过 generate_image 生成图片后更新视频主画面，保留到下一张出现。
  void _applyGeneratedImage(Map<String, dynamic> reply) {
    final path = reply['image_path']?.toString().trim() ?? '';
    if (path.isEmpty || !mounted) return;
    setState(() => _generatedImagePath = path);
    AppLogService.instance.add('VOICE_CALL', '机器人分享了画面');
  }

  Future<void> _toggleMute() async {
    TideHaptics.tap();
    if (_muted) {
      setState(() => _muted = false);
      await _startListening();
      return;
    }
    _vadActive = false;
    _autoStopTimer?.cancel();
    _stopAmpMonitor();
    _silentTicks = 0;
    if (_recording) await _recorder.stop();
    _recordingStartedAt = null;
    if (!mounted) return;
    setState(() {
      _muted = true;
      _recording = false;
      _flowState = CallFlowState.idle;
      _caption = '已静音';
    });
  }

  Future<void> _toggleSpeaker() async {
    TideHaptics.tap();
    final next = !_speakerMuted;
    setState(() => _speakerMuted = next);
    await _player.setVolume(next ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final name = widget.bot['name']?.toString().trim().isNotEmpty == true
        ? widget.bot['name'].toString()
        : 'TideBot';
    final avatar = widget.bot['avatar']?.toString() ?? '';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _videoEnabled
          ? KeyedSubtree(
              key: const ValueKey('video_call'),
              child: _buildVideoCall(theme, name, avatar),
            )
          : KeyedSubtree(
              key: const ValueKey('voice_call'),
              child: _buildVoiceCall(theme, name, avatar),
            ),
    );
  }

  // ===================== 语音通话布局 =====================

  Widget _buildVoiceCall(TideTheme theme, String name, String avatar) {
    final ready = _hasStt;
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
                                      color:
                                          theme.primary.withValues(alpha: .22),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              TideBotAvatar(
                                  name: name, path: avatar, size: 104),
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
                        if (_flowState == CallFlowState.failed)
                          OutlinedButton.icon(
                            onPressed: _retryVoiceFlow,
                            icon: Icon(Icons.refresh_rounded,
                                color: theme.primary),
                            label: Text(
                              '重试',
                              style: TextStyle(
                                color: theme.primary,
                                fontFamily: 'TideFont',
                              ),
                            ),
                          )
                        else
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
                                      onTap: _toggleMute)),
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
                                      onTap: _toggleSpeaker)),
                              Positioned(
                                left: 72,
                                top: 2,
                                child: IconButton(
                                  tooltip: '切换为视频通话',
                                  onPressed: _ending ? null : _toggleVideo,
                                  icon: Icon(
                                    Icons.videocam_rounded,
                                    color: theme.primary,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 72,
                                top: 2,
                                child: IconButton(
                                  tooltip: '文字回复',
                                  onPressed: _processing || _ending
                                      ? null
                                      : _openTextComposer,
                                  icon: Icon(
                                    _showTextComposer
                                        ? Icons.edit_off_rounded
                                        : Icons.edit_rounded,
                                    color: theme.primary,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== 视频通话布局 =====================

  Widget _buildVideoCall(TideTheme theme, String name, String avatar) {
    final image = _generatedImagePath;
    final subtitle = _videoSubtitle();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            // 机器人画面：未生成时保持纯黑，生成后一直保留到下一张出现。
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: image == null
                  ? const SizedBox.expand(key: ValueKey('video_stage_empty'))
                  : _botImageStage(image),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 200,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xB3000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 340,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xE6000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 14,
                    left: 18,
                    right: 140,
                    child: _videoHeader(theme, name, avatar),
                  ),
                  Positioned(
                    top: 12,
                    right: 16,
                    child: VideoCallOverlay(key: _videoOverlayKey),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (subtitle.isNotEmpty) ...[
                          _videoSubtitleCard(subtitle),
                          const SizedBox(height: 14),
                        ],
                        if (_showTextComposer) ...[
                          _videoGlass(
                            radius: 22,
                            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                            child: _textComposer(theme),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _videoActionRow(theme),
                        const SizedBox(height: 16),
                        _videoControlBar(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botImageStage(String path) {
    final file = File(path);
    Widget fallback(BuildContext _, Object __, StackTrace? ___) =>
        const SizedBox.shrink();
    return Stack(
      key: ValueKey(path),
      fit: StackFit.expand,
      children: [
        // 同一张图的模糊放大版作为氛围底，避免上下留出生硬黑边。
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: fallback,
          ),
        ),
        const ColoredBox(color: Color(0x99000000)),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 40,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: '对方分享的画面',
                  errorBuilder: fallback,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _videoHeader(TideTheme theme, String name, String avatar) {
    final failed = _flowState == CallFlowState.failed;
    return Row(
      children: [
        AnimatedBuilder(
          animation: _wave,
          builder: (context, child) {
            final active = _botSpeaking;
            final pulse = _wave.value;
            return Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? theme.primary.withValues(alpha: .55 + pulse * .4)
                      : Colors.white.withValues(alpha: .28),
                  width: 2,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color:
                              theme.primary.withValues(alpha: .18 + pulse * .3),
                          blurRadius: 14 + pulse * 10,
                        ),
                      ]
                    : null,
              ),
              child: child,
            );
          },
          child: TideBotAvatar(name: name, path: avatar, size: 46),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'TideFont',
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: failed
                          ? const Color(0xFFFF453A)
                          : const Color(0xFF30D158),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${_callStateLabel()} · ${_formatClock(_elapsed)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        fontSize: 12.5,
                        fontFamily: 'TideFont',
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _videoSubtitle() {
    final caption = _caption.trim();
    if (caption.isNotEmpty) return caption;
    if (_messages.isNotEmpty) return _messages.last.text;
    return _hasStt ? '正在自动监听，请直接说话' : '';
  }

  Widget _videoGlass({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    double radius = 24,
  }) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: shape,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .16),
                Colors.white.withValues(alpha: .06),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _videoSubtitleCard(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: _videoGlass(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.45,
              fontFamily: 'TideFont',
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoPill({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool highlighted = false,
  }) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled
            ? () {
                TideHaptics.tap();
                onTap();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : .45,
          child: highlighted
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: _pillContent(icon, label, Colors.black),
                )
              : _videoGlass(
                  radius: 22,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: _pillContent(icon, label, Colors.white),
                ),
        ),
      ),
    );
  }

  Widget _pillContent(IconData icon, String label, Color color) =>
      ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'TideFont',
              ),
            ),
          ],
        ),
      );

  Widget _videoActionRow(TideTheme theme) {
    final Widget primary;
    if (!_hasStt) {
      primary = _videoPill(
        icon: Icons.settings_rounded,
        label: '配置语音模型',
        onTap: widget.onOpenSettings,
      );
    } else if (_flowState == CallFlowState.failed) {
      primary = _videoPill(
        icon: Icons.refresh_rounded,
        label: '重试',
        onTap: _retryVoiceFlow,
        highlighted: true,
      );
    } else {
      final speaking = _botSpeaking;
      final listening = _recording;
      primary = _videoPill(
        icon: speaking ? Icons.pause_rounded : Icons.check_rounded,
        label: speaking ? '暂停' : '说完了',
        highlighted: speaking,
        onTap: !(speaking || listening) || _finishingRecording
            ? null
            : () {
                if (speaking) {
                  unawaited(_pauseBotReply());
                } else {
                  unawaited(_finishListening());
                }
              },
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        primary,
        const SizedBox(width: 10),
        _videoPill(
          icon: _showTextComposer ? Icons.edit_off_rounded : Icons.edit_rounded,
          label: '文字',
          onTap: _processing || _ending ? null : _openTextComposer,
        ),
      ],
    );
  }

  Widget _videoControlBar() {
    return _videoGlass(
      radius: 36,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _videoControl(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _muted ? '已静音' : '静音',
            active: _muted,
            onTap: _toggleMute,
          ),
          _videoControl(
            icon: Icons.cameraswitch_rounded,
            label: '翻转',
            onTap: () => _videoOverlayKey.currentState?.switchCamera(),
          ),
          _videoControl(
            icon: Icons.call_end_rounded,
            label: '挂断',
            danger: true,
            onTap: _endCall,
          ),
          _videoControl(
            icon: Icons.videocam_off_rounded,
            label: '关视频',
            onTap: _toggleVideo,
          ),
          _videoControl(
            icon: _speakerMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            label: _speakerMuted ? '声音关' : '声音开',
            active: _speakerMuted,
            onTap: _toggleSpeaker,
          ),
        ],
      ),
    );
  }

  Widget _videoControl({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
  }) {
    const red = Color(0xFFFF3B30);
    final size = danger ? 62.0 : 50.0;
    final background = danger
        ? red
        : active
            ? Colors.white
            : Colors.white.withValues(alpha: .14);
    final foreground = danger
        ? Colors.white
        : active
            ? Colors.black
            : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!danger) TideHaptics.tap();
          onTap();
        },
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: background,
                  boxShadow: danger
                      ? [
                          BoxShadow(
                            color: red.withValues(alpha: .45),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Icon(icon, color: foreground, size: danger ? 28 : 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  fontSize: 11,
                  fontFamily: 'TideFont',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== 共享组件 =====================

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

  Future<void> _retryVoiceFlow() async {
    if (_processing || _recording || _ending) return;
    _recordingPath = null;
    _recordingStartedAt = null;
    _speechDetected = false;
    _silentTicks = 0;
    _voiceTicks = 0;
    if (mounted) {
      setState(() {
        _flowState = CallFlowState.idle;
        _caption = '';
      });
    }
    await _startListening();
  }

  String _formatClock(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  String _callStateLabel() {
    if (!_hasStt) return '需要配置语音';
    if (_muted) return '已静音';
    return switch (_flowState) {
      CallFlowState.requestingPermission => '正在请求权限',
      CallFlowState.recording => '正在聆听',
      CallFlowState.speechDetected => '已检测到语音',
      CallFlowState.transcribing => '正在识别语音',
      CallFlowState.generatingReply => '正在生成回复',
      CallFlowState.synthesizing => '正在生成语音',
      CallFlowState.playing => '机器人正在说话',
      CallFlowState.failed => '需要重试',
      CallFlowState.idle => '通话中',
    };
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
