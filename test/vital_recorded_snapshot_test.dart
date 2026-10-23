import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_vital_model.dart';
import 'package:tide_bot/bot_data_page.dart';
import 'package:tide_bot/bot_vital_signs_service.dart';

void main() {
  test('data pages use latest recorded hour until the next record arrives', () {
    final two = DateTime(2026, 10, 24, 2);
    final three = DateTime(2026, 10, 24, 3);
    final state = <String, dynamic>{
      'stress': 5.2,
      'mood': 90,
      'heart': 80,
      'samples': [
        {'time': three.millisecondsSinceEpoch, 'stress': 5.2, 'heart': 80},
        {
          'time': two.millisecondsSinceEpoch,
          'stress': 4.4,
          'mood': 60,
          'heart': 66,
          'steps': 300,
          'weight': 55.2,
          'height': 165,
          'temperature': 36.4,
          'health': '健康',
          'recovery': 100,
          'activity': '睡觉'
        },
      ],
    };
    final view =
        recordedVitalSnapshot(state, now: two.add(const Duration(minutes: 8)));
    expect(view['stress'], 4.4);
    expect(view['mood'], 60);
    expect(view['heart'], 66);
    expect(view['steps'], 300);
    expect(view['weight'], 55.2);
    expect(view['temperature'], 36.4);
    expect(view['last_hour'], two.millisecondsSinceEpoch ~/ 3600000);
    expect(vitalList(view['samples']), hasLength(1));
    expect(metricValue(view, 2), '4.4 / 10');
    expect(metricNote(view, 2), contains('轻度压力'));
    expect(metricPoints(view, 2, days: 36500).last['value'], 4.4);
    expect(recordedVitalSnapshot(state, now: three)['stress'], 5.2);
    expect(state['stress'], 5.2);
    expect(vitalList(state['samples']), hasLength(2));
  });

  test('stress boundaries, legend and AI context agree', () {
    for (final pair in <num, String>{
      0: '放松',
      2.99: '放松',
      3: '轻度压力',
      4.99: '轻度压力',
      5: '中度压力',
      6.99: '中度压力',
      7: '重度压力',
      10: '重度压力'
    }.entries) {
      expect(stressLevel(pair.key), pair.value);
      final prompt =
          BotVitalSignsService.instance.context({'stress': pair.key});
      expect(prompt, contains(pair.value));
      for (final range in stressRanges.values) {
        expect(prompt, contains(range));
      }
    }
    expect(stressRanges.keys.map(stressTrendColor).toSet(), hasLength(4));
  });

  test('hourly heart rate fluctuates and sleep stays lower over many hours',
      () {
    List<int> simulate(bool asleep) {
      final random = Random(42);
      var previous = 72.0;
      return List.generate(120, (_) {
        final next = hourlyMeanHeartRate(
            previous: previous,
            baseline: 72,
            asleep: asleep,
            activity: '休息',
            stress: 3,
            sleepQuality: 80,
            temperature: 36.5,
            noise: random.nextDouble() * 6 - 3);
        expect(next, inInclusiveRange(45, 135));
        expect(next, isNot(previous.round()));
        expect((next - previous).abs(), lessThanOrEqualTo(6));
        previous = next.toDouble();
        return next;
      });
    }

    final awake = simulate(false), sleeping = simulate(true);
    expect(sleeping.reduce((a, b) => a + b),
        lessThan(awake.reduce((a, b) => a + b)));
    expect(sleeping.toSet().length, greaterThan(3));
  });
}
