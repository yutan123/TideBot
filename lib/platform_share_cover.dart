import 'dart:io';
import 'package:flutter/material.dart';
import 'link_preview_models.dart';
import 'platform_video_poster.dart';

class PlatformShareCover extends StatelessWidget {
  const PlatformShareCover(
      {super.key, required this.data, required this.placeholder});
  final LinkPreviewData data;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => data.type == LinkType.douyin
        ? _PosterFallback(
            key: ValueKey('${data.url}:${data.videoUrl}'),
            data: data,
            placeholder: placeholder)
        : placeholder;
    if (data.imageUrl?.isNotEmpty != true) return fallback();
    return Image.network(data.imageUrl!,
        headers: data.imageHeaders,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback());
  }
}

class _PosterFallback extends StatefulWidget {
  const _PosterFallback(
      {super.key, required this.data, required this.placeholder});
  final LinkPreviewData data;
  final Widget placeholder;
  @override
  State<_PosterFallback> createState() => _PosterFallbackState();
}

class _PosterFallbackState extends State<_PosterFallback> {
  late final Future<String?> _poster = PlatformVideoPoster.load(widget.data);
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _poster,
        builder: (context, snapshot) => snapshot.data == null
            ? widget.placeholder
            : Image.file(File(snapshot.data!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => widget.placeholder),
      );
}
