import 'global_notice.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'ai.dart';
import 'call_speech.dart';
import 'db.dart';
import 'ui_components.dart';
import 'theme.dart';

Future<void> showCallSpeechPreview(
    BuildContext context, String strength) async {
  final providers = await DBManager().queryTtsProviders();
  if (!context.mounted) return;
  if (providers.isEmpty) {
    GlobalNotice.show('请先在 API 设置中添加 TTS 提供商');
    return;
  }
  var provider = providers.first['id'].toString();
  var emotion = 'comforting';
  var busy = false;
  var alive = true;
  var status = '选择通话使用的音色服务，试听同一句话的不同语气。';
  final player = AudioPlayer();
  final token = AICancellationToken();
  try {
    await TideDialogs.show(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final theme = TideTheme.of(ctx);
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content:
              TideDialogs.glassContent(context: ctx, maxWidth: .9, children: [
            Text('通话情绪试听',
                style: TextStyle(
                    color: theme.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: provider,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'TTS 服务'),
              items: providers
                  .map((p) => DropdownMenuItem(
                      value: p['id'].toString(),
                      child: Text(p['name'].toString(),
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      if (v != null) update(() => provider = v);
                    },
            ),
            const SizedBox(height: 12),
            Wrap(
                spacing: 8,
                children: CallSpeechStyle.emotions.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value),
                          selected: emotion == e.key,
                          selectedColor: theme.primary.withValues(alpha: .2),
                          onSelected: busy
                              ? null
                              : (_) => update(() => emotion = e.key),
                        ))
                    .toList()),
            const SizedBox(height: 8),
            Text(
              callSpeechCapability(providers.firstWhere(
                (p) => p['id'].toString() == provider,
                orElse: () => providers.first,
              )),
              style: TextStyle(color: theme.textWeak, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Text('“我在这里，慢慢说，我听着呢。”', style: TextStyle(color: theme.textStrong)),
            const SizedBox(height: 8),
            Text(status, style: TextStyle(color: theme.textWeak, fontSize: 12)),
            const SizedBox(height: 16),
            TideDialogs.glassButton(busy ? '正在合成…' : '试听', onTap: () async {
              if (busy) return;
              update(() {
                busy = true;
                status = '正在生成语音…';
              });
              try {
                await player.stop();
                final path = await AIManager().generateTTS(
                  '我在这里，慢慢说，我听着呢。',
                  provider,
                  speechStyle: CallSpeechStyle(
                          emotion: emotion,
                          delivery:
                              emotion == 'comforting' ? 'gentle' : 'natural')
                      .moderated(strength: strength),
                  cancellationToken: token,
                );
                if (!alive || !ctx.mounted) return;
                if (path == null) {
                  update(() => status = '合成失败，请检查服务配置或更换模型');
                } else {
                  await player.play(DeviceFileSource(path));
                  if (alive && ctx.mounted)
                    update(() => status = '正在播放；实际情绪效果取决于所选模型的能力');
                }
              } on AICancelledException {
                // Closing the preview cancels the request.
              } catch (_) {
                if (alive && ctx.mounted) update(() => status = '试听失败，请检查音频服务');
              } finally {
                if (alive && ctx.mounted) update(() => busy = false);
              }
            }),
            const SizedBox(height: 8),
            TideDialogs.glassButton('关闭', onTap: () {
              alive = false;
              token.cancel();
              Navigator.pop(ctx);
            }),
          ]),
        );
      }),
    );
  } finally {
    alive = false;
    token.cancel();
    await player.dispose();
  }
}
