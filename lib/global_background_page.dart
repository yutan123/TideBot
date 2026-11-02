import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_permissions.dart';
import 'chat_background_defaults.dart';
import 'db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'main.dart' show JellyDock;
import 'ui_space_square.dart' show SpacePage;

class GlobalBackgroundPage extends StatefulWidget {
  const GlobalBackgroundPage({super.key});

  @override
  State<GlobalBackgroundPage> createState() => _GlobalBackgroundPageState();
}

class _GlobalBackgroundPageState extends State<GlobalBackgroundPage> {
  late String _path;
  late double _opacity;
  late bool _enableLiquidGlass;
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
      final safeExtension = RegExp(r'^[a-z0-9]{2,5}$').hasMatch(extension)
          ? extension
          : 'jpg';
      final file = File(
        '${directory.path}/background_${DateTime.now().millisecondsSinceEpoch}.$safeExtension',
      );
      await File(image.path).copy(file.path);
      if (!mounted) return;
      await precacheImage(FileImage(file), context);
      if (mounted) setState(() => _path = file.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法选择背景图：$error')));
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
        enableLiquidGlass: _enableLiquidGlass,
      );
      if (_path.isNotEmpty) {
        final documents = await getApplicationDocumentsDirectory();
        final bots = await DBManager().queryBots();
        await copyGlobalToUnsetChatBackgrounds(
          sourcePath: _path,
          botIds: bots.map((bot) => bot['id']?.toString() ?? ''),
          directory: Directory('${documents.path}/chat_backgrounds'),
          prefs: await SharedPreferences.getInstance(),
        );
      }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存背景图失败：$error')));
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
      _enableLiquidGlass = theme.enableLiquidGlass;
    }
    final hasImage = _path.isNotEmpty && File(_path).existsSync();
    return TideBackground(
      excludeGlobalBackground: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
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
                        path: _path,
                        opacity: _opacity,
                        enableLiquidGlass: _enableLiquidGlass,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: _ControlSurface(
                      theme: theme,
                      hasImage: hasImage,
                      opacity: _opacity,
                      enableLiquidGlass: _enableLiquidGlass,
                      onPick: _pick,
                      onClear: () => setState(() => _path = ''),
                      onOpacityChanged: (value) =>
                          setState(() => _opacity = value),
                      onLiquidGlassChanged: (value) =>
                          setState(() => _enableLiquidGlass = value),
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

/// Renders a device-sized app scene, then scales the entire scene for display.
/// The actual space widgets, dock, background and theme rules are shared.
class _BackgroundAppPreview extends StatefulWidget {
  const _BackgroundAppPreview({
    required this.theme,
    required this.hasImage,
    required this.path,
    required this.opacity,
    required this.enableLiquidGlass,
  });
  final TideTheme theme;
  final bool hasImage;
  final String path;
  final double opacity;
  final bool enableLiquidGlass;
  @override
  State<_BackgroundAppPreview> createState() => _BackgroundAppPreviewState();
}

class _BackgroundAppPreviewState extends State<_BackgroundAppPreview> {
  final TideTheme _previewTheme = TideTheme();
  @override
  void initState() {
    super.initState();
    _updatePreview();
  }

  @override
  void didUpdateWidget(covariant _BackgroundAppPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePreview();
  }

  void _updatePreview() {
    _previewTheme.configureBackgroundPreview(
      widget.theme,
      path: widget.hasImage ? widget.path : '',
      opacity: widget.opacity,
      enableLiquidGlass: widget.enableLiquidGlass,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_previewTheme.precacheGlobalBackground(context));
    });
  }

  @override
  void dispose() {
    // Invalidate any pending image warm-up before disposing its notifier.
    _previewTheme.configureBackgroundPreview(
      widget.theme,
      path: '',
      opacity: widget.opacity,
      enableLiquidGlass: false,
      notify: false,
    );
    _previewTheme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: media.size.width,
          height: media.size.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: RepaintBoundary(
              child: IgnorePointer(
                child: MediaQuery(
                  data: media.copyWith(viewInsets: EdgeInsets.zero),
                  child: TideBotThemeProvider(
                    theme: _previewTheme,
                    child: TideBackground(
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: SpacePage(previewOnly: true),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: media.padding.bottom + 24,
                            child: JellyDock(currentIndex: 1, onTap: (_) {}),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
    required this.enableLiquidGlass,
    required this.onPick,
    required this.onClear,
    required this.onOpacityChanged,
    required this.onLiquidGlassChanged,
  });

  final TideTheme theme;
  final bool hasImage;
  final double opacity;
  final bool enableLiquidGlass;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<bool> onLiquidGlassChanged;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
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
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFF3B30),
                ),
                title: const Text('清除全局背景图'),
                onTap: onClear,
              ),
            if (hasImage)
              SwitchListTile(
                secondary: Icon(Icons.blur_on_rounded, color: theme.primary),
                title: const Text('启用液态玻璃'),
                subtitle: const Text('开启流光折射；关闭后保留常规卡片和按钮样式'),
                value: enableLiquidGlass,
                onChanged: onLiquidGlassChanged,
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
