import 'package:flutter/material.dart';
import 'log_text.dart';
import 'app_log_service.dart';
import 'theme.dart';

class LogSessionDetailPage extends StatefulWidget {
  final AppLogSession session;
  const LogSessionDetailPage({super.key, required this.session});
  @override
  State<LogSessionDetailPage> createState() => _LogSessionDetailPageState();
}

class _LogSessionDetailPageState extends State<LogSessionDetailPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text('日志详情',
                style: TextStyle(
                    fontFamily: 'TideFont', color: theme.textStrong))),
        body: ListView.builder(
          key: PageStorageKey('log_session_${widget.session.id}'),
          controller: _scrollController,
          // Focusing selectable content must not reveal an entire tall row.
          physics: const HistoryLogScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: widget.session.entries.length,
          itemBuilder: (_, i) {
            final e = widget.session.entries[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LogText(
                '[${e.time.toLocal()}] ${e.level}\n${e.message}',
                color: e.level.toUpperCase().contains('ERROR')
                    ? Colors.redAccent
                    : theme.textStrong,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Preserve explicit gestures while rejecting selection focus reveal requests.
class HistoryLogScrollPhysics extends ScrollPhysics {
  const HistoryLogScrollPhysics({super.parent});
  @override
  bool get allowImplicitScrolling => false;
  @override
  HistoryLogScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      HistoryLogScrollPhysics(parent: buildParent(ancestor));
}
