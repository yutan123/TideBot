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
    try {
      if (!await AppPermissions.photos(context, feature: '设置全局背景图')) {
        return;
      }
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        imageQuality: 82,
      );
      if (image == null) return;
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory('${documents.path}/global_backgrounds');
      await directory.create(recursive: true);
      // The picker may return a content URI without a useful extension.
      final extension = image.path.split('.').last.toLowerCase();
      final safeExtension =
          RegExp(r'^[a-z0-9]{2,5}$').hasMatch(extension) ? extension : 'jpg';
      final file = File(
        '${directory.path}/background_${DateTime.now().millisecondsSinceEpoch}.$safeExtension',
      );
      await File(image.path).copy(file.path);
      if (!mounted) return;
      await precacheImage(FileImage(file), context);
      if (mounted) setState(() => _path = file.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法选择背景图：$error')),
        );
      }
    }
  }

  Future<void> _save(TideTheme theme) async {
    try {
      final old = theme.globalBackground;
      await theme.setGlobalBackground(
        _path,
        context: context,
        opacity: _opacity,
      );
      // The candidate was precached before this page saves it; remove only the old
      // image after the new path has become the active theme value.
      if (old.isNotEmpty &&
          old != _path &&
          old.contains('/global_backgrounds/')) {
        final file = File(old);
        if (await file.exists()) await file.delete();
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存背景图失败：$error')),
        );
      }
    }
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: _BackgroundAppPreview(
                      theme: theme,
                      hasImage: hasImage,
                    ),
                  ),
                ),
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

class _BackgroundAppPreview extends StatelessWidget {
  const _BackgroundAppPreview({required this.theme, required this.hasImage});

  final TideTheme theme;
  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    final text = hasImage
        ? (theme.isDark ? Colors.white : const Color(0xFF15171B))
        : theme.textStrong;
    final muted = hasImage
        ? (theme.isDark ? Colors.white70 : const Color(0xFF4A4D53))
        : theme.textWeak;
    final card = hasImage
        ? Colors.white.withValues(alpha: theme.isDark ? .24 : .72)
        : theme.surface.withValues(alpha: .92);
    return AspectRatio(
      aspectRatio: .72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .12),
            border: Border.all(color: Colors.white.withValues(alpha: .38)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.primary.withValues(alpha: .86),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.waves_rounded,
                          size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TideBot',
                              style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'TideFont')),
                          Text('我的消息',
                              style: TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                  fontFamily: 'TideFont')),
                        ],
                      ),
                    ),
                    Icon(Icons.more_horiz_rounded, color: text),
                  ],
                ),
                const SizedBox(height: 18),
                Text('早上好',
                    style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 4),
                Text('这是全局背景下的界面效果。',
                    style: TextStyle(
                        color: muted, fontSize: 12, fontFamily: 'TideFont')),
                const SizedBox(height: 16),
                _PreviewMessage(
                  alignment: Alignment.centerLeft,
                  color: card,
                  textColor: text,
                  message: '今天想聊些什么？',
                ),
                const SizedBox(height: 10),
                _PreviewMessage(
                  alignment: Alignment.centerRight,
                  color: theme.primary.withValues(alpha: .88),
                  textColor: Colors.white,
                  message: '看看这个背景效果。',
                ),
                const Spacer(),
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white
                            .withValues(alpha: hasImage ? .34 : .0)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('发送消息',
                            style: TextStyle(
                                color: muted,
                                fontSize: 12,
                                fontFamily: 'TideFont')),
                      ),
                      Icon(Icons.arrow_upward_rounded, color: theme.primary),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          Colors.white.withValues(alpha: hasImage ? .34 : .0),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 19),
                      Icon(Icons.grid_view_rounded, size: 19),
                      Icon(Icons.explore_outlined, size: 19),
                      Icon(Icons.person_outline_rounded, size: 19),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.alignment,
    required this.color,
    required this.textColor,
    required this.message,
  });

  final Alignment alignment;
  final Color color;
  final Color textColor;
  final String message;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(message,
              style: TextStyle(
                  color: textColor, fontSize: 12, fontFamily: 'TideFont')),
        ),
      );
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
