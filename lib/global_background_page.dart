import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_permissions.dart';
import 'theme.dart';

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
    if (!mounted) return;
    await precacheImage(FileImage(file), context);
    if (mounted) setState(() => _path = file.path);
  }

  Future<void> _save(TideTheme theme) async {
    final old = theme.globalBackground;
    await theme.setGlobalBackground(_path, opacity: _opacity);
    // The candidate was precached before this page saves it; remove only the old
    // image after the new path has become the active theme value.
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
    final hasImage = _path.isNotEmpty && File(_path).existsSync();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
              color: theme.isDark
                  ? const Color(0xFF101619)
                  : const Color(0xFFF3F5FA)),
          if (hasImage) Image.file(File(_path), fit: BoxFit.cover),
          if (hasImage)
            IgnorePointer(
              child:
                  ColoredBox(color: Colors.black.withValues(alpha: _opacity)),
            ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  title: '全局背景图',
                  primary: theme.primary,
                  onBack: () => Navigator.pop(context),
                  onSave: () => _save(theme),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: _ControlSurface(
                    theme: theme,
                    hasImage: hasImage,
                    opacity: _opacity,
                    onPick: _pick,
                    onClear: () => setState(() => _path = ''),
                    onOpacityChanged: (value) =>
                        setState(() => _opacity = value),
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.primary,
    required this.onBack,
    required this.onSave,
  });

  final String title;
  final Color primary;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: primary),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: '保存',
            onPressed: onSave,
            icon: Icon(Icons.check_rounded, color: primary),
          ),
        ],
      ),
    );
  }
}

class _ControlSurface extends StatelessWidget {
  const _ControlSurface({
    required this.theme,
    required this.hasImage,
    required this.opacity,
    required this.onPick,
    required this.onClear,
    required this.onOpacityChanged,
  });

  final TideTheme theme;
  final bool hasImage;
  final double opacity;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<double> onOpacityChanged;

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return Material(
      color: theme.surface.withValues(alpha: theme.isDark ? 0.94 : 0.92),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: shape,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.image_outlined, color: theme.primary),
              title: Text(hasImage ? '替换图片' : '选择图片'),
              onTap: onPick,
            ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF3B30)),
                title: const Text('清除全局背景图'),
                onTap: onClear,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.contrast_rounded, color: theme.primary, size: 20),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: theme.primary,
                        thumbColor: theme.primary,
                        overlayColor: theme.primary.withValues(alpha: 0.16),
                      ),
                      child: Slider(
                        value: opacity,
                        min: .18,
                        max: .70,
                        onChanged: onOpacityChanged,
                      ),
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
