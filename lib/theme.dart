import 'package:flutter/material.dart';
import 'db.dart';

// ================= 全局主题系统 =================
class TideTheme extends ChangeNotifier {
  String _name = 'lavender';
  Color _primary = const Color(0xFFB8A9C9);
  Color _primaryLight = const Color(0xFFD5C6E0);
  Color get primary => _primary;
  Color get primaryLight => _primaryLight;
  String get name => _name;
  LinearGradient get primaryGradient => LinearGradient(colors: [_primary, _primaryLight]);

  static const _themes = {
    'rose':      [Color(0xFFD4A5A5), Color(0xFFE8C8C8)],
    'lavender':  [Color(0xFFB8A9C9), Color(0xFFD5C6E0)],
    'sky':       [Color(0xFF89B0C8), Color(0xFFB5D3E7)],
    'mint':      [Color(0xFF8FBC8F), Color(0xFFB8D8B8)],
    'peach':     [Color(0xFFE8B89D), Color(0xFFF5D0B8)],
    'plum':      [Color(0xFFA593C2), Color(0xFFC9B8E8)],
    'teal':      [Color(0xFF6FA8A0), Color(0xFFA3D2C8)],
  };

  Future<void> loadFromDB() async {
    final name = await DBManager().getKV('theme_color');
    if (name != null && _themes.containsKey(name)) {
      _name = name;
      _primary = _themes[name]![0];
      _primaryLight = _themes[name]![1];
      notifyListeners();
    }
  }

  Future<void> setTheme(String name) async {
    if (!_themes.containsKey(name)) return;
    _name = name;
    _primary = _themes[name]![0];
    _primaryLight = _themes[name]![1];
    await DBManager().insertKV('theme_color', name);
    notifyListeners();
  }

  static TideTheme of(BuildContext context, {bool listen = true}) {
    return listen
        ? TideBotThemeProvider.of(context)
        : (context.dependOnInheritedWidgetOfExactType<_TideThemeWidget>()?.theme ?? TideTheme());
  }
}

class _TideThemeWidget extends InheritedNotifier<TideTheme> {
  const _TideThemeWidget({required this.theme, required super.child}) : super(notifier: theme);
  final TideTheme theme;
}

class TideBotThemeProvider extends StatelessWidget {
  final TideTheme theme;
  final Widget child;
  const TideBotThemeProvider({Key? key, required this.theme, required this.child}) : super(key: key);
  static TideTheme of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<_TideThemeWidget>();
    return w?.theme ?? TideTheme();
  }
  @override Widget build(BuildContext context) => _TideThemeWidget(theme: theme, child: child);
}
