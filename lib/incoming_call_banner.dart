import 'package:flutter/material.dart';
import 'voice_call_state_service.dart';
import 'db.dart';
import 'ui_call.dart';
import 'theme.dart';

class IncomingCallBanner extends StatelessWidget {
  final String botId;

  const IncomingCallBanner({
    super.key,
    required this.botId,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VoiceCallStateService.instance,
      builder: (context, _) {
        final ringingCalls = VoiceCallStateService.instance.ringingCalls;
        final call = ringingCalls[botId];

        if (call == null) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: DBManager().getBotData(botId),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) {
              return const SizedBox.shrink();
            }

            final bot = snapshot.data!;
            final botName = bot['name'] as String? ?? '未知';
            final avatarUrl = bot['avatar_url'] as String?;

            return Container(
              color: TideTheme.of(context).surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Icon(Icons.person,
                            size: 24, color: TideTheme.of(context).textWeak)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          botName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: TideTheme.of(context).textStrong,
                            fontFamily: 'TideFont',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '来电通话',
                          style: TextStyle(
                            fontSize: 13,
                            color: TideTheme.of(context).textWeak,
                            fontFamily: 'TideFont',
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _rejectCall(context, call, bot),
                    style: TextButton.styleFrom(
                      backgroundColor: TideTheme.of(context).surfaceVariant,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '拒接',
                      style: TextStyle(
                        color: TideTheme.of(context).textStrong,
                        fontFamily: 'TideFont',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _acceptCall(context, call, bot),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TideTheme.of(context).primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '接听',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'TideFont',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _acceptCall(
      BuildContext context, ActiveCall call, Map<String, dynamic> bot) async {
    try {
      await DBManager().updateVoiceCallRecord(
        call.callId,
        status: 'active',
      );

      await DBManager().updateChatMessage(
        'card_${call.callId}',
        content: '[语音通话，通话中]',
        callStatus: 'active',
      );
      VoiceCallStateService.instance.accept(call.botId, call.callId);

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallPage(
              bot: bot,
              callId: call.callId,
              initiator: call.initiator,
              hasStt: bot['has_stt'] == 1,
              hasTts: bot['has_tts'] == 1,
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('接听通话失败：$error');
    }
  }

  Future<void> _rejectCall(
      BuildContext context, ActiveCall call, Map<String, dynamic> bot) async {
    try {
      await DBManager().updateVoiceCallRecord(
        call.callId,
        status: 'rejected',
      );

      await DBManager().updateChatMessage(
        'card_${call.callId}',
        content: '[语音通话，已拒接]',
        callStatus: 'rejected',
      );

      VoiceCallStateService.instance.reject(call.botId, call.callId);
    } catch (error) {
      debugPrint('拒接通话失败：$error');
    }
  }
}
