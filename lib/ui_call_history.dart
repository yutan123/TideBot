import 'package:flutter/material.dart';

import 'db.dart';
import 'theme.dart';

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({super.key, required this.bot});

  final Map<String, dynamic> bot;

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  late Future<List<Map<String, dynamic>>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = DBManager().queryCallSessions(widget.bot['id'].toString());
  }

  String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return minutes > 0 ? '$minutes 分 $remainder 秒' : '$remainder 秒';
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
          title: Text('通话记录',
              style: TextStyle(
                  color: theme.onBackgroundStrong, fontFamily: 'TideFont')),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                  child: CircularProgressIndicator(color: theme.primary));
            }
            final sessions = snapshot.data ?? const <Map<String, dynamic>>[];
            if (sessions.isEmpty) {
              return Center(
                child: Text('暂无通话记录',
                    style: TextStyle(
                        color: theme.textWeak, fontFamily: 'TideFont')),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final session = sessions[index];
                final timestamp = (session['created_at'] as num?)?.toInt() ?? 0;
                final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
                final failed = session['status'] == 'failed';
                return Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    leading: Icon(
                      failed ? Icons.call_end_rounded : Icons.call_rounded,
                      color: failed ? Colors.red.shade400 : theme.primary,
                    ),
                    title: Text(
                      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: theme.textStrong, fontFamily: 'TideFont'),
                    ),
                    subtitle: Text(
                      _duration((session['duration'] as num?)?.toInt() ?? 0),
                      style: TextStyle(
                          color: theme.textWeak, fontFamily: 'TideFont'),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: theme.iconMuted),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CallHistoryDetailPage(session: session),
                    )),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class CallHistoryDetailPage extends StatelessWidget {
  const CallHistoryDetailPage({super.key, required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final sessionId = session['id'].toString();
    final summary = session['summary']?.toString().trim() ?? '';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('通话详情',
            style: TextStyle(
                color: theme.onBackgroundStrong, fontFamily: 'TideFont')),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DBManager().queryCallMessages(sessionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
                child: CircularProgressIndicator(color: theme.primary));
          }
          final messages = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: messages.length + (summary.isEmpty ? 0 : 1),
            itemBuilder: (context, index) {
              if (summary.isNotEmpty && index == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(summary,
                      style: TextStyle(
                          color: theme.textStrong,
                          fontFamily: 'TideFont',
                          height: 1.4)),
                );
              }
              final message = messages[index - (summary.isEmpty ? 0 : 1)];
              final isUser = message['role'] == 'user';
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .76),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: isUser ? theme.primary : theme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message['content']?.toString() ?? '',
                    style: TextStyle(
                        color: isUser ? Colors.white : theme.textStrong,
                        fontFamily: 'TideFont',
                        height: 1.35),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
