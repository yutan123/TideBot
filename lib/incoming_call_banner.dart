import 'package:flutter/material.dart';
import 'voice_call_state_service.dart';
import 'db.dart';
import 'ui_call.dart';
import 'ui_components.dart';
import 'theme.dart';

class IncomingCallBanner extends StatefulWidget {
  final String botId;

  const IncomingCallBanner({super.key, required this.botId});

  @override
  State<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<IncomingCallBanner> {
  bool _busy = false;
  late Future<Map<String, dynamic>?> _bot;

  @override
  void initState() {
    super.initState();
    _bot = DBManager().getBotData(widget.botId);
  }

  @override
  void didUpdateWidget(covariant IncomingCallBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.botId != widget.botId) {
      _bot = DBManager().getBotData(widget.botId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return AnimatedBuilder(
      animation: VoiceCallStateService.instance,
      builder: (context, _) {
        final call = VoiceCallStateService.instance.ringingCalls[widget.botId];
        if (call == null || call.bannerIgnored) {
          return const SizedBox.shrink();
        }
        return FutureBuilder<Map<String, dynamic>?>(
          future: _bot,
          builder: (context, snapshot) {
            final bot = snapshot.data;
            if (bot == null) return const SizedBox.shrink();
            final name = bot['name']?.toString() ?? 'TA';
            return Dismissible(
              key: ValueKey(call.callId),
              direction:
                  _busy ? DismissDirection.none : DismissDirection.horizontal,
              resizeDuration: null,
              onDismissed: (_) => VoiceCallStateService.instance
                  .ignoreBanner(call.botId, call.callId),
              child: TweenAnimationBuilder<double>(
                key: ValueKey('arrival_${call.callId}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -16 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: theme.primary.withValues(alpha: .20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: theme.isDark ? .28 : .12),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(28),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        theme.primary.withValues(alpha: .30)),
                              ),
                              child: TideBotAvatar(
                                name: name,
                                path: bot['avatar']?.toString(),
                                size: 42,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.textStrong,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'TideFont')),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.graphic_eq_rounded,
                                      size: 15, color: theme.primary),
                                  const SizedBox(width: 5),
                                  Flexible(
                                      child: Text('邀请你语音通话',
                                          style: TextStyle(
                                              color: theme.textWeak,
                                              fontSize: 12,
                                              fontFamily: 'TideFont'))),
                                ]),
                              ],
                            )),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: Text('左右滑动忽略',
                                    style: TextStyle(
                                        color: theme.textWeak,
                                        fontSize: 11,
                                        fontFamily: 'TideFont'))),
                            _action(theme,
                                label: '拒接',
                                icon: Icons.call_end_rounded,
                                accept: false,
                                onTap: () => _act(
                                    () => _rejectCall(context, call, bot))),
                            const SizedBox(width: 8),
                            _action(theme,
                                label: '接听',
                                icon: Icons.call_rounded,
                                accept: true,
                                onTap: () => _act(
                                    () => _acceptCall(context, call, bot))),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _action(TideTheme theme,
      {required String label,
      required IconData icon,
      required bool accept,
      required VoidCallback onTap}) {
    final foreground = accept ? Colors.white : const Color(0xFFE36773);
    return TextButton.icon(
      onPressed: _busy ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor:
            accept ? theme.primary : foreground.withValues(alpha: .10),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(
              fontFamily: 'TideFont', fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
