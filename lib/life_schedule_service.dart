import 'dart:convert';
import 'dart:math';

import 'ai.dart';
import 'app_log_service.dart';
import 'db.dart';
import 'bot_state.dart';

class LifeScheduleService {
  LifeScheduleService._();
  static final instance = LifeScheduleService._();

  static const defaultPools = <String, List<String>>{
    'themes': [
      '探索日',
      '社交日',
      '宅家日',
      '工作日',
      '自我提升日',
      '休闲放松日',
      '创意日',
      '运动日',
      '整理日',
      '美食日',
      '文艺日',
      '随性漫游日'
    ],
    'moods': [
      '慵懒',
      '活力',
      '优雅',
      '俏皮',
      '神秘',
      '温柔',
      '冷艳',
      '甜美',
      '知性',
      '随性',
      '浪漫',
      '清新'
    ],
    'outfits': [
      '知性学院风',
      '街头休闲风',
      '温柔淑女风',
      '酷飒中性风',
      '慵懒居家风',
      '精致约会风',
      '运动活力风',
      '日系森女风',
      '法式优雅风',
      '韩系甜美风',
      '复古文艺风',
      '极简都市风',
      '甜酷混搭风',
      '民族风情风',
      '暗黑系风格'
    ],
    'types': [
      '户外活动型',
      '社交聚会型',
      '独处充电型',
      '技能学习型',
      '随性漫游型',
      '家务整理型',
      '工作专注型',
      '休闲娱乐型',
      '健身运动型',
      '美食探索型',
      '文化艺术型',
      '购物采买型'
    ],
    'weather': [
      '晴',
      '少云',
      '多云',
      '阴',
      '小雨',
      '中雨',
      '大雨',
      '雷阵雨',
      '雾',
    ],
  };

  String dateKey([DateTime? value]) {
    final d = value ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<bool> enabled() async =>
      (await DBManager().getKV('life_schedule_enabled')) != 'false';

  Future<Map<String, List<String>>> pools() async {
    final db = DBManager();
    final raw = await db.getKV('life_schedule_pools');
    try {
      final json = jsonDecode(raw ?? '');
      if (json is Map) {
        return defaultPools.map((key, fallback) {
          final rawList = json[key];
          final list = rawList is List
              ? rawList
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : List<String>.from(fallback);
          return MapEntry(
              key, list.isEmpty ? List<String>.from(fallback) : list);
        });
      }
    } catch (_) {}
    final copy = defaultPools.map((k, v) => MapEntry(k, List<String>.from(v)));
    await savePools(copy);
    return copy;
  }

  Future<void> savePools(Map<String, List<String>> value) async {
    await DBManager().setKV('life_schedule_pools', jsonEncode(value));
  }

  final Map<String, Future<Map<String, dynamic>?>> _generationFlights = {};

  /// Returns today's schedule, generating it on first interaction when absent.
  Future<Map<String, dynamic>?> ensureToday(String botId) async {
    if (!await enabled()) return null;
    final key = dateKey();
    final existing = await DBManager().getLifeSchedule(botId, key);
    if (existing != null) return Map<String, dynamic>.from(existing);
    final flightKey = '$botId:$key';
    final future = _generationFlights.putIfAbsent(
      flightKey,
      () => generateToday(botId),
    );
    try {
      final generated = await future;
      return generated == null ? null : Map<String, dynamic>.from(generated);
    } finally {
      if (identical(_generationFlights[flightKey], future)) {
        _generationFlights.remove(flightKey);
      }
    }
  }

  /// Generates missing schedules after the configured daily generation hour.
  /// The default preserves the historical 07:00 behavior.
  Future<void> generateDueSchedules({DateTime? now}) async {
    if (!await enabled()) return;
    final current = now ?? DateTime.now();
    final configured = int.tryParse(
          await DBManager().getKV('life_schedule_generation_hour') ?? '',
        ) ??
        7;
    if (current.hour < configured.clamp(0, 23)) return;
    final today = dateKey(current);
    for (final bot in await DBManager().getAllBots()) {
      final botId = bot['id']?.toString().trim() ?? '';
      if (botId.isEmpty) continue;
      if (await DBManager().getLifeSchedule(botId, today) == null) {
        await ensureToday(botId);
      }
    }
  }

  Future<Map<String, dynamic>?> generateToday(
    String botId, {
    String extra = '',
  }) async {
    if (!await enabled()) return null;
    final db = DBManager();
    final key = dateKey();
    final old = await db.getLifeSchedule(botId, key);
    final all = await pools();
    final random = Random();
    String choose(String type) {
      final items = all[type] ?? const <String>[];
      return items.isEmpty ? '' : items[random.nextInt(items.length)];
    }

    final theme = choose('themes');
    final mood = choose('moods');
    final outfitStyle = choose('outfits');
    final scheduleType = choose('types');
    final weatherPool = (all['weather'] ?? const <String>[]).join('、');
    final result = await AIManager().sendMessage(
      botId: botId,
      text: '''这是内部日程任务，不要和用户聊天。请只输出 JSON。
今天是 $key。为自己生成真实连续的拟人化生活状态。
主题：$theme；心情：$mood；穿搭风格：$outfitStyle；日程类型：$scheduleType。
可用天气池：$weatherPool。你必须根据全天时间合理选择天气，并让相邻时段天气平缓变化；无需使用全部天气，禁止无理由的大幅跳变。
输出格式：
{"theme":"...","mood":"...","outfit_style":"$outfitStyle","outfit":"详细完整的从头到脚穿搭、鞋袜、材质、配饰、发型与整体氛围","timeline":[{"time":"09:00","end_time":"10:30","activity":"...","weather":"晴","rigid":false}]}
只安排 09:00 至 23:00。按任务实际耗时自由安排足够多的连续时段，短任务不要虚构为一小时，不能重叠，不能留出不合理的大空档；每条都必须提供晚于开始时间的 end_time。固定追加一条 23:00 至次日09:00 的“睡觉”，weather 沿用夜间合理天气。刚性事项仅限上班、已预约、就医、重要工作等不可随意改变的事情。$extra''',
      persistResponse: false,
      includeChatHistory: false,
      enableAutoSummary: false,
      skipLifeState: true,
      allowTools: false,
    );
    if (result['success'] != true) return old;
    final text = result['reply']?.toString() ?? '';
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return old;
    try {
      final payload = jsonDecode(text.substring(start, end + 1));
      if (payload is! Map || payload['timeline'] is! List) return old;
      final timeline = (payload['timeline'] as List)
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => <String, dynamic>{
                'time': e['time']?.toString() ?? '',
                'end_time': e['end_time']?.toString() ?? '',
                'activity': e['activity']?.toString().trim() ?? '',
                'weather': e['weather']?.toString().trim() ?? '',
                'rigid': e['rigid'] == true,
              })
          .where((e) =>
              (e['time']?.toString().isNotEmpty ?? false) &&
              (e['activity']?.toString().isNotEmpty ?? false))
          .toList();
      _normalizeTimeline(timeline, all['weather'] ?? const <String>[]);
      final outfit = payload['outfit']?.toString().trim() ?? '';
      if (timeline.length < 2 || outfit.isEmpty) return old;
      final now = DateTime.now().millisecondsSinceEpoch;
      final row = <String, dynamic>{
        'id': old?['id'] ?? 'life_${botId}_$key',
        'bot_id': botId,
        'date_key': key,
        'theme': payload['theme']?.toString().trim().isNotEmpty == true
            ? payload['theme'].toString().trim()
            : theme,
        'mood': payload['mood']?.toString().trim().isNotEmpty == true
            ? payload['mood'].toString().trim()
            : mood,
        'outfit_style': outfitStyle,
        'outfit': outfit,
        'timeline_json': jsonEncode(timeline),
        'generated_at': old?['generated_at'] ?? now,
        'updated_at': now,
      };
      await db.upsertLifeSchedule(row);
      AppLogService.instance.add('SCHEDULE',
          '已生成拟人化日程 $key：主题=${row['theme']}，心情=${row['mood']}，时间线${timeline.length}条');
      return row;
    } catch (_) {
      return old;
    }
  }

  void _normalizeTimeline(
    List<Map<String, dynamic>> timeline,
    List<String> weatherPool,
  ) {
    final allowedWeather = weatherPool.toSet();
    timeline.removeWhere((item) {
      final start = item['time']?.toString() ?? '';
      return !_isTime(start) ||
          start.compareTo('09:00') < 0 ||
          start.compareTo('23:00') >= 0;
    });
    timeline.sort((a, b) =>
        (a['time']?.toString() ?? '').compareTo(b['time']?.toString() ?? ''));
    var previousEnd = '09:00';
    var previousWeather = weatherPool.isEmpty ? '' : weatherPool.first;
    for (final item in timeline) {
      var start = item['time']?.toString() ?? previousEnd;
      if (start.compareTo(previousEnd) < 0) start = previousEnd;
      var end = item['end_time']?.toString() ?? '';
      if (!_isTime(end) || end.compareTo(start) <= 0) {
        end = _plusMinutes(start, 30);
      }
      if (end.compareTo('23:00') > 0) end = '23:00';
      item['time'] = start;
      item['end_time'] = end;
      final weather = item['weather']?.toString().trim() ?? '';
      item['weather'] =
          allowedWeather.contains(weather) ? weather : previousWeather;
      previousWeather = item['weather'].toString();
      previousEnd = end;
    }
    if (previousEnd.compareTo('23:00') < 0) {
      timeline.add({
        'time': previousEnd,
        'end_time': '23:00',
        'activity': '放松、整理并准备休息',
        'weather': previousWeather,
        'rigid': false,
      });
    }
    timeline.add({
      'time': '23:00',
      'end_time': '次日09:00',
      'activity': '睡觉',
      'weather': previousWeather,
      'rigid': false,
    });
  }

  bool _isTime(String value) =>
      RegExp(r'^([01]\\d|2[0-3]):[0-5]\\d$').hasMatch(value);

  String _plusMinutes(String value, int minutes) {
    final parts = value.split(':').map(int.parse).toList();
    final total = (parts[0] * 60 + parts[1] + minutes).clamp(0, 23 * 60);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  Future<void> runDueEndEvents({DateTime? now}) async {
    if (!await enabled()) return;
    final db = DBManager();
    if (await db.getKV('proactive_reply') == 'false') return;
    final current = now ?? DateTime.now();
    final key = dateKey(current);
    final nowText =
        '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}';
    for (final bot in await db.getAllBots()) {
      final botId = bot['id']?.toString() ?? '';
      if (isBotDisabled(bot['is_disabled'])) continue;
      final row = await db.getLifeSchedule(botId, key);
      if (botId.isEmpty || row == null) continue;
      final timeline = _timeline(row);
      for (var index = 0; index < timeline.length; index++) {
        final item = timeline[index];
        final explicitEnd = item['end_time']?.toString() ?? '';
        final inferredEnd = index + 1 < timeline.length
            ? timeline[index + 1]['time']?.toString() ?? ''
            : '';
        final endTime = explicitEnd.isNotEmpty ? explicitEnd : inferredEnd;
        if (endTime.startsWith('次日') ||
            endTime.isEmpty ||
            endTime.compareTo(nowText) > 0) {
          continue;
        }
        final eventKey = 'life_end_${botId}_${key}_$index';
        if (await db.getKV(eventKey) == 'done') continue;
        await db.setKV(eventKey, 'running');
        try {
          final activity = item['activity']?.toString() ?? '';
          final result = await AIManager()
              .sendMessage(
                botId: botId,
                text:
                    '【日程结束事件】你今天从 ${item['time']} 到 $endTime 的“$activity”刚刚结束。根据人格、当前心情和最近聊天，自然决定是否想告诉用户；没有分享欲或会打扰时必须保持沉默。若发送，仅发 1-3 句自然短消息，不要提及日程、系统或指令。',
                persistResponse: true,
                notifyResponse: true,
              )
              .timeout(const Duration(minutes: 5));
          if (result['success'] != true) {
            throw StateError(result['error']?.toString() ?? '日程结束回复失败');
          }
          await db.setKV(eventKey, 'done');
        } catch (e) {
          await db.setKV(eventKey, 'pending');
          AppLogService.instance.add('SCHEDULE', '日程结束事件失败：$e');
        }
      }
    }
  }

  String compactContext(Map<String, dynamic> row) {
    final timeline = _timeline(row);
    final now = DateTime.now();
    final nowText =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    Map<String, dynamic>? current;
    for (final item in timeline) {
      if ((item['time']?.toString() ?? '').compareTo(nowText) <= 0) {
        current = item;
      }
    }
    final currentText = current == null
        ? '暂未开始安排'
        : '${current['time']} ${current['activity']}';
    final rigid = timeline
        .where((e) => e['rigid'] == true)
        .map((e) => '${e['time']} ${e['activity']}')
        .join('；');
    final fullTimeline = timeline.map((e) {
      final end = e['end_time']?.toString() ?? '';
      final weather = e['weather']?.toString().trim() ?? '';
      final rigidMark = e['rigid'] == true ? '（刚性）' : '';
      return '${e['time']}-${end.isEmpty ? '?' : end} ${e['activity']}${weather.isEmpty ? '' : '，$weather'}$rigidMark';
    }).join('；');
    return '【今日生活状态与完整日程】主题：${row['theme'] ?? ''}；心情：${row['mood'] ?? ''}；'
        '穿搭风格：${row['outfit_style'] ?? ''}；完整穿搭：${row['outfit'] ?? ''}；当前安排：$currentText。'
        '全天日程：$fullTimeline。'
        '${rigid.isEmpty ? '' : '刚性事项：$rigid。'}'
        '今天的活动仅是角色生活状态，不得虚构成已经与用户共同经历；用户询问今天做了什么时，可基于日程自然说明。需要变更日程或穿搭时必须调用生活状态工具，不得仅在正文声称已修改，也不得删除或改写刚性事项。';
  }

  List<Map<String, dynamic>> _timeline(Map<String, dynamic> row) {
    try {
      final raw = jsonDecode(row['timeline_json']?.toString() ?? '[]');
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> updateFromTool(
      String botId, Map<String, dynamic> args) async {
    final db = DBManager();
    final row = await db.getLifeSchedule(botId, dateKey());
    if (row == null) return null;
    if (args['kind']?.toString() == 'outfit') {
      final outfit = args['outfit']?.toString().trim() ?? '';
      if (outfit.isEmpty) return null;
      row['outfit'] = outfit;
    } else {
      final raw = args['timeline'];
      if (raw is! List) return null;
      final timeline = raw
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => <String, dynamic>{
                'time': e['time']?.toString() ?? '',
                'end_time': e['end_time']?.toString() ?? '',
                'activity': e['activity']?.toString().trim() ?? '',
                'weather': e['weather']?.toString().trim() ?? '',
                'rigid': e['rigid'] == true,
              })
          .where((e) =>
              (e['time']?.toString().isNotEmpty ?? false) &&
              (e['activity']?.toString().isNotEmpty ?? false))
          .toList();
      _normalizeTimeline(
          timeline, (await pools())['weather'] ?? const <String>[]);
      if (timeline.length < 2) return null;
      final existingRigid = _timeline(row).where((e) => e['rigid'] == true);
      for (final fixed in existingRigid) {
        final preserved = timeline.any((e) =>
            e['time'] == fixed['time'] &&
            e['activity'] == fixed['activity'] &&
            e['rigid'] == true);
        if (!preserved) return null;
      }
      row['timeline_json'] = jsonEncode(timeline);
    }
    final mood = args['mood']?.toString().trim() ?? '';
    if (mood.isNotEmpty) row['mood'] = mood;
    row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await db.upsertLifeSchedule(row);
    AppLogService.instance.add('SCHEDULE',
        '已通过工具更新拟人化日程 ${dateKey()}：${args['kind']?.toString() ?? 'timeline'}');
    return row;
  }
}
