import 'package:flutter/material.dart';
import 'db.dart';

// ================= 全局主题系统 =================
class TideTheme extends ChangeNotifier {
  String _name = 'purple';
  Color _primary = const Color(0xFF6B5B95);
  Color _primaryLight = const Color(0xFF9B8EC4);
  Color get primary => _primary;
  Color get primaryLight => _primaryLight;
  String get name => _name;
  LinearGradient get primaryGradient => LinearGradient(colors: [_primary, _primaryLight]);

  static const _themes = {
    'purple':   [Color(0xFF6B5B95), Color(0xFF9B8EC4)],
    'blue':     [Color(0xFF007AFF), Color(0xFF4DA3FF)],
    'red':      [Color(0xFFFF6B6B), Color(0xFFFFA5A5)],
    'green':    [Color(0xFF34C759), Color(0xFF5EE48B)],
    'greenGrad':[Color(0xFF20B868), Color(0xFF5EE48B)],
    'sunset':   [Color(0xFFFF6B6B), Color(0xFFFFA500)],
    'ocean':    [Color(0xFF00748A), Color(0xFF00B4D8)],
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
