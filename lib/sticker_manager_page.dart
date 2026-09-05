import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

class StickerManagerPage extends StatefulWidget {
  const StickerManagerPage({super.key});
  @override
  State<StickerManagerPage> createState() => _StickerManagerPageState();
}

class _StickerManagerPageState extends State<StickerManagerPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await DBManager().queryStickers();
    if (mounted)
      setState(() {
        _items = items;
        _loading = false;
      });
  }

  Future<void> _add() async {
    final emotion = TextEditingController(text: '开心');
    final result = await TideDialogs.show<String>(
        context: context,
        builder: (ctx) {
          final theme = TideTheme.of(ctx);
          return Center(
            child: Material(
              type: MaterialType.transparency,
              child: TideDialogs.glassContent(context: ctx, children: [
                const Text('添加表情包',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 14),
                TextField(
                    controller: emotion,
                    decoration: InputDecoration(
                      labelText: '情绪分类，例如：开心、睡觉',
                      filled: true,
                      fillColor: theme.surfaceVariant,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                    ),
                    style: const TextStyle(fontFamily: 'TideFont')),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: TideDialogs.glassButton('取消',
                          color: theme.buttonSecondary,
                          textColor: theme.textStrong,
                          onTap: () => Navigator.pop(ctx))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TideDialogs.glassButton('选择图片',
                          onTap: () =>
                              Navigator.pop(ctx, emotion.text.trim()))),
                ]),
              ]),
            ),
          );
        });
    emotion.dispose();
    if (result == null || result.isEmpty) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'],
    );
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) return;
    final source = File(sourcePath);
    if (!await source.exists()) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Copy imported files to app storage so persisted stickers do not depend on
    // a transient gallery or document-provider path.
    String storedPath = source.path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/stickers');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = source.path.contains('.')
          ? source.path.split('.').last.toLowerCase()
          : 'png';
      final dest = '${dir.path}/sticker_$now.$ext';
      await source.copy(dest);
      storedPath = dest;
    } catch (_) {
      // Keep the chosen path when a provider cannot be copied.
    }
    await DBManager().insertSticker({
      'id': 'sticker_$now',
      'emotion': result,
      'file_path': storedPath,
      'created_at': now
    });
    _load();
  }

  Widget _stickerPreview(String path, {required BoxFit fit}) {
    if (path.isEmpty || !File(path).existsSync()) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    if (path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(File(path), fit: fit);
    }
    return Image.file(
      File(path),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
            title:
                const Text('表情包管理', style: TextStyle(fontFamily: 'TideFont')),
            actions: [
              IconButton(
                  onPressed: _add,
                  icon: const Icon(Icons.add_photo_alternate_rounded))
            ]),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: theme.primary))
            : _items.isEmpty
                ? Center(
                    child: Text('暂无素材\n可先添加"开心""睡觉"等分类的图片',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: theme.textWeak,
                            height: 1.6,
                            fontFamily: 'TideFont')))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: .78),
                    itemCount: _items.length,
                    itemBuilder: (_, index) {
                      final item = _items[index];
                      final path = item['file_path']?.toString() ?? '';
                      return Stack(children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                                color: theme.surfaceVariant,
                                child:
                                    _stickerPreview(path, fit: BoxFit.cover))),
                        Positioned(
                            left: 7,
                            bottom: 7,
                            child: Text(item['emotion']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'TideFont',
                                    shadows: [Shadow(blurRadius: 4)]))),
                        Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white),
                                onPressed: () async {
                                  await DBManager()
                                      .deleteSticker(item['id'].toString());
                                  _load();
                                }))
                      ]);
                    }),
      ),
    );
  }
}
