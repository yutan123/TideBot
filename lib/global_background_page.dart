import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_permissions.dart';
import 'theme.dart';
import 'tide_liquid_glass.dart';

class GlobalBackgroundPage extends StatefulWidget {
  const GlobalBackgroundPage({super.key});

  @override
  State<GlobalBackgroundPage> createState() => _GlobalBackgroundPageState();
}

class _GlobalBackgroundPageState extends State<GlobalBackgroundPage> {
  bool _initialized = false;
  late String _path;
  late double _opacity;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pick() async {
    if (!await AppPermissions.photos(context, feature: '设置全局背景图')) return;
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 90,
    );
    if (selected == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${directory.path}/global_backgrounds');
    await targetDir.create(recursive: true);
    final extension = selected.path.split('.').last;
    final target = File(
      '${targetDir.path}/background_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await File(selected.path).copy(target.path);
    if (mounted) setState(() => _path = target.path);
  }

  Future<void> _save(TideTheme theme) async {
    final previous = theme.chatBg;
    await theme.setChatBg(_path, opacity: _opacity);
    if (previous.isNotEmpty &&
        previous != _path &&
        previous.contains('/global_backgrounds/')) {
      final old = File(previous);
      if (await old.exists()) await old.delete();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    if (!_initialized) {
      _initialized = true;
      _path = theme.chatBg;
      _opacity = theme.backgroundOpacity;
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('全局背景图', style: TextStyle(fontFamily: 'TideFont')),
        actions: [
          TextButton(
            onPressed: () => _save(theme),
            child: Text('保存',
                style: TextStyle(color: theme.primary, fontFamily: 'TideFont')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            AspectRatio(
              aspectRatio: 0.68,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: theme.bgColor),
                    if (_path.isNotEmpty && File(_path).existsSync())
                      Image.file(File(_path), fit: BoxFit.cover),
                    ColoredBox(
                      color: (theme.isDark
                              ? const Color(0xFF081012)
                              : Colors.white)
                          .withValues(alpha: _opacity),
                    ),
                    const _ChatPreview(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TideLiquidGlass(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.image_rounded),
                    title: Text(_path.isEmpty ? '选择背景图' : '替换背景图'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pick,
                  ),
                  if (_path.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded),
                      title: const Text('清除背景图'),
                      onTap: () => setState(() => _path = ''),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        const Icon(Icons.opacity_rounded, size: 20),
                        Expanded(
                          child: Slider(
                            value: _opacity,
                            min: 0.20,
                            max: 0.82,
                            onChanged: (value) =>
                                setState(() => _opacity = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPreview extends StatelessWidget {
  const _ChatPreview();

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          const TideLiquidGlass(
            radius: 16,
            child: ListTile(
              dense: true,
              leading: CircleAvatar(child: Icon(Icons.smart_toy_rounded)),
              title: Text('TideBot', style: TextStyle(fontFamily: 'TideFont')),
            ),
          ),
          const Spacer(),
          const Align(
            alignment: Alignment.centerLeft,
            child: TideLiquidGlass(
              radius: 16,
              child: Padding(
                padding: EdgeInsets.all(12),
                child:
                    Text('今天过得怎么样？', style: TextStyle(fontFamily: 'TideFont')),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('还不错。',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'TideFont')),
              ),
            ),
          ),
          const Spacer(),
          const TideLiquidGlass(
            radius: 18,
            child: SizedBox(
                height: 44,
                child: Center(
                    child:
                        Text('发消息', style: TextStyle(fontFamily: 'TideFont')))),
          ),
        ],
      ),
    );
  }
}
