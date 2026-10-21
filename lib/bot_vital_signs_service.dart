import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ai.dart';
import 'app_log_service.dart';
import 'bot_state.dart';
import 'bot_vital_model.dart';
import 'db.dart';
import 'future_task_scheduler.dart';

class BotVitalSignsService {
  BotVitalSignsService._();
  static final instance = BotVitalSignsService._();
  final _rng = Random();
  final Map<String, String> _leaseTokens = {};
  final Map<String, Future<void>> _locks = {};
  final Map<String, int> _active = {};
  final Set<String> _replying = {};
  final revision = ValueNotifier(0);
  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<T> _serial<T>(String id, Future<T> Function() fn) async {
    final old = _locks[id] ?? Future<void>.value(), done = Completer<void>();
    _locks[id] = done.future;
    await old;
    final native = defaultTargetPlatform == TargetPlatform.android;
    final token =
        '${DateTime.now().microsecondsSinceEpoch}:${_rng.nextDouble()}';
    var acquired = false;
    final stopRenewal = Completer<void>();
    Future<void>? renewal;
    try {
      if (native) {
        final db = await DBManager().database;
        for (var attempt = 0; attempt < 100 && !acquired; attempt++) {
          acquired = await db.transaction((txn) async {
            final rows = await txn.query('kv_store',
                where: 'key = ?', whereArgs: ['vital_lock_$id']);
            Map<String, dynamic> lease = {};
            try {
              if (rows.isNotEmpty)
                lease = Map<String, dynamic>.from(
                    jsonDecode('${rows.first['value']}') as Map);
            } catch (_) {}
            final now = DateTime.now().millisecondsSinceEpoch;
            if (vitalInt(lease['until']) > now) return false;
            await txn.rawInsert(
                'INSERT OR REPLACE INTO kv_store(key,value) VALUES (?,?)', [
              'vital_lock_$id',
              jsonEncode({'token': token, 'until': now + 120000})
            ]);
            return true;
          });
          if (!acquired)
            await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!acquired) {
          throw StateError('生活状态正在更新，请稍后重试');
        }
        _leaseTokens[id] = token;
        renewal = () async {
          while (!stopRenewal.isCompleted) {
            await Future.any([
              stopRenewal.future,
              Future<void>.delayed(const Duration(seconds: 30)),
            ]);
            if (stopRenewal.isCompleted) return;
            try {
              final renewed = await db.transaction((txn) async {
                final rows = await txn.query('kv_store',
                    where: 'key = ?', whereArgs: ['vital_lock_$id']);
                if (rows.isEmpty) return false;
                final lease = jsonDecode('${rows.first['value']}') as Map;
                final now = DateTime.now().millisecondsSinceEpoch;
                if (lease['token'] != token ||
                    vitalInt(lease['until']) <= now) {
                  return false;
                }
                await txn.rawUpdate('UPDATE kv_store SET value=? WHERE key=?', [
                  jsonEncode({'token': token, 'until': now + 120000}),
                  'vital_lock_$id',
                ]);
                return true;
              });
              if (!renewed) return;
            } catch (error) {
              debugPrint('Vital lease renewal failed: $error');
              return;
            }
          }
        }();
      }
      return await fn();
    } finally {
      try {
        stopRenewal.complete();
        await renewal;
        if (native && acquired) {
          final db = await DBManager().database;
          await db.transaction((txn) async {
            final rows = await txn.query('kv_store',
                where: 'key = ?', whereArgs: ['vital_lock_$id']);
            if (rows.isNotEmpty &&
                (jsonDecode('${rows.first['value']}') as Map)['token'] ==
                    token) {
              await txn.delete('kv_store',
                  where: 'key = ?', whereArgs: ['vital_lock_$id']);
            }
          });
        }
      } finally {
        _leaseTokens.remove(id);
        done.complete();
        if (identical(_locks[id], done.future)) _locks.remove(id);
      }
    }
  }

  Future<Map<String, dynamic>> _read(String id) async {
    try {
      final v = jsonDecode(await DBManager().getKV('bot_vitals_v1_$id') ?? '');
      if (v is Map) {
        final state = Map<String, dynamic>.from(v)
          ..remove('systolic')
          ..remove('diastolic');
        state['samples'] = vitalList(state['samples'])
            .map((sample) => sample
              ..remove('systolic')
              ..remove('diastolic'))
            .toList();
        return state;
      }
    } catch (_) {}
    final bot = await DBManager().getBotById(id);
    final prompt = '${bot?['prompt'] ?? ''}';
    double? explicit(String units) =>
        double.tryParse(RegExp('(\\d+(?:\\.\\d+)?)\\s*(?:$units)')
                .firstMatch(prompt)
                ?.group(1) ??
            '');
    final height = explicit('cm|厘米') ?? (160 + _rng.nextInt(16)).toDouble();
    final weight = explicit('kg|公斤|千克') ??
        height * height / 10000 * (20 + _rng.nextDouble() * 3);
    return {
      'height': height,
      'weight': weight,
      'base_weight': weight,
      'temperature': 36.5,
      'heart': 72,
      'base_heart': 72,
      'mood': 65.0,
      'stress': 3.0,
      'energy': 75.0,
      'health': '健康',
      'illness': '',
      'recovery': 100.0,
      'last_hour': 0,
      'body_day': '',
      'samples': [],
      'sleep_history': [],
      'plans': [],
      'sleep_plans': [],
      'pending': [],
      'last_chat': 0
    };
  }

  Future<void> _save(String id, Map<String, dynamic> s) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final db = await DBManager().database;
      await db.transaction((txn) async {
        final rows = await txn
            .query('kv_store', where: 'key = ?', whereArgs: ['vital_lock_$id']);
        final lease = rows.isEmpty
            ? <String, dynamic>{}
            : jsonDecode('${rows.first['value']}') as Map;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (lease['token'] != _leaseTokens[id] ||
            vitalInt(lease['until']) <= now) {
          throw StateError('生活状态更新已过期，请重试');
        }
        await txn.rawInsert(
            'INSERT OR REPLACE INTO kv_store(key,value) VALUES (?,?)',
            ['bot_vitals_v1_$id', jsonEncode(s)]);
        await txn.rawInsert(
            'INSERT OR REPLACE INTO kv_store(key,value) VALUES (?,?)', [
          'vital_lock_$id',
          jsonEncode({'token': _leaseTokens[id], 'until': now + 120000})
        ]);
      });
    } else {
      await DBManager().setKV('bot_vitals_v1_$id', jsonEncode(s));
    }
    revision.value++;
  }

  Future<Map<String, dynamic>> snapshot(String id) async {
    await tick(id, replyPending: false);
    return _serial(id, () => _read(id));
  }

  bool sleeping(Map<String, dynamic> s) => s['sleep'] is Map;
  String moodName(num v) => v < 35
      ? '低落'
      : v < 50
          ? '疲惫'
          : v < 65
              ? '平静'
              : v < 82
                  ? '愉悦'
                  : '兴奋';
  Future<void> _alarm(String id, int t) async {
    if (t > DateTime.now().millisecondsSinceEpoch)
      await FutureTaskScheduler.schedule({
        'id': 'vital:$id:$t',
        'run_at': t,
        'title': 'TideBot 生活状态更新',
        'bot_id': id
      });
  }

  Future<bool> hasSchedule(String id, String date) => _serial(
      id,
      () async =>
          vitalList((await _read(id))['plans']).any((p) => p['day'] == date));

  Future<void> applySchedule(
          String id, String date, List<Map<String, dynamic>> timeline,
          {Map<String, dynamic>? initial}) =>
      _serial(id, () async {
        final s = await _read(id), plans = vitalList(s['plans']);
        plans.removeWhere((p) => p['day'] == date);
        plans.add({'day': date, 'blocks': stepPlan(date, timeline, _rng)});
        s['plans'] =
            plans.length > 35 ? plans.sublist(plans.length - 35) : plans;
        if (initial != null && s['initialized_by_model'] != true) {
          final ranges = {
            'height': [80.0, 240.0],
            'weight': [15.0, 250.0],
            'heart': [45.0, 100.0],
            'temperature': [36.0, 37.2]
          };
          for (final k in ranges.keys) {
            if (initial[k] is num)
              s[k] =
                  vitalDouble(initial[k]).clamp(ranges[k]![0], ranges[k]![1]);
          }
          s['base_weight'] = s['weight'];
          s['base_heart'] = s['heart'];
          s['initialized_by_model'] = true;
        }
        final entries =
            timeline.where((e) => '${e['activity']}'.contains('睡')).toList();
        if (entries.isNotEmpty) {
          final e = entries.last,
              start = vitalTime(date, '${entries.last['time']}');
          var end = vitalTime(date, '${e['end_time']}');
          if (start != null && end != null) {
            if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
            final duration = end.difference(start).inMinutes;
            final sleeps = vitalList(s['sleep_plans']);
            sleeps.removeWhere((p) => p['day'] == date && p['done'] != true);
            if (duration >= 420 &&
                duration <= 540 &&
                !sleeps.any((p) => p['day'] == date)) {
              sleeps.add({
                'day': date,
                'start': start.millisecondsSinceEpoch,
                'end': end.millisecondsSinceEpoch
              });
              s['sleep_plans'] = sleeps.length > 35
                  ? sleeps.sublist(sleeps.length - 35)
                  : sleeps;
              await _alarm(id, start.millisecondsSinceEpoch);
            }
          }
        }
        await _save(id, s);
      });
  Future<void> _pause(String id, int at) async {
    final db = DBManager(),
        due = vitalInt(await DBManager().getKV('proactive_due_at_$id'));
    await db.setKV('vital_pause_$id', '$at');
    await db.setKV('vital_remaining_$id', due > 0 ? '${max(0, due - at)}' : '');
  }

  Future<void> _resume(String id, int at) async {
    final db = DBManager();
    final stored = await db.getKV('vital_remaining_$id');
    await db.setKV('proactive_due_at_$id',
        stored == null || stored.isEmpty ? '' : '${at + vitalInt(stored)}');
    await db.setKV('vital_pause_$id', '');
  }

  Future<void> tick(String id, {DateTime? at, bool replyPending = true}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await const MethodChannel('tidebot.native.channel')
            .invokeMethod<String>('tickVitalSigns', {'botId': id});
        revision.value++;
      } on MissingPluginException {
        // Native Worker owns background advancement when this engine has no channel.
      } on PlatformException catch (error) {
        if (error.code != 'VITAL_BUSY') rethrow;
      }
      return;
    }
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    String? reason;
    await _serial(id, () async {
      final s = await _read(id), plans = vitalList(s['sleep_plans']);
      var sleep = s['sleep'] is Map
          ? Map<String, dynamic>.from(s['sleep'] as Map)
          : null;
      if (sleep == null) {
        for (final p in plans) {
          if (p['done'] == true || vitalInt(p['start']) > now) continue;
          if (vitalInt(p['end']) > now &&
              ((_active[id] ?? 0) > 0 ||
                  now - vitalInt(s['last_chat']) < 5 * 60000)) {
            final delay = max(vitalInt(p['start']), now) +
                30 * 60000 -
                vitalInt(p['start']);
            p['start'] = vitalInt(p['start']) + delay;
            p['end'] = vitalInt(p['end']) + delay;
            await _alarm(id, vitalInt(p['start']));
            break;
          }
          final start = vitalInt(p['start']), end = vitalInt(p['end']);
          p['done'] = true;
          if (start >= end) continue;
          final natural = <Map<String, dynamic>>[];
          final count = _rng.nextInt(3);
          // Separate windows prevent overlapping natural awakenings.
          for (var i = 0; i < count; i++) {
            final span = max(1, (end - start - 30 * 60000) ~/ max(1, count));
            final t = start +
                15 * 60000 +
                i * span +
                _rng.nextInt(max(1, span - 10 * 60000));
            natural.add({
              'start': t,
              'end': min(end, t + (5 + _rng.nextInt(6)) * 60000),
              'reason': '自然清醒',
              'processed': false
            });
          }
          sleep = {
            'day': p['day'],
            'start': start,
            'planned_end': end,
            'awake': [],
            'natural': natural
          };
          s['sleep'] = sleep;
          await _pause(id, start);
          await _alarm(id, end);
          for (final n in natural) {
            await _alarm(id, vitalInt(n['start']));
          }
          break;
        }
      }
      s['sleep_plans'] = plans;
      if (sleep != null) {
        final pending = vitalList(s['pending']);
        final history = await DBManager().getChatHistory(id);
        for (final message in history) {
          final timestamp = vitalInt(message['timestamp']);
          if (message['role'] == 'user' &&
              timestamp >= vitalInt(sleep['start']) &&
              timestamp < vitalInt(sleep['planned_end']) &&
              timestamp > vitalInt(s['answered_until']) &&
              !pending.any((p) => p['id'] == message['id'])) {
            pending.add({
              'id': message['id'],
              'time': timestamp,
              'type': message['type'],
              'content': message['content'],
              'file_path': message['file_path']
            });
          }
        }
        s['pending'] = pending;
        final awake = vitalList(sleep['awake']),
            natural = vitalList(sleep['natural']);
        for (final n in natural) {
          if (n['processed'] == true || vitalInt(n['start']) > now) continue;
          n['processed'] = true;
          awake.add(Map.of(n));
        }
        for (final n in natural) {
          if (n['reply_checked'] != true &&
              now >= vitalInt(n['start']) &&
              now < vitalInt(n['end']) &&
              now < vitalInt(sleep['planned_end']) &&
              replyPending) {
            n['reply_checked'] = true;
            reason = 'natural';
          }
        }
        sleep['natural'] = natural;
        sleep['awake'] = awake;
        if (now >= vitalInt(sleep['planned_end'])) {
          sleep['end'] = sleep['planned_end'];
          final settled = settleSleep(sleep);
          final history = vitalList(s['sleep_history'])..add(settled);
          s['sleep_history'] = history.length > 90
              ? history.sublist(history.length - 90)
              : history;
          s['sleep_quality'] = settled['quality'];
          s['energy'] = (40 + vitalInt(settled['quality']) * .55).clamp(0, 100);
          s.remove('sleep');
          reason = 'morning';
          await _resume(id, vitalInt(sleep['planned_end']));
        } else {
          s['sleep'] = sleep;
        }
      }
      final hour = now ~/ 3600000;
      var last = vitalInt(s['last_hour']);
      if (last == 0) last = hour - 1;
      last = max(last, hour - 720);
      final samples = vitalList(s['samples']);
      for (var h = last + 1; h <= hour; h++) {
        final t = h * 3600000,
            date = day(DateTime.fromMillisecondsSinceEpoch(h * 3600000));
        final nights = [
          ...vitalList(s['sleep_history']),
          if (s['sleep'] is Map) Map<String, dynamic>.from(s['sleep'] as Map)
        ];
        final inSleep = nights.any(
            (n) => t >= vitalInt(n['start']) && t < vitalInt(n['planned_end']));
        var steps = 0;
        String activity = '休息';
        for (final b
            in vitalList(s['plans']).expand((p) => vitalList(p['blocks']))) {
          final a = vitalInt(b['start']), z = vitalInt(b['end']);
          if (t >= a && t < z) activity = '${b['activity']}';
          final d = DateTime.parse(date).millisecondsSinceEpoch;
          if (z > a && a < t && z > d)
            steps += (vitalInt(b['steps']) *
                    (min(t, z) - max(a, d)).clamp(0, z - a) /
                    (z - a))
                .round();
        }
        final dateStart = DateTime.parse(date).millisecondsSinceEpoch;
        if (t == dateStart && samples.isNotEmpty) {
          final previousDate = day(DateTime.fromMillisecondsSinceEpoch(t - 1));
          final previousStart =
              DateTime.parse(previousDate).millisecondsSinceEpoch;
          var total = 0;
          for (final b
              in vitalList(s['plans']).expand((p) => vitalList(p['blocks']))) {
            final a = vitalInt(b['start']), z = vitalInt(b['end']);
            if (z > a && a < t && z > previousStart) {
              total += (vitalInt(b['steps']) *
                      (min(t, z) - max(a, previousStart)).clamp(0, z - a) /
                      (z - a))
                  .round();
            }
          }
          final previous = samples.lastWhere((e) => e['day'] == previousDate,
              orElse: () => <String, dynamic>{});
          if (previous.isNotEmpty) {
            samples.add({
              ...previous,
              'time': t - 1,
              'steps': total,
              'activity': '当日步数结算'
            });
          }
        }
        final quality = vitalDouble(s['sleep_quality'], 80);
        final working = RegExp('工作|上班|考试|学习').hasMatch(activity),
            relaxing = RegExp('散步|休息|读书|游戏|运动').hasMatch(activity);
        final target = (inSleep
                ? 2.0
                : working
                    ? 5.5
                    : relaxing
                        ? 2.0
                        : 3.0) +
            (quality < 60 ? 1.2 : 0) +
            (s['health'] == '生病' ? 1 : 0);
        final stress = (vitalDouble(s['stress'], 3) +
                (target - vitalDouble(s['stress'], 3)) * .16 +
                (_rng.nextDouble() - .5) * .5)
            .clamp(0, 10);
        final mood = (vitalDouble(s['mood'], 65) +
                (70 -
                        stress * 3 +
                        (quality - 80) * .1 -
                        vitalDouble(s['mood'], 65)) *
                    .15 +
                (_rng.nextDouble() - .5) * 4)
            .clamp(0, 100);
        s['stress'] = stress;
        s['mood'] = mood;
        if (s['health'] == '健康' && t >= vitalInt(s['cooldown'])) {
          if (_rng.nextDouble() <
              0.0005 +
                  (quality < 60 ? 0.0008 : 0) +
                  (stress > 7 ? 0.0005 : 0)) {
            s['health'] = '生病';
            s['illness'] = ['感冒', '轻微肠胃不适', '头痛'][_rng.nextInt(3)];
            s['ill_start'] = t;
            s['ill_until'] = t + (48 + _rng.nextInt(49)) * 3600000;
            s['recovery'] = 0.0;
          }
        } else if (s['health'] != '健康') {
          final a = vitalInt(s['ill_start']), z = vitalInt(s['ill_until']);
          final recovery =
              z > a ? ((t - a) / (z - a) * 100).clamp(0, 100) : 100.0;
          s['recovery'] = recovery;
          if (recovery >= 100) {
            s['health'] = '健康';
            s['illness'] = '';
            s['cooldown'] = t + 7 * 24 * 3600000;
          } else if (recovery >= 65) s['health'] = '康复中';
        }
        if (s['body_day'] != date) {
          s['weight'] = (vitalDouble(s['weight']) +
                  (_rng.nextDouble() - .5) * .25 +
                  (s['health'] == '生病' ? -.08 : 0) +
                  (steps > 8000 ? -.03 : 0))
              .clamp(15, 250);
          final sick = s['health'] == '生病';
          s['temperature'] = nextBodyTemperature(
            vitalDouble(s['temperature'], 36.5),
            sick: sick,
            noise: _rng.nextDouble() * 2 - 1,
          );
          s['body_day'] = date;
        }
        // One settled hourly mean; reopening the page never rerolls the value.
        s['heart'] = hourlyMeanHeartRate(
          previous: vitalDouble(s['heart'], 72),
          asleep: inSleep,
          activity: activity,
          stress: stress.toDouble(),
          sleepQuality: quality,
          temperature: vitalDouble(s['temperature'], 36.5),
          noise: _rng.nextDouble() * 4 - 2,
        );
        s['steps'] = max(0, steps);
        s['activity'] = activity;
        s['energy'] = (vitalDouble(s['energy']) +
                (inSleep ? 4 : -1.5) +
                (relaxing ? 1 : 0) -
                (stress > 7 ? 1 : 0))
            .clamp(0, 100);
        samples.add({
          'time': t,
          'day': date,
          'mood': mood,
          'stress': stress,
          'steps': s['steps'],
          'height': s['height'],
          'weight': s['weight'],
          'temperature': s['temperature'],
          'heart': s['heart'],
          'health': s['health'],
          'recovery': s['recovery'],
          'activity': activity
        });
      }
      s['last_hour'] = hour;
      s['samples'] = samples.length > 2160
          ? samples.sublist(samples.length - 2160)
          : samples;
      await _save(id, s);
      await _alarm(id, (hour + 1) * 3600000);
      if (reason == null &&
          !sleeping(s) &&
          vitalList(s['pending']).isNotEmpty &&
          now >= vitalInt(s['retry_at'])) reason = 'morning';
    });
    if (replyPending && reason != null) await _pendingReply(id, reason!);
  }

  Future<void> runDue() async {
    for (final bot in await DBManager().getAllBots()) {
      if (isBotDisabled(bot['is_disabled'])) continue;
      try {
        await tick('${bot['id']}');
      } catch (e) {
        AppLogService.instance.add('VITALS', '$e');
      }
    }
  }

  Future<bool> isSleepPeriod(String id) async {
    await tick(id, replyPending: false);
    return sleeping(await _serial(id, () => _read(id)));
  }

  Future<String> beforeRequest(String id) async {
    _active[id] = (_active[id] ?? 0) + 1;
    try {
      await tick(id, replyPending: false);
    } catch (_) {
      failedRequest(id);
      rethrow;
    }
    return _serial(id, () async {
      final s = await _read(id);
      if (sleeping(s)) {
        final history = await DBManager().getChatHistory(id),
            pending = vitalList(s['pending']);
        for (final m in history.where((m) =>
            m['role'] == 'user' &&
            vitalInt(m['timestamp']) >=
                vitalInt((s['sleep'] as Map)['start']) &&
            vitalInt(m['timestamp']) > vitalInt(s['answered_until']))) {
          if (!pending.any((p) => p['id'] == m['id']))
            pending.add({
              'id': m['id'],
              'time': m['timestamp'],
              'type': m['type'],
              'content': m['content'],
              'file_path': m['file_path']
            });
        }
        s['pending'] = pending;
        await _save(id, s);
      }
      return context(s);
    });
  }

  Future<void> afterRequest(
      String id, Map<String, dynamic> result, int cutoff) async {
    failedRequest(id);
    if (result['success'] != true) return;
    await _serial(id, () async {
      final s = await _read(id), now = DateTime.now().millisecondsSinceEpoch;
      if (result['silent'] != true &&
          '${result['reply'] ?? ''}'.trim().isNotEmpty) {
        if (sleeping(s)) {
          final sleep = Map<String, dynamic>.from(s['sleep'] as Map),
              awake = vitalList((s['sleep'] as Map)['awake']);
          awake.add({
            'start': now,
            'end': min(vitalInt(sleep['planned_end']),
                now + (5 + _rng.nextInt(16)) * 60000),
            'reason': '回复消息'
          });
          sleep['awake'] = awake;
          s['sleep'] = sleep;
        }
        s['pending'] = vitalList(s['pending'])
            .where((p) => vitalInt(p['time']) > cutoff)
            .toList();
        s['answered_until'] = cutoff;
        s['last_chat'] = now;
      }
      await _save(id, s);
    });
  }

  void failedRequest(String id) {
    _active[id] = max(0, (_active[id] ?? 1) - 1);
  }

  Future<void> updateBodyMetrics(String id,
      {required double height,
      required double weight,
      required double temperature,
      required int heart}) async {
    await _serial(id, () async {
      final s = await _read(id);
      s['height'] = height;
      s['weight'] = weight;
      s['temperature'] = temperature;
      s['heart'] = heart;
      s['base_heart'] = heart;
      s['base_weight'] = weight;
      // Manual values also prevent first-schedule initialization from replacing them.
      s['initialized_by_model'] = true;
      final samples = vitalList(s['samples']);
      if (samples.isNotEmpty) {
        samples.last.addAll({
          'height': height,
          'weight': weight,
          'temperature': temperature,
          'heart': heart,
        });
        s['samples'] = samples;
      }
      await _save(id, s);
    });
  }

  String context(Map<String, dynamic> s) {
    final samples = vitalList(s['samples']);
    final latestSample = samples.isEmpty ? null : samples.last;
    final mood = moodName(vitalDouble(s['mood']));
    final stress = vitalDouble(s['stress']).toStringAsFixed(1);
    final energy = vitalDouble(s['energy']).round();
    final health = s['health'] ?? '健康';
    final illness = s['illness'] ?? '';

    final sleepStatus = sleeping(s)
        ? sleepReplyGuidance(Map<String, dynamic>.from(s['sleep'] as Map),
            now: DateTime.now().millisecondsSinceEpoch)
        : '';

    final sleepHistory = vitalList(s['sleep_history']);
    final todaySleep = sleepHistory.isEmpty ? null : sleepHistory.last;
    final sleepInfo = todaySleep != null
        ? '今日睡眠：${(vitalInt(todaySleep['minutes']) / 60).toStringAsFixed(1)}小时，质量${todaySleep['quality']}/100；'
        : '今日尚未入睡；';

    final bodyInfo = latestSample != null
        ? '体温${vitalDouble(latestSample['temperature']).toStringAsFixed(1)}°C，平均心率${latestSample['heart']}次/分；'
        : '';

    final steps = s['steps'] ?? 0;
    final activity = s['activity'] ?? '休息';

    return '【你自己的生活状态】心情：$mood；压力 $stress/10；精力 $energy；健康：$health${illness.isNotEmpty ? " $illness" : ""}。$sleepInfo$bodyInfo今日步数$steps步，当前活动：$activity。这些是角色生活状态。$sleepStatus';
  }

  Future<void> _pendingReply(String id, String reason) async {
    if (_replying.contains(id) || (_active[id] ?? 0) > 0) return;
    _replying.add(id);
    try {
      final s = await _serial(id, () => _read(id));
      final pending = vitalList(s['pending']);
      if (pending.isEmpty) return;
      final natural = reason == 'natural';
      final images = pending
          .where((p) => p['type'] == 'image')
          .map((p) => '${p['file_path'] ?? ''}')
          .where((p) => p.isNotEmpty)
          .toList();
      final text = pending
          .map((p) =>
              '${DateTime.fromMillisecondsSinceEpoch(vitalInt(p['time']))} 对方：${p['content'] ?? ''}${p['type'] == 'image' ? ' [图片]' : ''}')
          .join('\n');
      final result = await AIManager().sendMessage(
          botId: id,
          text: text,
          imagePaths: images,
          persistResponse: true,
          notifyResponse: true,
          allowTools: natural,
          extraSystemPrompt: natural
              ? '你正在睡觉，刚刚短暂醒了，一会儿还要继续睡。前面对方发送的以下消息尚未回复。你自行决定是否现在回复：需要就直接回复，不需要就调用 choose_silence，不输出正文。'
              : '你刚刚在睡觉，现在已经起床。前面对方发送的以下消息还没有回复。请自然回复这些消息，结合上下文，不重复已回复内容。本次起床补回必须输出回复，不调用沉默工具。');
      if (result['success'] != true || result['silent'] == true)
        await _serial(id, () async {
          final state = await _read(id);
          state['retry_at'] = DateTime.now().millisecondsSinceEpoch + 5 * 60000;
          await _save(id, state);
        });
      // Pending messages are cleared by afterRequest only after an actual reply.
    } catch (e) {
      AppLogService.instance.add('VITALS', '睡眠补回失败：$e');
    } finally {
      _replying.remove(id);
    }
  }

  Future<void> observeMood(String id, String mood, int intensity) =>
      _serial(id, () async {
        final s = await _read(id);
        final target = {
              '开心': 80.0,
              '兴奋': 88.0,
              '平静': 65.0,
              '伤心': 30.0,
              '生气': 40.0,
              '害羞': 72.0
            }[mood] ??
            65;
        final influence = .1 + intensity.clamp(0, 10) / 10 * .3;
        s['mood'] =
            (vitalDouble(s['mood']) * (1 - influence) + target * influence)
                .clamp(0, 100);
        final stressTarget = mood == '生气' || mood == '伤心' ? 6.5 : 2.5;
        s['stress'] = (vitalDouble(s['stress'], 3) * (1 - influence) +
                stressTarget * influence)
            .clamp(0, 10);
        s['mood_note'] = mood;
        await _save(id, s);
      });
}
