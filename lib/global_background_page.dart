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
  late String _path;
  late double _opacity;
  bool _ready = false;

  Future<void> _pick() async {
    if (!await AppPermissions.photos(context, feature: '设置全局背景图')) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 90,
    );
    if (image == null) return;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/global_backgrounds');
    await directory.create(recursive: true);
    final extension = image.path.split('.').last;
    final file = File(
      '${directory.path}/background_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await File(image.path).copy(file.path);
    if (mounted) setState(() => _path = file.path);
  }

  Future<void> _save(TideTheme theme) async {
    final old = theme.globalBackground;
    await theme.setGlobalBackground(_path, opacity: _opacity);
    if (old.isNotEmpty &&
        old != _path &&
        old.contains('/global_backgrounds/')) {
      final file = File(old);
      if (await file.exists()) await file.delete();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    if (!_ready) {
      _ready = true;
      _path = theme.globalBackground;
      _opacity = theme.globalBackgroundOpacity;
    }
    final preview = Stack(
      fit: StackFit.expand,
      children: [
        if (_path.isNotEmpty && File(_path).existsSync())
          Image.file(File(_path), fit: BoxFit.cover)
        else
          ColoredBox(color: theme.surfaceVariant),
        ColoredBox(color: Colors.black.withValues(alpha: _opacity)),
        const _PreviewSurface(),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('全局背景图'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: () => _save(theme),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AspectRatio(
            aspectRatio: .68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: preview,
            ),
          ),
          const SizedBox(height: 16),
          TideLiquidGlass(
            radius: 16,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(_path.isEmpty ? '选择图片' : '替换图片'),
                  onTap: _pick,
                ),
                if (_path.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('清除全局背景图'),
                    onTap: () => setState(() => _path = ''),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.contrast_rounded, size: 20),
                      Expanded(
                        child: Slider(
                          value: _opacity,
                          min: .18,
                          max: .70,
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
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          children: [
            TideLiquidGlass(
              radius: 20,
              child: SizedBox(height: 52, child: Center(child: Text('页面与弹窗'))),
            ),
            Spacer(),
            TideLiquidGlass(
              radius: 18,
              child: SizedBox(height: 96, width: double.infinity),
            ),
            Spacer(),
            TideLiquidGlass(
              radius: 28,
              child: SizedBox(height: 56, width: double.infinity),
            ),
          ],
        ),
      );
}
