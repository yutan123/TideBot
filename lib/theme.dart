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
  String _chatBg = ''; // 全局聊天背景图路径（自定义，可为空）

  Color get primary => _primary;
  Color get primaryLight => _primaryLight;
  String get name => _name;
  ThemeMode get mode => _mode;
  bool get hasManualMode => _manualMode;
  String get chatBg => _chatBg;

  bool get isDark {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (_mode == ThemeMode.system) return brightness == Brightness.dark;
    return _mode == ThemeMode.dark;
  }

  LinearGradient get primaryGradient =>
      LinearGradient(colors: [_primary, _primaryLight]);
  // 界面背景（日/夜通用底色），供 FlowGlassBg 与聊天室兜底使用
  Color get bgColor =>
      isDark ? const Color(0xFF151416) : const Color(0xFFF3F5FA);
  // 卡片 / 输入框 / 弹窗浮层：夜间采用带蓝灰倾向的深表面，避免纯黑割裂。
  Color get surface =>
      isDark ? const Color(0xFF211F22) : const Color(0xFFFFFFFF);
  // 次级表面（输入框内部、芯片、弱浮层）
  Color get surfaceVariant =>
      isDark ? const Color(0xFF302C31) : const Color(0xFFE9EDF5);
  // 毛玻璃层：夜间必须是低亮度深色玻璃，不能使用半透明白色。
  Color get glass => isDark ? const Color(0xE6272428) : const Color(0xC9FFFFFF);

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
      isDark ? const Color(0xFF262A31) : const Color(0xFFFFFFFF);
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
    // 读取全局聊天背景
    final bg = await DBManager().getKV('chat_bg_global');
    if (bg != null && bg.isNotEmpty) _chatBg = bg;
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

  Future<void> setChatBg(String path) async {
    _chatBg = path;
    await DBManager().insertKV('chat_bg_global', path);
    notifyListeners();
  }

  /// Restores the shipped mint palette, system appearance and default background.
  Future<void> restoreDefaults() async {
    _name = 'mint';
    _mode = ThemeMode.system;
    _manualMode = false;
    _chatBg = '';
    _applyColors();
    await DBManager().insertKV('theme_color', _name);
    await DBManager().insertKV('theme_mode', 'system');
    await DBManager().insertKV('chat_bg_global', '');
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
