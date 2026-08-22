import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_permissions.dart';
import 'db.dart';
import 'theme.dart';

class ChatBackgroundPage extends StatefulWidget {
  const ChatBackgroundPage({super.key});

  @override
  State<ChatBackgroundPage> createState() => _ChatBackgroundPageState();
}

class _ChatBackgroundPageState extends State<ChatBackgroundPage> {
  List<Map<String, dynamic>> _bots = const [];
  final Set<String> _selected = <String>{};
  Map<String, String> _backgrounds = <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bots = await DBManager().queryBots();
    final prefs = await SharedPreferences.getInstance();
    final backgrounds = <String, String>{};
    for (final bot in bots) {
      final id = bot['id']?.toString() ?? '';
      final path = prefs.getString('chat_bg_$id') ?? '';
      if (id.isNotEmpty && path.isNotEmpty && await File(path).exists()) {
        backgrounds[id] = path;
      }
    }
    if (!mounted) return;
    setState(() {
      _bots = bots;
      _backgrounds = backgrounds;
      _loading = false;
    });
  }

  Future<void> _deleteIfUnused(String path, SharedPreferences prefs) async {
    if (!path.contains('/chat_backgrounds/')) return;
    for (final bot in _bots) {
      final id = bot['id']?.toString() ?? '';
      if (id.isNotEmpty && prefs.getString('chat_bg_$id') == path) return;
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> _pickForSelected() async {
    if (_selected.isEmpty) {
      _notice('请先选择机器人');
      return;
    }
    if (!await AppPermissions.photos(context, feature: '设置聊天背景图')) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 90,
    );
    if (image == null) return;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/chat_backgrounds');
    await directory.create(recursive: true);
    final extension = image.path.split('.').last.toLowerCase();
    final file = File(
      '${directory.path}/background_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await File(image.path).copy(file.path);
    final prefs = await SharedPreferences.getInstance();
    for (final id in _selected) {
      final old = _backgrounds[id];
      await prefs.setString('chat_bg_$id', file.path);
      if (old != null && old != file.path) {
        await _deleteIfUnused(old, prefs);
      }
    }
    if (!mounted) return;
    setState(() {
      for (final id in _selected) {
        _backgrounds[id] = file.path;
      }
    });
    _notice('已应用到 ${_selected.length} 个机器人');
  }

  Future<void> _clearSelected() async {
    if (_selected.isEmpty) {
      _notice('请先选择机器人');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final id in _selected) {
      final old = _backgrounds[id];
      await prefs.remove('chat_bg_$id');
      if (old != null) await _deleteIfUnused(old, prefs);
    }
    if (!mounted) return;
    setState(() {
      for (final id in _selected) {
        _backgrounds.remove(id);
      }
    });
    _notice('已清除所选机器人的聊天背景');
  }

  void _notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(title: const Text('聊天背景图')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Text('选择机器人',
                          style: TextStyle(
                              color: theme.textWeak, fontFamily: 'TideFont')),
                      const Spacer(),
                      Text('${_selected.length} 个已选',
                          style: TextStyle(
                              color: theme.textFaint, fontFamily: 'TideFont')),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    itemCount: _bots.length,
                    itemBuilder: (context, index) {
                      final bot = _bots[index];
                      final id = bot['id']?.toString() ?? '';
                      final selected = _selected.contains(id);
                      final path = _backgrounds[id];
                      return Card(
                        color: theme.surface,
                        child: CheckboxListTile(
                          activeColor: theme.primary,
                          checkColor: Colors.white,
                          value: selected,
                          onChanged: (_) => setState(() => selected
                              ? _selected.remove(id)
                              : _selected.add(id)),
                          secondary: path == null
                              ? CircleAvatar(
                                  child: Text((bot['name']?.toString() ?? '机')
                                      .characters
                                      .first))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(File(path),
                                      width: 48, height: 48, fit: BoxFit.cover),
                                ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  bot['name']?.toString() ?? '未命名机器人',
                                  style:
                                      const TextStyle(fontFamily: 'TideFont'),
                                ),
                              ),
                              if (path != null)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: theme.primary,
                                  size: 19,
                                ),
                            ],
                          ),
                          subtitle: Text(path == null ? '未设置聊天背景' : '已设置聊天背景',
                              style: const TextStyle(fontFamily: 'TideFont')),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.primary,
                  side: BorderSide(color: theme.primary),
                ),
                onPressed: _clearSelected,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('清除'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _pickForSelected,
                icon: const Icon(Icons.wallpaper_rounded),
                label: const Text('选择图片'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
