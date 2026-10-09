import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';
import 'life_schedule_service.dart';
import 'ops.dart';
import 'bot_state.dart';

class DiaryService {
  DiaryService._();
  static final DiaryService instance = DiaryService._();
  bool _running = false;

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Schedules daily diary catch-up at 00:00 using AlarmManager.
  Future<void> scheduleDailyAlarm() async {
    try {
      final now = DateTime.now();
      var nextRun = DateTime(now.year, now.month, now.day);
      if (now.isAfter(nextRun)) {
        nextRun = nextRun.add(const Duration(days: 1));
      }
      final success = await OpsManager().setSystemAlarm(
        nextRun.hour,
        nextRun.minute,
        'TideBot 日记补写',
        repeating: true,
      );
      if (success) {
        AppLogService.instance.add('DIARY', '已设置每日 00:00 日记补写闹钟');
      }
    } catch (error) {
      AppLogService.instance.add('DIARY', '设置日记闹钟失败：$error');
    }
  }

  Future<void> catchUp() async {
    if (_running) return;
    _running = true;
    try {
      final db = DBManager();
      final today = DateTime.now();
      final yesterday = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 1));
      final bots = await db.queryBots();
      for (final bot in bots) {
        final botId = bot['id']?.toString() ?? '';
        if (botId.isEmpty || isBotDisabled(bot['is_disabled'])) continue;
        final history = await db.getChatHistory(botId);
        final byDate = <String, List<Map<String, dynamic>>>{};
        for (final message in history) {
          final stamp = (message['timestamp'] as num?)?.toInt();
          if (stamp == null) continue;
          final key = _dateKey(DateTime.fromMillisecondsSinceEpoch(stamp));
          byDate.putIfAbsent(key, () => []).add(message);
        }
        for (var day = yesterday;
            !day.isBefore(yesterday.subtract(const Duration(days: 30)));
            day = day.subtract(const Duration(days: 1))) {
          final dateKey = _dateKey(day);
          final schedule = await db.getLifeSchedule(botId, dateKey);
          if ((!byDate.containsKey(dateKey) && schedule == null) ||
              await db.getDiary(botId, dateKey) != null) {
            continue;
          }
          final job = 'diary_${botId}_$dateKey';
          if (!await db.claimBackgroundJob(job)) continue;
          try {
            if (await db.getDiary(botId, dateKey) == null) {
              await _writeDiary(botId, dateKey, byDate[dateKey] ?? []);
            }
          } catch (error) {
            AppLogService.instance
                .add('DIARY', '$botId $dateKey 日记生成失败：$error');
          } finally {
            await db.releaseBackgroundJob(job);
          }
        }
      }
    } catch (error) {
      AppLogService.instance.add('DIARY', '补写日记失败：$error');
    } finally {
      _running = false;
    }
  }

  Future<String> _scheduleText(String botId, String dateKey) async {
    try {
      if (!await LifeScheduleService.instance.enabled()) return '当天未启用日程';
      final row = await DBManager().getLifeSchedule(botId, dateKey);
      return row == null
          ? '当天暂无已生成日程'
          : LifeScheduleService.instance.compactContext(row);
    } catch (_) {
      return '当天日程暂时不可用';
    }
  }

  Future<void> _writeDiary(
      String botId, String dateKey, List<Map<String, dynamic>> messages) async {
    final db = DBManager();
    final transcript = messages
        .where((m) => m['type'] == 'text' || m['type'] == 'audio')
        .map((m) {
          final stamp = (m['timestamp'] as num?)?.toInt();
          final timeStr = stamp != null
              ? DateTime.fromMillisecondsSinceEpoch(stamp)
                  .toIso8601String()
                  .substring(11, 16) // HH:mm
              : '';
          final role = m['role'] == 'assistant' ? '角色' : '用户';
          final content = m['content'] ?? '';
          return timeStr.isEmpty
              ? '$role：$content'
              : '[$timeStr] $role：$content';
        })
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
    if (transcript.isEmpty && await db.getLifeSchedule(botId, dateKey) == null)
      return;
    final previous = await db.queryDiaryRange(
      botId,
      _dateKey(DateTime.parse(dateKey).subtract(const Duration(days: 3))),
      dateKey,
    );
    final priorText =
        previous.map((d) => '${d['date_key']}：${d['content']}').join('\n');
    final dayStart = DateTime.parse(dateKey);
    final eventStart = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final eventEnd = eventStart.add(const Duration(days: 1));
    final generatedAt = DateTime.now();
    final scheduleText = await _scheduleText(botId, dateKey);
    final result = await AIManager().sendMessage(
      botId: botId,
      priority: false,
      text:
          '这是内部日记任务，不是与用户聊天。请以第一人称写一篇简洁、真实、不可编造的日记。不仅要记录与用户的对话内容，还要写自己的事情、感受、想法和经历。只根据事件时间范围内实际发生的内容提炼。日程是安排，不能仅凭日程把计划写成已完成；没有聊天时不得虚构用户参与。主题名称如xx日只供内部了解，不直接写进正文，要写有依据的具体经历和感受；不要问候用户、不要解释任务、不要使用 Markdown。\n日记日期：$dateKey\n当前本地时间：${generatedAt.toIso8601String()}\n事件时间范围：${eventStart.toIso8601String()} 至 ${eventEnd.toIso8601String()}\n当天日程：$scheduleText\n当天对话：\n$transcript\n\n最近三天日记：\n$priorText',
      persistResponse: false,
      includeChatHistory: false,
      enableAutoSummary: false,
      skipLifeState: true,
      allowTools: false,
    );
    final content = result['reply']?.toString().trim() ?? '';
    if (result['success'] == true && content.isNotEmpty) {
      await db.upsertDiary(botId: botId, dateKey: dateKey, content: content);
      AppLogService.instance.add('DIARY', '已补写 $botId $dateKey 日记');
    }
  }
}
