import 'assistant_output_guard.dart';
import 'dart:convert';
import 'dart:math';

import 'ai.dart';
import 'app_log_service.dart';
import 'chat_content.dart';
import 'db.dart';
import 'bot_state.dart';
import 'ops.dart';
import 'bot_vital_signs_service.dart';
import 'bot_vital_model.dart';

Map<String, dynamic>? parseLifeSchedulePayload(String raw) {
  var source = cleanChatContent(raw).trim();
  if (source.isEmpty) return null;
  for (var pass = 0; pass < 3; pass++) {
    final direct = _decodeLifeScheduleMap(source);
    if (direct != null) return direct;
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      return null;
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    if (decoded is! String || decoded.trim() == source) return null;
    source = cleanChatContent(decoded).trim();
  }
  return null;
}

Map<String, dynamic>? _decodeLifeScheduleMap(String source) {
  var quoted = false;
  var escaped = false;
  var depth = 0;
  var start = -1;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
    } else if (char == '{') {
      if (depth++ == 0) start = index;
    } else if (char == '}' && depth > 0 && --depth == 0 && start >= 0) {
      try {
        final decoded = jsonDecode(source.substring(start, index + 1));
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      start = -1;
    }
  }
  return null;
}

bool isLifeScheduleClockTime(String value) =>
    RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

String compactLifeScheduleContext(
  Map<String, dynamic> row, {
  DateTime? at,
}) {
  final timeline = decodeLifeScheduleTimeline(row);
  final now = at ?? DateTime.now();
  final nowText =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  Map<String, dynamic>? current;
  for (final item in timeline) {
    final start = item['time']?.toString() ?? '';
    final end = item['end_time']?.toString() ?? '';
    final overnight = end.startsWith('次日');
    if (start.isEmpty || end.isEmpty) continue;
    if (overnight) {
      if (nowText.compareTo(start) >= 0 ||
          nowText.compareTo(end.replaceAll('次日', '')) < 0) {
        current = item;
        break;
      }
    } else if (nowText.compareTo(start) >= 0 && nowText.compareTo(end) < 0) {
      current = item;
      break;
    }
  }
  final currentText = current == null
      ? '当前没有安排'
      : '${current['time']}-${current['end_time']} ${current['activity']}';
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
      '全天日程：$fullTimeline。主题名称仅供内部了解，不要把xx日直接写进聊天、动态或日记，应写具体活动、经历和感受。'
      '${rigid.isEmpty ? '' : '刚性事项：$rigid。'}'
      '今天的活动仅是角色生活状态，不得虚构成已经与用户共同经历；用户询问今天做了什么时，可基于日程自然说明。需要变更日程或穿搭时必须调用生活状态工具，不得仅在正文声称已修改，也不得删除或改写刚性事项。';
}

List<Map<String, dynamic>> decodeLifeScheduleTimeline(
    Map<String, dynamic> row) {
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

  /// Schedules daily schedule generation at the configured hour using AlarmManager.
  Future<void> scheduleDailyAlarm() async {
    try {
      final db = DBManager();
      final configured = int.tryParse(
            await db.getKV('life_schedule_generation_hour') ?? '',
          ) ??
          7;
      final hour = configured.clamp(0, 23);
      final now = DateTime.now();
      var nextRun = DateTime(now.year, now.month, now.day, hour, 0);
      if (now.isAfter(nextRun)) {
        nextRun = nextRun.add(const Duration(days: 1));
      }
      final success = await OpsManager().setSystemAlarm(
        nextRun.hour,
        nextRun.minute,
        'TideBot 日程生成',
        repeating: true,
      );
      if (success) {
        AppLogService.instance.add(
          'SCHEDULE',
          '已设置每日 ${hour.toString().padLeft(2, '0')}:00 日程生成闹钟',
        );
      }
    } catch (error) {
      AppLogService.instance.add('SCHEDULE', '设置日程闹钟失败：$error');
    }
  }

  final Map<String, Future<Map<String, dynamic>?>> _generationFlights = {};

  /// Returns today's schedule, generating it on first interaction when absent.
  Future<Map<String, dynamic>?> ensureToday(String botId) async {
    if (!await enabled()) return null;
    final key = dateKey();
    final existing = await DBManager().getLifeSchedule(botId, key);
    if (existing != null) {
      final timeline = decodeLifeScheduleTimeline(existing);
      final nights = timeline.where((e) => '${e['activity']}'.contains('睡'));
      final valid = timeline.every((e) => e['steps'] is num) &&
          nights.any((e) {
            final start = vitalTime(key, '${e['time']}');
            var end = vitalTime(key, '${e['end_time']}');
            if (start == null || end == null) return false;
            if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
            return end.difference(start).inMinutes >= 420 &&
                end.difference(start).inMinutes <= 540;
          });
      if (valid) {
        if (!await BotVitalSignsService.instance.hasSchedule(botId, key)) {
          await BotVitalSignsService.instance
              .applySchedule(botId, key, timeline);
        }
        return Map<String, dynamic>.from(existing);
      }
    }
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
    for (final bot in await DBManager().getAllBots()) {
      final botId = bot['id']?.toString().trim() ?? '';
      if (botId.isEmpty) continue;
      if (isBotDisabled(bot['is_disabled'])) continue;
      await ensureToday(botId);
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
      task: AIRequestTask.lifeSchedule,
      botId: botId,
      text: '''这是内部日程任务，不要和用户聊天。请只输出 JSON。
今天是 $key。当前本地时间：${DateTime.now().toIso8601String()}。为自己生成真实连续的拟人化生活状态。\n已有日程（保留刚性事项）：${jsonEncode(old)}
${BotVitalSignsService.instance.context(await BotVitalSignsService.instance.snapshot(botId))}
主题：$theme；心情：$mood；穿搭风格：$outfitStyle；日程类型：$scheduleType。
可用天气池：$weatherPool。你必须根据全天时间合理选择天气，并让相邻时段天气平缓变化；无需使用全部天气，禁止无理由的大幅跳变。

【重要】睡眠时间要求：
- 你自己决定今晚的入睡时间和明早的起床时间
- 睡眠时长建议在 7-9 小时区间，根据人设与状态在这个区间内决定
- 入睡时间和起床时间不固定，由你根据今天的安排和心情决定
- 在 timeline 中必须包含睡觉时段，格式如：{"time":"23:30","end_time":"次日07:00","activity":"睡觉","weather":"...","rigid":false}
- end_time 如果是第二天，必须加"次日"前缀

【重要】步数分配要求：
- 你需要为今天的每个时间段分配步数
- timeline 中每个时段都要有 steps 字段，表示该时段的步数
- 根据活动类型合理分配：睡觉0步、宅家200-500步、外出1000-3000步、运动3000-6000步
- 全天总步数建议在 5000-12000 区间

首次生成时请同时给出 body 对象，依据人设已有身高体重，缺失则生成适合角色且无需性别判断的稳定初始数据；字段 height(cm)、weight(kg)、heart(静息平均心率)、temperature；不要生成血压字段。
输出格式（首次 body 必填；已有身体数据时不要重新生成身高）：
{"body":{"height":170,"weight":60,"heart":70,"temperature":36.5},"theme":"...","mood":"...","outfit_style":"$outfitStyle","outfit":"详细完整的从头到脚穿搭、鞋袜、材质、配饰、发型与整体氛围","sleep_plan_start":"23:30","sleep_plan_end":"次日07:00","timeline":[{"time":"09:00","end_time":"10:30","activity":"...","weather":"晴","steps":800,"rigid":false}]}
从你决定的起床时间安排当天生活，直到下一次睡觉结束。不要使用固定的09:00或23:00。按任务实际耗时自由安排足够多的连续时段，短任务不要虚构为一小时，不能重叠，不能留出不合理的大空档；每条都必须提供晚于开始时间的 end_time。必须包含一条睡觉时段（从入睡到起床）。刚性事项仅限上班、已预约、就医、重要工作等不可随意改变的事情。$extra''',
      persistResponse: false,
      includeChatHistory: false,
      enableAutoSummary: false,
      skipLifeState: true,
      allowTools: false,
    );
    if (result['success'] != true) {
      AppLogService.instance.add(
        'SCHEDULE',
        '生成 $key 日程失败：${result['error'] ?? '模型请求失败'}',
      );
      return old;
    }
    final text = result['reply']?.toString() ?? '';
    final payload = parseLifeSchedulePayload(text);
    if (payload == null || payload['timeline'] is! List) {
      AppLogService.instance.add(
        'SCHEDULE',
        '生成 $key 日程的响应无法解析，未覆盖现有日程',
      );
      return old;
    }
    try {
      final timeline = (payload['timeline'] as List)
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => <String, dynamic>{
                'time': e['time']?.toString() ?? '',
                'end_time': e['end_time']?.toString() ?? '',
                'activity': e['activity']?.toString().trim() ?? '',
                'weather': e['weather']?.toString().trim() ?? '',
                'steps': vitalInt(e['steps']),
                'rigid': e['rigid'] == true,
              })
          .where((e) =>
              (e['time']?.toString().isNotEmpty ?? false) &&
              (e['activity']?.toString().isNotEmpty ?? false))
          .toList();
      _normalizeTimeline(timeline, all['weather'] ?? const <String>[]);
      if (old != null &&
          _timeline(old).where((e) => e['rigid'] == true).any((e) =>
              !timeline.any((n) =>
                  n['rigid'] == true &&
                  n['time'] == e['time'] &&
                  n['end_time'] == e['end_time'] &&
                  n['activity'] == e['activity']))) return old;
      final sleepEntries =
          timeline.where((e) => '${e['activity']}'.contains('睡')).toList();
      if (sleepEntries.isEmpty) return old;
      final selected = sleepEntries.last;
      final sleepStart = vitalTime(key, '${selected['time']}');
      var sleepEnd = vitalTime(key, '${selected['end_time']}');
      if (sleepStart == null || sleepEnd == null) return old;
      if (!sleepEnd.isAfter(sleepStart))
        sleepEnd = sleepEnd.add(const Duration(days: 1));
      if (sleepEnd.difference(sleepStart).inMinutes < 420 ||
          sleepEnd.difference(sleepStart).inMinutes > 540) return old;
      final outfit = payload['outfit']?.toString().trim() ?? '';
      if (timeline.length < 2 || outfit.isEmpty) {
        AppLogService.instance.add(
          'SCHEDULE',
          '生成 $key 日程校验失败：有效时间线不足或穿搭为空，未覆盖现有日程',
        );
        return old;
      }

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

      await BotVitalSignsService.instance.applySchedule(botId, key, timeline,
          initial: payload['body'] is Map
              ? Map<String, dynamic>.from(payload['body'])
              : null);
      AppLogService.instance.add('SCHEDULE', '已生成生活日程 $key');
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
    timeline.removeWhere((e) =>
        vitalTime('2026-01-01', '${e['time']}') == null ||
        vitalTime('2026-01-01', '${e['end_time']}') == null);
    timeline.sort((a, b) => vitalTime('2026-01-01', '${a['time']}')!
        .compareTo(vitalTime('2026-01-01', '${b['time']}')!));
    var previousWeather = weatherPool.isEmpty ? '' : weatherPool.first;
    for (final item in timeline) {
      final weather = '${item['weather'] ?? ''}';
      item['weather'] =
          allowedWeather.contains(weather) ? weather : previousWeather;
      previousWeather = '${item['weather']}';
      item['steps'] = '${item['activity']}'.contains('睡')
          ? 0
          : vitalInt(item['steps']).clamp(0, 30000);
    }
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
      if (await BotVitalSignsService.instance.isSleepPeriod(botId)) continue;
      if (isBotDisabled(bot['is_disabled'])) continue;
      final row = await db.getLifeSchedule(botId, key);
      if (botId.isEmpty || row == null) continue;
      final resumedAt =
          int.tryParse(await db.getKV('bot_resumed_at_$botId') ?? '') ?? 0;
      var attempted = false;
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
        final state = await db.getKV(eventKey);
        if (state == 'done' || state == 'running') continue;
        final clock = endTime.split(':');
        if (clock.length != 2) continue;
        final hour = int.tryParse(clock[0]);
        final minute = int.tryParse(clock[1]);
        if (hour == null ||
            minute == null ||
            hour < 0 ||
            hour > 23 ||
            minute < 0 ||
            minute > 59) continue;
        final end =
            DateTime(current.year, current.month, current.day, hour, minute);
        if (!isFreshLifeEndEvent(end, current, resumedAt: resumedAt) ||
            attempted) {
          await db.setKV(eventKey, 'done');
          continue;
        }
        if (!await db.claimBackgroundJob(eventKey,
            lease: const Duration(minutes: 10))) continue;
        attempted = true;
        await db.setKV(eventKey, 'running');
        try {
          final activity = item['activity']?.toString() ?? '';
          final result = await AIManager()
              .sendMessage(
                task: AIRequestTask.proactiveChat,
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
          await db.setKV(eventKey, 'done');
          AppLogService.instance.add('SCHEDULE', '日程结束事件失败：$e');
        }
      }
    }
  }

  String compactContext(Map<String, dynamic> row) =>
      compactLifeScheduleContext(row);

  List<Map<String, dynamic>> _timeline(Map<String, dynamic> row) =>
      decodeLifeScheduleTimeline(row);

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
                'steps': vitalInt(e['steps']),
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
    await BotVitalSignsService.instance
        .applySchedule(botId, dateKey(), _timeline(row));
    AppLogService.instance.add('SCHEDULE',
        '已通过工具更新拟人化日程 ${dateKey()}：${args['kind']?.toString() ?? 'timeline'}');
    return row;
  }
}
