import 'package:flutter/material.dart';
import 'theme.dart';
import 'voice_call_detail_page.dart';

/// 语音通话卡片（显示在聊天记录中）
class VoiceCallCard extends StatelessWidget {
  final Map<String, dynamic> message;
  final String botName;

  const VoiceCallCard({
    super.key,
    required this.message,
    required this.botName,
  });

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return secs > 0 ? '$minutes分$secs秒' : '$minutes分';
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'ended':
        return '语音通话已结束';
      case 'rejected':
        return '语音通话已拒接';
      case 'timeout':
        return '语音通话已超时';
      default:
        return '语音通话';
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'ended':
        return Icons.call_end_rounded;
      case 'rejected':
        return Icons.call_missed_rounded;
      case 'timeout':
        return Icons.call_missed_outgoing_rounded;
      default:
        return Icons.call_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final callId = message['call_id']?.toString() ?? '';
    final status = message['call_status']?.toString() ?? 'ended';
    final duration = (message['call_duration'] as num?)?.toInt() ?? 0;
    final isUser = message['role'] == 'user';

    return GestureDetector(
      onTap: () {
        if (callId.isNotEmpty && status == 'ended') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VoiceCallDetailPage(
                callId: callId,
                botName: botName,
              ),
            ),
          );
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? theme.surface : theme.bubbleAi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? theme.primary.withValues(alpha: 0.2)
                : theme.textWeak.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(status),
                  size: 20,
                  color: status == 'ended' ? theme.primary : theme.textWeak,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(
                      color: theme.textStrong,
                      fontSize: 14,
                      fontFamily: 'TideFont',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (status == 'ended' && duration > 0) ...[
              const SizedBox(height: 8),
              Text(
                '通话时长 ${_formatDuration(duration)}',
                style: TextStyle(
                  color: theme.textWeak,
                  fontSize: 13,
                  fontFamily: 'TideFont',
                ),
              ),
            ],
            if (status == 'ended' && callId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 14,
                    color: theme.textWeak,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '点击查看详情',
                    style: TextStyle(
                      color: theme.textWeak,
                      fontSize: 12,
                      fontFamily: 'TideFont',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
