import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'app_permissions.dart';

import 'package:flutter/material.dart';
import 'theme.dart';
import 'ui_components.dart';
import 'ai.dart';

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
  bool _processing = false;
  String _caption = '';
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _recordingPath;
  bool _recording = false;

  Future<void> _toggleRecording() async {
    if (!await AppPermissions.microphone(context)) return;
    if (_recording) {
      final path = await _recorder.stop();
      if (mounted)
        setState(() {
          _recording = false;
          _recordingPath = path;
        });
      if (path != null) await _runVoiceTurn();
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path);
    if (mounted)
      setState(() {
        _recording = true;
        _caption = '正在聆听…再次点击结束录音';
      });
  }

  Future<void> _runVoiceTurn() async {
    if (_processing ||
        !widget.hasStt ||
        !widget.hasTts ||
        _recordingPath == null) return;
    setState(() {
      _processing = true;
      _caption = '正在等待录音输入…';
    });
    // 录音能力由现有 OpsManager/录音组件提供；未获得录音文件时保持明确状态，不再显示“未集成”。
    final path = _recordingPath;
    if (path == null) {
      if (mounted)
        setState(() {
          _processing = false;
          _caption = '请先开始并结束一次录音';
        });
      return;
    }
    final text = await AIManager()
        .transcribeAudio(botId: widget.bot['id'].toString(), audioPath: path);
    if (text == null || text.trim().isEmpty) {
      if (mounted)
        setState(() {
          _processing = false;
          _caption = '没有识别到语音';
        });
      return;
    }
    if (mounted) setState(() => _caption = text);
    final reply = await AIManager()
        .sendMessage(botId: widget.bot['id'].toString(), text: text);
    final answer =
        reply['reply']?.toString() ?? reply['content']?.toString() ?? '';
    if (answer.isNotEmpty) {
      if (mounted) setState(() => _caption = answer);
    }
    if (mounted)
      setState(() {
        _processing = false;
      });
  }

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final ready = widget.hasStt && widget.hasTts;
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
                          ? (_caption.isEmpty ? '长按麦克风录音，松开后识别并回复' : _caption)
                          : '缺少：${widget.hasStt ? '' : 'STT 转写模型'}${!widget.hasStt && !widget.hasTts ? '、' : ''}${widget.hasTts ? '' : 'TTS 语音模型'}',
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
                          onTap: () {
                            TideHaptics.tap();
                            setState(() => _muted = !_muted);
                          },
                          onLongPress: _toggleRecording,
                        ),
                        const SizedBox(width: 34),
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
