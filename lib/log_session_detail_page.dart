import 'package:flutter/material.dart';
import 'app_log_service.dart';
import 'theme.dart';

class LogSessionDetailPage extends StatelessWidget {
  final AppLogSession session;
  const LogSessionDetailPage({super.key, required this.session});
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('日志详情',
              style:
                  TextStyle(fontFamily: 'TideFont', color: theme.textStrong))),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: session.entries.length,
        itemBuilder: (_, i) {
          final e = session.entries[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
                '[${e.time.toLocal()}] ${e.level}\n${e.message}',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: e.level.toUpperCase().contains('ERROR')
                        ? Colors.redAccent
                        : theme.textStrong)),
          );
        },
      ),
    );
  }
}
