import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';

/// 语音通话详情页面
class VoiceCallDetailPage extends StatefulWidget {
  final String callId;
  final String botName;

  const VoiceCallDetailPage({
    super.key,
    required this.callId,
    required this.botName,
  });

  @override
  State<VoiceCallDetailPage> createState() => _VoiceCallDetailPageState();
}

class _VoiceCallDetailPageState extends State<VoiceCallDetailPage> {
  Map<String, dynamic>? _record;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    try {
      final record = await DBManager().getVoiceCallRecord(widget.callId);
      if (mounted) {
        setState(() {
          _record = record;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return secs > 0 ? '$minutes分$secs秒' : '$minutes分';
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'ended':
        return '已结束';
      case 'rejected':
        return '已拒接';
      case 'timeout':
        return '超时未接';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.pageBackground,
        appBar: AppBar(
          backgroundColor: theme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.textStrong),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('通话详情',
              style: TextStyle(
                  color: theme.textStrong,
                  fontSize: 18,
                  fontFamily: 'TideFont',
                  fontWeight: FontWeight.w500)),
        ),
        body: Center(
          child: CircularProgressIndicator(color: theme.primary),
        ),
      );
    }

    if (_record == null) {
      return Scaffold(
        backgroundColor: theme.pageBackground,
        appBar: AppBar(
          backgroundColor: theme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.textStrong),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('通话详情',
              style: TextStyle(
                  color: theme.textStrong,
                  fontSize: 18,
                  fontFamily: 'TideFont',
                  fontWeight: FontWeight.w500)),
        ),
        body: Center(
          child: Text('通话记录不存在',
              style: TextStyle(color: theme.textWeak, fontFamily: 'TideFont')),
        ),
      );
    }

    final status = _record!['status']?.toString() ?? 'ended';
    final duration = (_record!['duration'] as num?)?.toInt() ?? 0;
    final summary = _record!['summary']?.toString() ?? '';
    final transcript = _record!['transcript']?.toString() ?? '';
    final timestamp = (_record!['timestamp'] as num?)?.toInt() ?? 0;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

    return Scaffold(
      backgroundColor: theme.pageBackground,
      appBar: AppBar(
        backgroundColor: theme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.textStrong),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('通话详情',
            style: TextStyle(
                color: theme.textStrong,
                fontSize: 18,
                fontFamily: 'TideFont',
                fontWeight: FontWeight.w500)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  status == 'ended'
                      ? Icons.call_end_rounded
                      : Icons.call_missed_rounded,
                  size: 48,
                  color: status == 'ended' ? theme.primary : theme.textWeak,
                ),
                const SizedBox(height: 12),
                Text(
                  _getStatusText(status),
                  style: TextStyle(
                    color: theme.textStrong,
                    fontSize: 20,
                    fontFamily: 'TideFont',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (status == 'ended') ...[
                  const SizedBox(height: 8),
                  Text(
                    '通话时长：${_formatDuration(duration)}',
                    style: TextStyle(
                      color: theme.textWeak,
                      fontSize: 14,
                      fontFamily: 'TideFont',
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: theme.textWeak,
                    fontSize: 12,
                    fontFamily: 'TideFont',
                  ),
                ),
              ],
            ),
          ),
          if (status == 'ended' && summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.summarize_rounded,
                          size: 20, color: theme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '通话摘要',
                        style: TextStyle(
                          color: theme.textStrong,
                          fontSize: 16,
                          fontFamily: 'TideFont',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    summary,
                    style: TextStyle(
                      color: theme.textStrong,
                      fontSize: 14,
                      fontFamily: 'TideFont',
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (status == 'ended' && transcript.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 20, color: theme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '通话原文',
                        style: TextStyle(
                          color: theme.textStrong,
                          fontSize: 16,
                          fontFamily: 'TideFont',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...transcript.split('\n').map((line) {
                    if (line.trim().isEmpty) return const SizedBox(height: 8);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: theme.textStrong,
                          fontSize: 14,
                          fontFamily: 'TideFont',
                          height: 1.5,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
