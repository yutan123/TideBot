import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_launch_animation.dart';
import 'legal_pages.dart';
import 'main.dart' show TideMainScaffold;

/// Owns the launch sequence so preference loading never replaces a running splash.
class FirstLaunchFlow extends StatefulWidget {
  const FirstLaunchFlow({super.key, required this.onReady});
  final VoidCallback onReady;
  @override
  State<FirstLaunchFlow> createState() => _FirstLaunchFlowState();
}

class _FirstLaunchFlowState extends State<FirstLaunchFlow> {
  SharedPreferences? _prefs;
  Object? _error;
  bool _accepted = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _error = null;
        _accepted = prefs.getBool('legal_agreement_accepted') == true &&
            prefs.getBool('legal_age_confirmed') == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : TextButton(onPressed: _load, child: const Text('重新读取启动设置')),
        ),
      );
    }
    return DailyLaunchAnimation(
      force: !_accepted,
      child: _accepted
          ? _ReadyHome(onReady: widget.onReady)
          : LegalAgreementPage(
              requiredAcceptance: true,
              onAccepted: () => setState(() => _accepted = true),
            ),
    );
  }
}

class _ReadyHome extends StatefulWidget {
  const _ReadyHome({required this.onReady});
  final VoidCallback onReady;
  @override
  State<_ReadyHome> createState() => _ReadyHomeState();
}

class _ReadyHomeState extends State<_ReadyHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) => const TideMainScaffold();
}
