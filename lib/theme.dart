import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'db.dart';

// ================= 全局主题系统 =================
// 每个主题含日/夜两套主色，夜间更沉静、更护眼。
class TideTheme extends ChangeNotifier {
  // 薄荷绿是产品默认主题；其他颜色仅在用户主动选择后使用。
  String _name = 'mint';
  ThemeMode _mode = ThemeMode.system; // 跟随系统，用户可手动切日/夜
  bool _manualMode = false;
  Color _primary = const Color(0xFF5FAF8A);
  Color _primaryLight = const Color(0xFF9CD4BC);
  String _globalBackground = '';
  FileImage? _globalBackgroundImage;
  FileImage? _pendingBackgroundImage;
  String _pendingBackgroundPath = '';
  String _configuredBackgroundPath = '';
  double _configuredDevicePixelRatio = 0;
  Size _configuredSize = Size.zero;
  bool _globalBackgroundReady = false;
  double _globalBackgroundOpacity = 0.38;
  final Map<_BackgroundRegion, bool> _backgroundLightness = {};
  Color get primary => _primary;
  Color get primaryLight => _primaryLight;
  String get name => _name;
  ThemeMode get mode => _mode;
  bool get hasManualMode => _manualMode;
  String get globalBackground => _globalBackground;
  ImageProvider<Object>? get globalBackgroundImage => _globalBackgroundImage;
  bool get isGlobalBackgroundReady => _globalBackgroundReady;
  double get globalBackgroundOpacity => _globalBackgroundOpacity;
  bool get hasGlobalBackground => _globalBackground.isNotEmpty;

  void _setGlobalBackgroundImage(String path) {
    _globalBackgroundReady = path.isEmpty;
    _configuredBackgroundPath = '';
    _configuredDevicePixelRatio = 0;
    _configuredSize = Size.zero;
    _backgroundLightness.clear();
    _globalBackgroundImage = path.isEmpty ? null : FileImage(File(path));
  }

  ImageConfiguration _imageConfiguration(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return createLocalImageConfiguration(
      context,
      size: media?.size,
    );
  }

  Future<bool> precacheGlobalBackground(BuildContext context) async {
    final image = _globalBackgroundImage;
    if (image == null) return false;
    final media = MediaQuery.maybeOf(context);
    final size = media?.size ?? Size.zero;
    final dpr = media?.devicePixelRatio ?? View.of(context).devicePixelRatio;
    if (_configuredBackgroundPath == _globalBackground &&
        _configuredDevicePixelRatio == dpr &&
        _configuredSize == size &&
        _globalBackgroundReady) {
      return true;
    }
    try {
      await precacheImage(image, context, size: size);
      final stream = image.resolve(_imageConfiguration(context));
      final ready = Completer<ui.Image>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          if (!ready.isCompleted) ready.complete(info.image);
        },
        onError: (_, __) {
          stream.removeListener(listener);
          if (!ready.isCompleted) ready.completeError(StateError('背景图片解码失败'));
        },
      );
      stream.addListener(listener);
      await _sampleBackgroundLightness(await ready.future);
      _configuredBackgroundPath = _globalBackground;
      _configuredDevicePixelRatio = dpr;
      _configuredSize = size;
      _globalBackgroundReady = true;
      notifyListeners();
      return true;
    } catch (_) {
      _globalBackgroundReady = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _sampleBackgroundLightness(ui.Image image) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null || image.width == 0 || image.height == 0) return;
    final samples = <_BackgroundRegion, Rect>{
      _BackgroundRegion.header: const Rect.fromLTWH(.15, 0, .7, .18),
      _BackgroundRegion.content: const Rect.fromLTWH(.1, .25, .8, .5),
      _BackgroundRegion.footer: const Rect.fromLTWH(.15, .78, .7, .2),
    };
    for (final entry in samples.entries) {
      var total = 0.0;
      var count = 0;
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 3; x++) {
          final px = ((entry.value.left + entry.value.width * (x / 2)) *
                  (image.width - 1))
              .round()
              .clamp(0, image.width - 1)
              .toInt();
          final py = ((entry.value.top + entry.value.height * (y / 2)) *
                  (image.height - 1))
              .round()
              .clamp(0, image.height - 1)
              .toInt();
          final offset = (py * image.width + px) * 4;
          final r = bytes.getUint8(offset) / 255;
          final g = bytes.getUint8(offset + 1) / 255;
          final b = bytes.getUint8(offset + 2) / 255;
          total += .2126 * r + .7152 * g + .0722 * b;
          count++;
        }
      }
      _backgroundLightness[entry.key] = total / count > .55;
    }
  }

  bool _isBackgroundLight(_BackgroundRegion region) =>
      _backgroundLightness[region] ?? !isDark;

  Color _onBackgroundFor(_BackgroundRegion region, {bool weak = false}) {
    if (!hasGlobalBackground) return weak ? textWeak : textStrong;
    final light = _isBackgroundLight(region);
    if (weak) return light ? const Color(0xFF30343A) : const Color(0xFFE2E6EA);
    return light ? const Color(0xFF101216) : const Color(0xFFF8F9FA);
  }

  Color get onBackgroundStrong => _onBackgroundFor(_BackgroundRegion.content);
  Color get onBackgroundWeak =>
      _onBackgroundFor(_BackgroundRegion.content, weak: true);
  Color get onBackgroundIcon => onBackgroundStrong;
  Color get backgroundScrim => backgroundOverlayColor.withValues(
        alpha: effectiveBackgroundOpacity,
      );

  bool get isDark {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (_mode == ThemeMode.system) return brightness == Brightness.dark;
    return _mode == ThemeMode.dark;
  }

  LinearGradient get primaryGradient =>
      LinearGradient(colors: [_primary, _primaryLight]);
  Color get bgColor => hasGlobalBackground
      ? Colors.transparent
      : (isDark ? const Color(0xFF171A20) : const Color(0xFFF3F5FA));
  Color get backgroundOverlayColor =>
      isDark ? const Color(0xFF06080C) : const Color(0xFF101216);
  double get effectiveBackgroundOpacity {
    if (!hasGlobalBackground) return 0;
    final readabilityFloor = isDark ? 0.24 : 0.18;
    return _globalBackgroundOpacity < readabilityFloor
        ? readabilityFloor
        : _globalBackgroundOpacity;
  }

  Color get surface =>
      isDark ? const Color(0xFF20242C) : const Color(0xFFFFFFFF);
  Color get surfaceVariant =>
      isDark ? const Color(0xFF2B303A) : const Color(0xFFE9EDF5);
  Color get glass => isDark ? const Color(0xE01D222B) : const Color(0xC9FFFFFF);

  // Night surfaces stay neutral graphite so theme accents and image content remain distinct.

  // 文字主色
  Color get textStrong =>
      isDark ? const Color(0xFFECEDF0) : const Color(0xFF1C1C1E);
  Color get textWeak =>
      isDark ? const Color(0xFF8A8F98) : const Color(0xFF636366);
  // 更弱的文字/图标色
  Color get textFaint =>
      isDark ? const Color(0xFF5A5F68) : const Color(0xFFC7C7CC);
  // 分割线
  Color get divider =>
      isDark ? const Color(0x22FFFFFF) : const Color(0x14000000);
  // 边框
  Color get border =>
      isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000);
  // 图标弱色
  Color get iconMuted =>
      isDark ? const Color(0xFF9AA1A9) : const Color(0xFF8E8E93);
  // AI/次要气泡底色（日间浅白、夜间深灰）
  Color get bubbleAi =>
      isDark ? const Color(0xFF292E38) : const Color(0xFFFFFFFF);

  // 次要按钮底色（取消、次级操作）
  Color get buttonSecondary =>
      isDark ? const Color(0xFF33363E) : const Color(0xFFE8E8F0);

  // 主题配色：主色 + 亮色 + 中文名 + 深色底主色（护眼） + 深色亮色
  static const _themes = {
    'rose': {
      'name': '玫瑰粉',
      'light': [Color(0xFFD98C94), Color(0xFFE8B8BE)],
      'dark': [Color(0xFFD98A92), Color(0xFFB0707A)]
    },
    'aurora': {
      'name': '极光蓝',
      'light': [Color(0xFF6C8CD5), Color(0xFFA7BEE8)],
      'dark': [Color(0xFF7D9BE0), Color(0xFF5A7499)]
    },
    'lavender': {
      'name': '薰衣草',
      'light': [Color(0xFF9B8AC4), Color(0xFFC5B8E0)],
      'dark': [Color(0xFFA79ACD), Color(0xFF7C6FA3)]
    },
    'sky': {
      'name': '雾霾蓝',
      'light': [Color(0xFF5D9BC5), Color(0xFF9CC5E3)],
      'dark': [Color(0xFF6FA9D2), Color(0xFF4A7DA0)]
    },
    'mint': {
      'name': '薄荷绿',
      'light': [Color(0xFF5FAF8A), Color(0xFF9CD4BC)],
      'dark': [Color(0xFF6BB996), Color(0xFF4A8F72)]
    },
    'peach': {
      'name': '蜜桃橙',
      'light': [Color(0xFFE39A6B), Color(0xFFF0C4A0)],
      'dark': [Color(0xFFE8A678), Color(0xFFB97D50)]
    },
    'plum': {
      'name': '梅子紫',
      'light': [Color(0xFF8E74B4), Color(0xFFB7A6D6)],
      'dark': [Color(0xFF9A80C0), Color(0xFF6E5895)]
    },
    'teal': {
      'name': '青瓷绿',
      'light': [Color(0xFF4FA79C), Color(0xFF92CFC8)],
      'dark': [Color(0xFF59B3A8), Color(0xFF3E857C)]
    },
    'sunset': {
      'name': '落日橙',
      'light': [Color(0xFFE06A5A), Color(0xFFF2A79A)],
      'dark': [Color(0xFFE87668), Color(0xFFB4554A)]
    },
    'ocean': {
      'name': '深海蓝',
      'light': [Color(0xFF3E7CB1), Color(0xFF7FAFDB)],
      'dark': [Color(0xFF4C8EC4), Color(0xFF33658A)]
    },
    'pinkg': {
      'name': '樱花粉',
      'light': [Color(0xFFE07A9A), Color(0xFFF0B3C6)],
      'dark': [Color(0xFFE886A4), Color(0xFFB55A78)]
    },
    'night': {
      'name': '午夜紫',
      'light': [Color(0xFF6B5FAE), Color(0xFF9D92D0)],
      'dark': [Color(0xFF786BC0), Color(0xFF524A86)]
    },
  };

  static List<Map<String, String>> get themeOptions => _themes.entries
      .map((e) => {'id': e.key, 'name': (e.value['name']!) as String})
      .toList();

  Future<void> loadFromDB() async {
    final name = await DBManager().getKV('theme_color');
    if (name != null && _themes.containsKey(name)) {
      _name = name;
      _applyColors();
    }
    // 读取日夜模式
    final modeStr = await DBManager().getKV('theme_mode');
    if (modeStr != null) {
      if (modeStr == 'system') {
        _mode = ThemeMode.system;
        _manualMode = false;
      } else if (modeStr == 'light') {
        _mode = ThemeMode.light;
        _manualMode = true;
      } else if (modeStr == 'dark') {
        _mode = ThemeMode.dark;
        _manualMode = true;
      }
    }
    // 读取全局背景图。它与每个机器人各自的聊天背景完全独立。
    final globalBackground = await DBManager().getKV('global_background_image');
    if (globalBackground != null &&
        globalBackground.isNotEmpty &&
        File(globalBackground).existsSync()) {
      _globalBackground = globalBackground;
      _setGlobalBackgroundImage(globalBackground);
    } else if (globalBackground != null && globalBackground.isNotEmpty) {
      await DBManager().insertKV('global_background_image', '');
    }
    _globalBackgroundOpacity = (double.tryParse(
              await DBManager().getKV('global_background_opacity') ?? '',
            ) ??
            _globalBackgroundOpacity)
        .clamp(0.18, 0.70);
    notifyListeners();
  }

  void _applyColors() {
    final t = _themes[_name]!;
    final dark = isDark;
    final palette =
        ((dark ? t['dark'] : t['light'])! as List<Object>).cast<Color>();
    _primary = palette[0];
    _primaryLight = palette[1];
  }

  Future<void> setTheme(String name) async {
    if (!_themes.containsKey(name)) return;
    _name = name;
    _applyColors();
    await DBManager().insertKV('theme_color', name);
    notifyListeners();
  }

  // 切换日夜：system->light->dark->system
  Future<String> cycleMode() async {
    if (_mode == ThemeMode.system) {
      _mode = ThemeMode.light;
      _manualMode = true;
    } else if (_mode == ThemeMode.light) {
      _mode = ThemeMode.dark;
      _manualMode = true;
    } else {
      _mode = ThemeMode.system;
      _manualMode = false;
    }
    _applyColors();
    await DBManager().insertKV(
        'theme_mode',
        _mode == ThemeMode.dark
            ? 'dark'
            : (_mode == ThemeMode.light ? 'light' : 'system'));
    notifyListeners();
    return _mode == ThemeMode.dark
        ? 'dark'
        : (_mode == ThemeMode.light ? 'light' : 'system');
  }

  void applySystemBrightness() {
    _applyColors();
    notifyListeners();
  }

  Future<void> setGlobalBackground(
    String path, {
    required BuildContext context,
    double? opacity,
  }) async {
    if (opacity != null) _globalBackgroundOpacity = opacity.clamp(0.18, 0.70);

    if (path.isEmpty) {
      await DBManager().insertKV('global_background_image', '');
      await DBManager().insertKV(
        'global_background_opacity',
        _globalBackgroundOpacity.toStringAsFixed(2),
      );
      _pendingBackgroundImage = null;
      _pendingBackgroundPath = '';
      _globalBackground = '';
      _setGlobalBackgroundImage('');
      notifyListeners();
      return;
    }
    if (!File(path).existsSync()) {
      throw StateError('背景图片不存在或无法读取');
    }

    final candidate = FileImage(File(path));
    try {
      await precacheImage(candidate, context,
          size: MediaQuery.maybeOf(context)?.size);
      final stream = candidate.resolve(_imageConfiguration(context));
      final ready = Completer<ui.Image>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, __) {
          stream.removeListener(listener);
          if (!ready.isCompleted) ready.complete(info.image);
        },
        onError: (_, __) {
          stream.removeListener(listener);
          if (!ready.isCompleted) {
            ready.completeError(StateError('背景图片解码失败'));
          }
        },
      );
      stream.addListener(listener);
      final decoded = await ready.future;
      await _sampleBackgroundLightness(decoded);
    } catch (_) {
      // Preserve the previously active image and database value on failure.
      rethrow;
    }
    _pendingBackgroundImage = candidate;
    _pendingBackgroundPath = path;
    if (_pendingBackgroundImage != candidate ||
        _pendingBackgroundPath != path) {
      return;
    }

    _globalBackground = path;
    _globalBackgroundImage = candidate;
    _configuredBackgroundPath = path;
    _configuredDevicePixelRatio =
        MediaQuery.maybeOf(context)?.devicePixelRatio ??
            View.of(context).devicePixelRatio;
    _configuredSize = MediaQuery.maybeOf(context)?.size ?? Size.zero;
    _globalBackgroundReady = true;
    _pendingBackgroundImage = null;
    _pendingBackgroundPath = '';
    await DBManager().insertKV('global_background_image', path);
    await DBManager().insertKV(
      'global_background_opacity',
      _globalBackgroundOpacity.toStringAsFixed(2),
    );
    notifyListeners();
  }

  /// Restores the shipped mint palette and system appearance.
  Future<void> restoreDefaults() async {
    _name = 'mint';
    _mode = ThemeMode.system;
    _manualMode = false;
    _globalBackground = '';
    _setGlobalBackgroundImage('');
    _globalBackgroundOpacity = 0.38;
    _applyColors();
    await DBManager().insertKV('theme_color', _name);
    await DBManager().insertKV('theme_mode', 'system');
    await DBManager().insertKV('global_background_image', '');
    await DBManager().insertKV('global_background_opacity', '0.38');
    notifyListeners();
  }

  static TideTheme of(BuildContext context, {bool listen = true}) {
    return listen
        ? TideBotThemeProvider.of(context)
        : (context
                .dependOnInheritedWidgetOfExactType<_TideThemeWidget>()
                ?.theme ??
            TideTheme());
  }
}

enum _BackgroundRegion { header, content, footer }

class _TideThemeWidget extends InheritedNotifier<TideTheme> {
  const _TideThemeWidget({required this.theme, required super.child})
      : super(notifier: theme);
  final TideTheme theme;
}

class TideBotThemeProvider extends StatelessWidget {
  final TideTheme theme;
  final Widget child;
  const TideBotThemeProvider(
      {super.key, required this.theme, required this.child});
  static TideTheme of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<_TideThemeWidget>();
    return w?.theme ?? TideTheme();
  }

  @override
  Widget build(BuildContext context) =>
      _TideThemeWidget(theme: theme, child: child);
}
