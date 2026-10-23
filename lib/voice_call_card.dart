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
    final messageId = message['id']?.toString() ?? '';
    final callId = message['call_id']?.toString() ??
        (messageId.startsWith('card_') ? messageId.substring(5) : '');
    final status = message['call_status']?.toString() ?? 'ended';
    final duration =
        ((message['duration'] ?? message['call_duration']) as num?)?.toInt() ??
            0;
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
          maxWidth: MediaQuery.of(context).size.width * 0.62,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isUser ? theme.surface : theme.bubbleAi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.primary.withValues(alpha: .22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getStatusIcon(status),
                size: 16,
                color: status == 'ended' ? theme.primary : theme.textWeak,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getStatusText(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textStrong,
                      fontSize: 13,
                      fontFamily: 'TideFont',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (status == 'ended' && duration > 0)
                    Text(
                      '时长 ${_formatDuration(duration)}',
                      style: TextStyle(
                        color: theme.textWeak,
                        fontSize: 11,
                        fontFamily: 'TideFont',
                      ),
                    ),
                ],
              ),
            ),
            if (callId.isNotEmpty) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: theme.textWeak),
            ],
          ],
        ),
      ),
    );
  }
}
