import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps square photos at 144 × 144 and bounds unusually long screenshots.
class ChatImage extends StatefulWidget {
  const ChatImage({super.key, required this.path});

  final String path;

  @override
  State<ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<ChatImage> {
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  double _ratio = 1;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener((info, synchronousCall) {
      final ratio = info.image.width / info.image.height;
      info.dispose();
      if (mounted && ratio != _ratio) {
        setState(() => _ratio = ratio);
      }
    }, onError: (Object error, StackTrace? stack) {});
  }

  ImageProvider get _provider => ResizeImage.resizeIfNeeded(
        720,
        null,
        FileImage(File(widget.path)),
      );

  void _resolve() {
    _stream?.removeListener(_listener);
    _stream = _provider.resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _ratio = 1;
      _resolve();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = _ratio >= 1 ? math.min(240.0, 144 * _ratio) : 144.0;
    final height = _ratio >= 1 ? 144.0 : math.min(260.0, 144 / _ratio);
    return SizedBox(
      width: width,
      height: height,
      child: Image(
        image: _provider,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
