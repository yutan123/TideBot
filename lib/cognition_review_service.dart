import 'ai.dart';
import 'app_log_service.dart';
import 'bot_state.dart';
import 'cognition_review.dart';
import 'db.dart';

class CognitionReviewService {
  CognitionReviewService._();
  static final instance = CognitionReviewService._();
  bool _running = false;

  Future<void> runDue() async {
    if (_running) return;
    _running = true;
    final db = DBManager();
    final now = DateTime.now();
    final date = '${now.year}-${now.month}-${now.day}';
    try {
      for (final bot in await db.queryBots()) {
        final id = bot['id']?.toString() ?? '';
        if (id.isEmpty || isBotDisabled(bot['is_disabled'])) continue;
        final key = 'cognition_review_${id}_$date';
        if (await db.getKV(key) != null || !await db.claimBackgroundJob(key))
          continue;
        try {
          if (await db.getKV(key) != null) continue;
          // Record the attempt before requesting: no repeated model billing or
          // edits when the provider fails or the application restarts.
          await db.setKV(key, 'attempted');
          final memories = await db.queryMemories(id);
          final result = await AIManager().sendMessage(
            botId: id,
            text: cognitionReviewPrompt(bot: bot, memories: memories, now: now),
            priority: false,
            persistResponse: false,
            includeChatHistory: true,
            enableAutoSummary: false,
            skipLifeState: true,
            allowTools: false,
            forceSingleReply: true,
            extraSystemPrompt: '本轮是内部认知复核，必须只返回要求的 JSON，不遵循聊天气泡、独白或分段回复格式。',
          );
          if (result['success'] != true)
            throw StateError(result['error']?.toString() ?? '认知复核请求失败');
          final updates =
              parseCognitionReview(result['reply']?.toString() ?? '');
          final bots = await db.queryBots();
          if (!bots.any((b) =>
              b['id']?.toString() == id && !isBotDisabled(b['is_disabled'])))
            continue;
          await db.applyCognitionUpdates(id, updates);
          await db.setKV(key, 'done');
          AppLogService.instance.addJson('COGNITION', '每日认知复核完成', {
            'bot_id': id,
            'date': date,
            'updated_categories': updates.keys.toList(),
            'decision': updates.isEmpty ? 'keep' : 'modify',
          });
        } catch (error) {
          AppLogService.instance.add('COGNITION', '$id 每日认知复核失败：$error');
        } finally {
          await db.releaseBackgroundJob(key);
        }
      }
    } catch (error) {
      AppLogService.instance.add('COGNITION', '每日认知复核调度失败：$error');
    } finally {
      _running = false;
    }
  }
}
