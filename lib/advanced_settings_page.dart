import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log_service.dart';
import 'log_session_detail_page.dart';
import 'theme.dart';
import 'ui_components.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  bool _logging = AppLogService.instance.enabled;
  bool _haptics = false;
  Timer? _ticker;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _logging) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
  }

  Future<void> _load() async {
    await TideHaptics.load();
    final prefs = await SharedPreferences.getInstance();
    final enabled = AppLogService.instance.enabled;
    if (mounted) {
      setState(() {
        _logging = enabled;
        _haptics = prefs.getBool('tide_haptics_enabled') ?? true;
      });
    }
  }

  Future<void> _toggleLog(bool value) async {
    if (value) {
      await AppLogService.instance.setEnabled(true);
      if (mounted) setState(() => _logging = true);
      return;
    }
    if (AppLogService.instance.entries.isNotEmpty && mounted) {
      final save = await TideDialogs.show<bool>(
        context: context,
        builder: (ctx) => TideDialogSurface(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: TideDialogs.glassContent(context: ctx, children: [
            Text('关闭实时日志',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'TideFont',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: TideTheme.of(ctx).textStrong)),
            const SizedBox(height: 8),
            Text('是否保存本次日志到历史记录？',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'TideFont', color: TideTheme.of(ctx).textWeak)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: TideDialogs.glassButton('不保存',
                      onTap: () => Navigator.pop(ctx, false),
                      color: TideTheme.of(ctx).surfaceVariant,
                      textColor: TideTheme.of(ctx).textStrong)),
              const SizedBox(width: 10),
              Expanded(
                  child: TideDialogs.glassButton('保存',
                      onTap: () => Navigator.pop(ctx, true),
                      color: TideTheme.of(ctx).primary)),
            ]),
          ]),
        ),
      );
      if (save == true) await AppLogService.instance.saveCurrent();
    }
    await AppLogService.instance.setEnabled(false);
    if (mounted) setState(() => _logging = false);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final logs = AppLogService.instance.entries;
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('高级设置',
            style: TextStyle(
                fontFamily: 'TideFont',
                color: theme.textStrong,
                fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: theme.iconMuted),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          FrostCard(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('触感反馈',
                  style: TextStyle(
                      fontFamily: 'TideFont',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong)),
              const SizedBox(height: 4),
              Text('开启后，使用 TideBot 的按钮和卡片时会有轻微震动。',
                  style: TextStyle(
                      fontFamily: 'TideFont',
                      color: theme.textWeak,
                      fontSize: 13)),
              Switch.adaptive(
                value: _haptics,
                activeThumbColor: theme.primary,
                onChanged: (value) async {
                  await TideHaptics.setEnabled(value);
                  if (mounted) setState(() => _haptics = value);
                  if (value) TideHaptics.tap();
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // Logs must always remain the final advanced-settings section.
          FrostCard(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('开发日志',
                          style: TextStyle(
                              fontFamily: 'TideFont',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.textStrong)),
                      const SizedBox(height: 4),
                      Text('仅本次运行有效；退出或重启 App 后自动关闭。',
                          style: TextStyle(
                              fontFamily: 'TideFont',
                              color: theme.textWeak,
                              fontSize: 13)),
                    ])),
                Switch.adaptive(
                    value: _logging,
                    activeThumbColor: theme.primary,
                    onChanged: _toggleLog),
              ]),
              if (_logging) ...[
                const SizedBox(height: 12),
                Container(
                  height: 220,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: theme.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.border)),
                  child: logs.isEmpty
                      ? Center(
                          child: Text('等待日志输出…',
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: theme.textFaint)))
                      : ListView.builder(
                          controller: _scroll,
                          itemCount: logs.length,
                          itemBuilder: (_, i) {
                            final log = logs[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: SelectableText(
                                  '[${log.time.toIso8601String()}] ${log.level}  ${log.message}',
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: theme.textStrong)),
                            );
                          },
                        ),
                ),
              ],
              const SizedBox(height: 12),
              TideDialogs.glassButton('查看历史日志',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LogHistoryPage())),
                  color: theme.primary),
            ]),
          ),
        ],
      ),
    );
  }
}

class LogHistoryPage extends StatelessWidget {
  const LogHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('历史日志',
              style: TextStyle(
                  fontFamily: 'TideFont',
                  color: theme.textStrong,
                  fontWeight: FontWeight.w700))),
      body: FutureBuilder<List<AppLogSession>>(
        future: AppLogService.instance.history(),
        builder: (_, snapshot) {
          final logs = snapshot.data ?? const <AppLogSession>[];
          if (snapshot.connectionState != ConnectionState.done)
            return Center(
                child: CircularProgressIndicator(color: theme.primary));
          if (logs.isEmpty)
            return Center(
                child: Text('暂无已保存日志',
                    style: TextStyle(
                        fontFamily: 'TideFont', color: theme.textFaint)));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final session = logs[i];
              return FrostCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                      child: InkWell(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                LogSessionDetailPage(session: session))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${session.startedAt.toLocal()} · ${session.entries.length} 条${session.hasError ? ' · 含错误' : ''}',
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: session.hasError
                                      ? Colors.redAccent
                                      : theme.primary,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                              session.entries.isEmpty
                                  ? '空日志'
                                  : session.entries.first.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  color: theme.textStrong)),
                        ]),
                  )),
                  IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        await AppLogService.instance.deleteSession(session.id);
                        if (context.mounted)
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LogHistoryPage()));
                      }),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
