import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'theme.dart';
import 'video_poster.dart';

String videoTime(Duration value) {
  final seconds = value.inSeconds;
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

class ChatVideoCard extends StatefulWidget {
  const ChatVideoCard({super.key, required this.path});
  final String path;
  @override
  State<ChatVideoCard> createState() => _ChatVideoCardState();
}

class _ChatVideoCardState extends State<ChatVideoCard> {
  late Future<VideoPoster> _poster;
  @override
  void initState() {
    super.initState();
    _poster = VideoPosterService.load(widget.path);
  }

  @override
  void didUpdateWidget(covariant ChatVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path)
      _poster = VideoPosterService.load(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoPoster>(
      future: _poster,
      builder: (context, snapshot) {
        final poster = snapshot.data;
        final ratio = poster?.aspectRatio ?? 4 / 3;
        final width = math.min(
            math.min(260.0, MediaQuery.sizeOf(context).width * .68),
            300 * ratio);
        return Semantics(
          button: true,
          label: '播放视频',
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ChatVideoPlayerPage(path: widget.path),
            )),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              width: width,
              height: width / ratio,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF191C20),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: .15)),
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (poster != null)
                  Image.file(File(poster.path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                const DecoratedBox(
                    decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x66000000)]),
                )),
                Center(
                    child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: .3),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .65))),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 34),
                )),
                const Positioned(
                    left: 12,
                    bottom: 10,
                    child: Row(children: [
                      Icon(Icons.videocam_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 5),
                      Text('视频',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ])),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class ChatVideoPlayerPage extends StatefulWidget {
  const ChatVideoPlayerPage({super.key, required this.path});
  final String path;
  @override
  State<ChatVideoPlayerPage> createState() => _ChatVideoPlayerPageState();
}

class _ChatVideoPlayerPageState extends State<ChatVideoPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Timer? _hideTimer;
  bool _controls = true;
  bool _landscape = false;
  bool _muted = false;
  bool _seeking = false;
  double _seek = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final previous = _controller;
    _controller = null;
    if (previous != null) await previous.dispose();
    if (!mounted) return;
    setState(() => _error = null);
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    try {
      if (!await File(widget.path).exists()) throw StateError('视频文件不存在或已被清理');
      await controller.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || _controller != controller) return;
      await controller.setVolume(_muted ? 0 : 1);
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await controller.play();
      }
      if (mounted) setState(() {});
      _scheduleHide();
    } catch (_) {
      if (mounted && _controller == controller)
        setState(() => _error = '无法播放此视频，请检查文件是否完整或格式是否受支持');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_controller?.pause());
      _hideTimer?.cancel();
      if (mounted) setState(() => _controls = true);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_seeking && _controller?.value.isPlaying == true)
        setState(() => _controls = false);
    });
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration)
        await controller.seekTo(Duration.zero);
      await controller.play();
    }
    if (mounted) setState(() => _controls = true);
    _scheduleHide();
  }

  Future<void> _toggleLandscape() async {
    setState(() => _landscape = !_landscape);
    await SystemChrome.setPreferredOrientations(_landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
    _scheduleHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    unawaited(_controller?.dispose());
    unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
            child: _error != null
                ? _errorView()
                : controller == null
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                    : ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          if (value.hasError) return _errorView();
                          final showControls = _controls || !value.isPlaying;
                          final total =
                              value.duration.inMilliseconds.toDouble();
                          final position = _seeking
                              ? _seek
                              : value.position.inMilliseconds
                                  .toDouble()
                                  .clamp(0.0, total);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() => _controls = !_controls);
                              _scheduleHide();
                            },
                            child: Stack(fit: StackFit.expand, children: [
                              if (value.isInitialized)
                                Center(
                                    child: AspectRatio(
                                        aspectRatio: value.aspectRatio,
                                        child: VideoPlayer(controller))),
                              if (!value.isInitialized || value.isBuffering)
                                const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.white)),
                              if (showControls) ...[
                                Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            8, 8, 18, 28),
                                        decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                              Color(0x99000000),
                                              Colors.transparent
                                            ])),
                                        child: Row(children: [
                                          IconButton(
                                              tooltip: '返回',
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              icon: const Icon(
                                                  Icons
                                                      .arrow_back_ios_new_rounded,
                                                  color: Colors.white)),
                                          const SizedBox(width: 6),
                                          const Text('视频',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600)),
                                        ]))),
                                if (value.isInitialized && !value.isBuffering)
                                  Center(
                                      child: IconButton.filled(
                                          style: IconButton.styleFrom(
                                              backgroundColor: Colors.black45,
                                              fixedSize: const Size(72, 72)),
                                          tooltip:
                                              value.isPlaying ? '暂停' : '播放',
                                          onPressed: _togglePlay,
                                          icon: Icon(
                                              value.isPlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 44))),
                                Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            18, 30, 18, 16),
                                        decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                              Colors.transparent,
                                              Color(0xBB000000)
                                            ])),
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SliderTheme(
                                                  data: SliderTheme.of(context)
                                                      .copyWith(
                                                          activeTrackColor:
                                                              TideTheme.of(
                                                                      context)
                                                                  .primary,
                                                          thumbColor:
                                                              Colors.white,
                                                          inactiveTrackColor:
                                                              Colors.white24,
                                                          trackHeight: 3),
                                                  child: Slider(
                                                      value: total > 0
                                                          ? position
                                                          : 0,
                                                      max:
                                                          total > 0 ? total : 1,
                                                      onChangeStart: total > 0
                                                          ? (v) {
                                                              _hideTimer
                                                                  ?.cancel();
                                                              setState(() {
                                                                _seeking = true;
                                                                _seek = v;
                                                              });
                                                            }
                                                          : null,
                                                      onChanged: total > 0
                                                          ? (v) => setState(
                                                              () => _seek = v)
                                                          : null,
                                                      onChangeEnd: total > 0
                                                          ? (v) async {
                                                              await controller
                                                                  .seekTo(Duration(
                                                                      milliseconds:
                                                                          v.round()));
                                                              if (mounted)
                                                                setState(() =>
                                                                    _seeking =
                                                                        false);
                                                              _scheduleHide();
                                                            }
                                                          : null)),
                                              Row(children: [
                                                Text(
                                                    '${videoTime(Duration(milliseconds: position.round()))} / ${videoTime(value.duration)}',
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12)),
                                                const Spacer(),
                                                IconButton(
                                                    tooltip:
                                                        _muted ? '开启声音' : '静音',
                                                    onPressed: () async {
                                                      setState(() =>
                                                          _muted = !_muted);
                                                      await controller
                                                          .setVolume(
                                                              _muted ? 0 : 1);
                                                      _scheduleHide();
                                                    },
                                                    icon: Icon(
                                                        _muted
                                                            ? Icons
                                                                .volume_off_rounded
                                                            : Icons
                                                                .volume_up_rounded,
                                                        color: Colors.white)),
                                                IconButton(
                                                    tooltip: _landscape
                                                        ? '竖屏'
                                                        : '横屏',
                                                    onPressed: _toggleLandscape,
                                                    icon: Icon(
                                                        _landscape
                                                            ? Icons
                                                                .fullscreen_exit_rounded
                                                            : Icons
                                                                .fullscreen_rounded,
                                                        color: Colors.white)),
                                              ]),
                                            ]))),
                              ],
                            ]),
                          );
                        },
                      )),
      ),
    );
  }

  Widget _errorView() => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.videocam_off_rounded,
                size: 44, color: Colors.white54),
            const SizedBox(height: 18),
            Text(_error ?? '视频播放失败',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextButton(
                onPressed: _initialize,
                child:
                    const Text('重新加载', style: TextStyle(color: Colors.white))),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('返回', style: TextStyle(color: Colors.white70))),
          ])));
}
