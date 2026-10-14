import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log_service.dart';

/// 视频通话中右上角的用户摄像头小窗。
///
/// 父组件通过 [GlobalKey<VideoCallOverlayState>] 调用 [VideoCallOverlayState.captureFrame]
/// 截取当前画面，或调用 [VideoCallOverlayState.switchCamera] 切换前后摄像头。
class VideoCallOverlay extends StatefulWidget {
  final double width;
  final double height;

  const VideoCallOverlay({super.key, this.width = 108, this.height = 152});

  @override
  State<VideoCallOverlay> createState() => VideoCallOverlayState();
}

class VideoCallOverlayState extends State<VideoCallOverlay>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _busy = false;
  String? _error;

  bool get canSwitchCamera => _cameras.length > 1 && !_busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initCameras());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // 后台时释放摄像头，避免持续占用。
      if (controller != null) {
        _controller = null;
        unawaited(controller.dispose());
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        !_busy &&
        _cameras.isNotEmpty) {
      unawaited(_startCamera(_cameraIndex));
    }
  }

  Future<void> _initCameras() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = '没有可用摄像头';
          });
        }
        return;
      }
      final front = _cameras.indexWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front);
      await _startCamera(front == -1 ? 0 : front);
    } catch (error) {
      AppLogService.instance.add('VIDEO_CALL', '摄像头初始化失败：$error');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '摄像头不可用';
        });
      }
    }
  }

  Future<void> _startCamera(int index) async {
    if (index < 0 || index >= _cameras.length) return;
    _busy = true;
    final previous = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await previous?.dispose();
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _busy = false;
        _error = null;
      });
    } catch (error) {
      await controller.dispose();
      AppLogService.instance.add('VIDEO_CALL', '摄像头启动失败：$error');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '摄像头启动失败';
        });
      }
    }
  }

  /// 切换前后摄像头。
  Future<void> switchCamera() async {
    if (!canSwitchCamera) return;
    await _startCamera((_cameraIndex + 1) % _cameras.length);
  }

  /// 截取当前摄像头画面并保存为 JPEG，失败时返回 null。
  Future<String?> captureFrame() async {
    final controller = _controller;
    if (_busy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return null;
    }
    try {
      final shot = await controller.takePicture();
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/video_call_frames');
      if (!await folder.exists()) await folder.create(recursive: true);
      final target =
          '${folder.path}/frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(shot.path).copy(target);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return target;
    } catch (error) {
      AppLogService.instance.add('VIDEO_CALL', '截取摄像头画面失败：$error');
      return null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    super.dispose();
  }

  Widget _preview(CameraController controller) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    // previewSize 为横向尺寸，竖屏小窗交换宽高后按 cover 裁切。
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.height,
        height: size.width,
        child: CameraPreview(controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Semantics(
      label: '我的摄像头画面',
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF111114),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .55),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: ready
                  ? KeyedSubtree(
                      key: ValueKey(_cameraIndex),
                      child: _preview(controller),
                    )
                  : Center(
                      key: const ValueKey('placeholder'),
                      child: _error == null
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam_off_rounded,
                                    color: Colors.white54, size: 22),
                                const SizedBox(height: 6),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontFamily: 'TideFont',
                                  ),
                                ),
                              ],
                            ),
                    ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '我',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'TideFont',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
