import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';

class DiaryService {
  DiaryService._();
  static final DiaryService instance = DiaryService._();
  bool _running = false;

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
        if (botId.isEmpty) continue;
        final history = await db.getChatHistory(botId);
        final byDate = <String, List<Map<String, dynamic>>>{};
        for (final message in history) {
          final stamp = (message['timestamp'] as num?)?.toInt();
          if (stamp == null) continue;
          final key = _dateKey(DateTime.fromMillisecondsSinceEpoch(stamp));
          byDate.putIfAbsent(key, () => []).add(message);
        }
        for (var day = DateTime(yesterday.year, yesterday.month, yesterday.day);
            !day.isBefore(
                DateTime(yesterday.year, yesterday.month, yesterday.day)
                    .subtract(const Duration(days: 30)));
            day = day.subtract(const Duration(days: 1))) {
          final dateKey = _dateKey(day);
          if (!byDate.containsKey(dateKey) ||
              await db.getDiary(botId, dateKey) != null) continue;
          await _writeDiary(botId, dateKey, byDate[dateKey]!);
        }
      }
    } catch (error) {
      AppLogService.instance.add('DIARY', '补写日记失败：$error');
    } finally {
      _running = false;
    }
  }

  Future<void> _writeDiary(
      String botId, String dateKey, List<Map<String, dynamic>> messages) async {
    final db = DBManager();
    final transcript = messages
        .where((m) => m['type'] == 'text' || m['type'] == 'audio')
        .map((m) =>
            '${m['role'] == 'assistant' ? '机器人' : '用户'}：${m['content'] ?? ''}')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
    if (transcript.isEmpty) return;
    final previous = await db.queryDiaryRange(
      botId,
      _dateKey(DateTime.parse(dateKey).subtract(const Duration(days: 3))),
      dateKey,
    );
    final priorText =
        previous.map((d) => '${d['date_key']}：${d['content']}').join('\n');
    final response = await AIManager().sendMessage(
      botId: botId,
      text:
          '这是内部日记任务，不是与用户聊天。请以机器人第一人称写一篇简洁、真实、不可编造的日记。只根据当天对话提炼已经发生的事与感受；不要问候用户、不要解释任务、不要使用 Markdown。\n日期：$dateKey\n当天对话：\n$transcript\n\n最近三天日记：\n$priorText',
      persistResponse: false,
      includeChatHistory: false,
      enableAutoSummary: false,
      skipLifeState: true,
      allowTools: false,
    );
    final content = response['reply']?.toString().trim() ?? '';
    if (response['success'] == true && content.isNotEmpty) {
      await db.upsertDiary(botId: botId, dateKey: dateKey, content: content);
      AppLogService.instance.add('DIARY', '已补写 $botId $dateKey 日记');
    }
  }
}
