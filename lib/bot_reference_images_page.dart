import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'bot_reference_image.dart';
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

  void _error(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _upload(String id) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    File? saved;
    try {
      // Document providers do not require a resolvable MediaStore image URI.
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      if (picked.size > 20 * 1024 * 1024)
        throw const FormatException('图片不能超过 20 MB');
      final bytes = picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw const FormatException('无法读取所选图片，请先保存到本机再选择');
      final png = await prepareBotReferenceImage(bytes);
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/bot_reference_images');
      await folder.create(recursive: true);
      saved =
          File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}.png');
      await saved.writeAsBytes(png, flush: true);
      await DBManager().setKV('bot_image_reference_$id', saved.path);
      if (mounted) setState(() => _paths[id] = saved!.path);
      saved = null;
    } on FormatException catch (error) {
      _error('上传失败：${error.message}');
    } on PlatformException catch (error) {
      debugPrint('Reference image picker failed: $error');
      _error('无法读取所选图片，请将图片保存到本机后重试');
    } catch (error, stack) {
      debugPrint('Reference image upload failed: $error\n$stack');
      _error('图片读取或保存失败，请选择本机的 JPG、PNG 或 WebP 图片重试');
    } finally {
      if (saved != null) {
        try {
          if (await saved.exists()) await saved.delete();
        } catch (error) {
          debugPrint('Reference image cleanup failed: $error');
        }
      }
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _remove(String id) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await DBManager().setKV('bot_image_reference_$id', '');
      if (mounted) setState(() => _paths[id] = '');
    } catch (_) {
      _error('移除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.pageBackground,
      appBar: AppBar(
          title: const Text('生图参考图'),
          backgroundColor: theme.pageBackground,
          foregroundColor: theme.textStrong,
          surfaceTintColor: Colors.transparent,
          elevation: 0),
      body: _bots == null
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : _bots!.isEmpty
              ? Center(
                  child: Text('暂无机器人', style: TextStyle(color: theme.textWeak)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _bots!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final bot = _bots![index];
                    final id = bot['id'].toString();
                    final path = _paths[id] ?? '';
                    final busy = _busy.contains(id);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: theme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: theme.divider)),
                      child: Row(children: [
                        Container(
                            width: 52,
                            height: 52,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                                color: theme.surfaceVariant,
                                borderRadius: BorderRadius.circular(12)),
                            child: path.isEmpty
                                ? Center(
                                    child: Text('空',
                                        style: TextStyle(
                                            color: theme.textWeak,
                                            fontSize: 13)))
                                : Image.file(File(path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                        child: Text('失效',
                                            style: TextStyle(
                                                color: theme.textWeak,
                                                fontSize: 12))))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(bot['name']?.toString() ?? '机器人',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: theme.textStrong,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(path.isEmpty ? '未设置参考图' : '已设置生图参考',
                                  style: TextStyle(
                                      color: theme.textWeak, fontSize: 12)),
                            ])),
                        const SizedBox(width: 8),
                        TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: theme.primary,
                                backgroundColor:
                                    theme.primary.withValues(alpha: .1),
                                minimumSize: const Size(56, 36),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            onPressed: busy ? null : () => _upload(id),
                            child: busy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: theme.primary))
                                : Text(path.isEmpty ? '上传' : '更换')),
                        if (path.isNotEmpty)
                          PopupMenuButton<String>(
                              enabled: !busy,
                              tooltip: '更多操作',
                              color: theme.surface,
                              icon: Icon(Icons.more_vert,
                                  color: theme.iconMuted, size: 20),
                              onSelected: (_) => _remove(id),
                              itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'remove',
                                        child: Text('移除参考图',
                                            style: TextStyle(
                                                color: theme.textStrong)))
                                  ]),
                      ]),
                    );
                  },
                ),
    );
  }
}
