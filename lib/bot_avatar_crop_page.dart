import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bot_avatar_storage.dart';
import 'theme.dart';
import 'ui_components.dart';

/// Returns a saved square avatar only after explicit confirmation.
Future<String?> selectBotAvatarCrop(BuildContext context, String path) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => BotAvatarCropPage(path: path),
      fullscreenDialog: true,
    ));

class BotAvatarCropPage extends StatefulWidget {
  const BotAvatarCropPage({super.key, required this.path});
  final String path;

  @override
  State<BotAvatarCropPage> createState() => _BotAvatarCropPageState();
}

class _BotAvatarCropPageState extends State<BotAvatarCropPage> {
  ui.Image? _image;
  String? _error;
  bool _saving = false;
  Size? _viewport;
  Rect _crop = Rect.zero;
  Offset _offset = Offset.zero;
  double _scale = 1;
  double _minimumScale = 1;
  double _startScale = 1;
  Offset _anchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(
        await File(widget.path).readAsBytes(),
      );
      try {
        final frame = await codec.getNextFrame();
        if (!mounted) {
          frame.image.dispose();
          return;
        }
        setState(() => _image = frame.image);
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '图片无法读取，请返回重新选择');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _layout(Size viewport, EdgeInsets padding) {
    if (_viewport == viewport) return;
    final image = _image!;
    final oldCrop = _crop;
    final oldScale = _scale;
    final sourceCenter = _viewport == null
        ? Offset(image.width / 2, image.height / 2)
        : (oldCrop.center - _offset) / oldScale;
    final zoom = _viewport == null ? 1.0 : oldScale / _minimumScale;
    final top = padding.top + 86;
    final bottom = viewport.height - padding.bottom - 128;
    final side = math.max(1.0, math.min(viewport.width - 40, bottom - top));
    _crop = Rect.fromCenter(
      center: Offset(viewport.width / 2, (top + bottom) / 2),
      width: side,
      height: side,
    );
    _minimumScale = side / math.min(image.width, image.height);
    _scale = _minimumScale * zoom;
    _offset = _bounded(_crop.center - sourceCenter * _scale);
    _viewport = viewport;
  }

  Offset _bounded(Offset offset) => Offset(
        offset.dx
            .clamp(math.min(_crop.right - _image!.width * _scale, _crop.left),
                _crop.left)
            .toDouble(),
        offset.dy
            .clamp(math.min(_crop.bottom - _image!.height * _scale, _crop.top),
                _crop.top)
            .toDouble(),
      );

  Future<void> _confirm() async {
    if (_image == null || _saving || _viewport == null) return;
    setState(() => _saving = true);
    try {
      final rect = Rect.fromLTWH(
        (_crop.left - _offset.dx) / _scale,
        (_crop.top - _offset.dy) / _scale,
        _crop.width / _scale,
        _crop.width / _scale,
      );
      final path = await saveSquareBotAvatar(widget.path, cropRect: rect);
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '头像保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: !_saving,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: LayoutBuilder(builder: (context, constraints) {
            if (_image != null) {
              _layout(constraints.biggest, MediaQuery.paddingOf(context));
            }
            return Stack(fit: StackFit.expand, children: [
              if (_image != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _saving
                      ? null
                      : (details) {
                          _startScale = _scale;
                          _anchor =
                              (details.localFocalPoint - _offset) / _scale;
                        },
                  onScaleUpdate: _saving
                      ? null
                      : (details) => setState(() {
                            _scale = (_startScale * details.scale)
                                .clamp(_minimumScale, _minimumScale * 8)
                                .toDouble();
                            _offset = _bounded(
                                details.localFocalPoint - _anchor * _scale);
                          }),
                  child: CustomPaint(
                      painter: _AvatarCropPainter(
                    image: _image!,
                    crop: _crop,
                    offset: _offset,
                    scale: _scale,
                  )),
                )
              else if (_error == null)
                Center(child: CircularProgressIndicator(color: theme.primary)),
              SafeArea(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      tooltip: '取消裁剪',
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    const Expanded(
                        child: Text('调整头像',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'TideFont',
                                fontSize: 19,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 48),
                  ]),
                  const Spacer(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  const Text('拖动调整位置，双指缩放\n仅保存 1:1 方框内的区域',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'TideFont',
                          height: 1.6,
                          fontSize: 13)),
                  const SizedBox(height: 16),
                  IgnorePointer(
                    ignoring: _image == null || _saving,
                    child: Opacity(
                        opacity: _image == null || _saving ? 0.45 : 1,
                        child: TideDialogs.glassButton(
                          _saving ? '正在保存…' : '使用此头像',
                          onTap: _confirm,
                        )),
                  ),
                ]),
              )),
            ]);
          }),
        ),
      ),
    );
  }
}

class _AvatarCropPainter extends CustomPainter {
  const _AvatarCropPainter(
      {required this.image,
      required this.crop,
      required this.offset,
      required this.scale});
  final ui.Image image;
  final Rect crop;
  final Offset offset;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        offset & Size(image.width * scale, image.height * scale),
        Paint()..filterQuality = FilterQuality.high);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(crop);
    canvas.drawPath(
        outside, Paint()..color = Colors.black.withValues(alpha: 0.58));
    canvas.drawRect(
        crop,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 0.5;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(_AvatarCropPainter old) =>
      old.image != image ||
      old.crop != crop ||
      old.offset != offset ||
      old.scale != scale;
}
