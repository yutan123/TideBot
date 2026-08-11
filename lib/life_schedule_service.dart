import 'dart:convert';
import 'dart:math';

import 'ai.dart';
import 'db.dart';

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

  Future<Map<String, dynamic>?> ensureToday(String botId) async {
    if (!await enabled()) return null;
    final db = DBManager();
    final existing = await db.getLifeSchedule(botId, dateKey());
    if (existing != null) return Map<String, dynamic>.from(existing);
    return await generateToday(botId);
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
    final result = await AIManager().sendMessage(
      botId: botId,
      text: '''这是内部日程任务，不要和用户聊天。请只输出 JSON。
今天是 $key。为自己生成真实连续的拟人化生活状态。
主题：$theme；心情：$mood；穿搭风格：$outfitStyle；日程类型：$scheduleType。
输出格式：
{"theme":"...","mood":"...","outfit_style":"$outfitStyle","outfit":"详细完整的从头到脚穿搭、鞋袜、材质、配饰、发型与整体氛围","timeline":[{"time":"09:00","activity":"...","rigid":false}]}
时间线 3 到 5 条；刚性事项仅限上班、已预约、就医、重要工作等不可随意改变的事情。$extra''',
      persistResponse: false,
      includeChatHistory: true,
      enableAutoSummary: false,
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
                'activity': e['activity']?.toString().trim() ?? '',
                'rigid': e['rigid'] == true,
              })
          .where((e) =>
              (e['time']?.toString().isNotEmpty ?? false) &&
              (e['activity']?.toString().isNotEmpty ?? false))
          .take(5)
          .toList();
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
      return row;
    } catch (_) {
      return old;
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
    return '【今日生活状态】主题：${row['theme'] ?? ''}；心情：${row['mood'] ?? ''}；'
        '穿搭风格：${row['outfit_style'] ?? ''}；当前安排：$currentText。'
        '${rigid.isEmpty ? '' : '刚性事项：$rigid。'}'
        '仅当真实对话确有必要时才调用生活状态工具；不得删除或改写刚性事项。';
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
                'activity': e['activity']?.toString().trim() ?? '',
                'rigid': e['rigid'] == true,
              })
          .where((e) =>
              (e['time']?.toString().isNotEmpty ?? false) &&
              (e['activity']?.toString().isNotEmpty ?? false))
          .take(6)
          .toList();
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
    return row;
  }
}
