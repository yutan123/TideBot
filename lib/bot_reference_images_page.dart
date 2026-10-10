import 'dart:io';
import 'dart:ui' show ImmutableBuffer, ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'db.dart';
import 'theme.dart';

class BotReferenceImagesPage extends StatefulWidget {
  const BotReferenceImagesPage({super.key});
  @override
  State<BotReferenceImagesPage> createState() => _BotReferenceImagesPageState();
}

class _BotReferenceImagesPageState extends State<BotReferenceImagesPage> {
  List<Map<String, dynamic>>? _bots;
  final Map<String, String> _paths = {};
  final Set<String> _busy = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DBManager();
    final bots = await db.queryBots();
    for (final bot in bots) {
      final id = bot['id'].toString();
      _paths[id] = await db.getKV('bot_image_reference_$id') ?? '';
    }
    if (mounted) setState(() => _bots = bots);
  }

  Future<void> _upload(String id) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    File? saved;
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 95);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024)
        throw const FormatException('图片不能超过 20 MB');
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/bot_reference_images');
      await folder.create(recursive: true);
      // Decode and re-encode through Flutter so uploads always have a known PNG format.
      final codec = await PaintingBinding.instance
          .instantiateImageCodecWithSize(
              await ImmutableBuffer.fromUint8List(bytes));
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) throw const FormatException('无法读取图片');
      saved =
          File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}.png');
      await saved.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await DBManager().setKV('bot_image_reference_$id', saved.path);
      if (mounted) setState(() => _paths[id] = saved!.path);
      saved = null;
    } catch (error) {
      if (saved != null && await saved.exists()) await saved.delete();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传失败：$error')));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.pageBackground,
      appBar: AppBar(title: const Text('生图参考图')),
      body: _bots == null
          ? const Center(child: CircularProgressIndicator())
          : _bots!.isEmpty
              ? const Center(child: Text('暂无机器人'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bots!.length,
                  itemBuilder: (context, index) {
                    final bot = _bots![index];
                    final id = bot['id'].toString();
                    final path = _paths[id] ?? '';
                    return Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              Expanded(
                                  child:
                                      Text(bot['name']?.toString() ?? '机器人')),
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: path.isEmpty
                                          ? const Center(child: Text('空'))
                                          : Image.file(File(path),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Center(
                                                      child: Text('空'))))),
                              const SizedBox(width: 8),
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                TextButton(
                                    onPressed: _busy.contains(id)
                                        ? null
                                        : () => _upload(id),
                                    child: Text(
                                        _busy.contains(id) ? '上传中' : '上传')),
                                if (path.isNotEmpty)
                                  TextButton(
                                      onPressed: _busy.contains(id)
                                          ? null
                                          : () async {
                                              await DBManager().setKV(
                                                  'bot_image_reference_$id',
                                                  '');
                                              if (mounted)
                                                setState(() => _paths[id] = '');
                                            },
                                      child: const Text('移除')),
                              ]),
                            ])));
                  },
                ),
    );
  }
}
