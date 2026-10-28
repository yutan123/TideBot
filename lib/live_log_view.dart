import 'package:flutter/material.dart';

import 'app_log_service.dart';
import 'log_text.dart';

/// Follow new output only while the reader remains at the end of the log.
class LiveLogView extends StatefulWidget {
  const LiveLogView({super.key, required this.color});

  final Color color;

  @override
  State<LiveLogView> createState() => _LiveLogViewState();
}

class _LiveLogViewState extends State<LiveLogView> {
  final _scroll = ScrollController();
  bool _followOutput = true;
  bool _followScheduled = false;

  @override
  void initState() {
    super.initState();
    AppLogService.instance.revision.addListener(_refresh);
    _scheduleFollow();
  }

  void _refresh() {
    setState(() {});
    if (_followOutput) _scheduleFollow();
  }

  void _scheduleFollow() {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted || !_followOutput || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.isScrollingNotifier.value) return;
      // Lazy variable-height rows may reveal more content after this layout.
      if (position.extentAfter > 1) {
        _scroll.jumpTo(position.maxScrollExtent);
        _scheduleFollow();
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // Cancel even an already queued follow as soon as a reader starts a drag.
      _followOutput = false;
    } else if (notification is ScrollEndNotification) {
      _followOutput = notification.metrics.extentAfter <= 1;
    }
    return false;
  }

  @override
  void dispose() {
    AppLogService.instance.revision.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = List<AppLogEntry>.of(AppLogService.instance.entries);
    if (logs.isEmpty) {
      return Center(
        child: Text('等待日志输出…',
            style: TextStyle(fontFamily: 'TideFont', color: widget.color)),
      );
    }
    final indices = <Key, int>{
      for (var i = 0; i < logs.length; i++) ObjectKey(logs[i]): i,
    };
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scroll,
        itemCount: logs.length,
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (_, i) {
          final log = logs[i];
          return Padding(
            key: ObjectKey(log),
            padding: const EdgeInsets.only(bottom: 6),
            child: LogText(
              '[${log.time.toIso8601String()}] ${log.level}  ${log.message}',
              fontSize: 11,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}
