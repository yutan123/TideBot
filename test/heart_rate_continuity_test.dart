import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_vital_model.dart';

void main() {
  int advance(
    double heart, {
    double baseline = 55,
    bool asleep = false,
    String activity = '休息',
    double stress = 3,
    double quality = 80,
    double temperature = 36.5,
    double noise = 0,
  }) =>
      hourlyMeanHeartRate(
        previous: heart,
        baseline: baseline,
        asleep: asleep,
        activity: activity,
        stress: stress,
        sleepQuality: quality,
        temperature: temperature,
        noise: noise,
      );

  test('manual baselines remain stable while hourly readings vary', () {
    for (final edited in [55, 95]) {
      var current = edited;
      final values = <int>{};
      for (var hour = 0; hour < 48; hour++) {
        final previous = current;
        current = advance(current.toDouble(), baseline: edited.toDouble());
        expect(current, inInclusiveRange(40, 135));
        expect((current - edited).abs(), lessThanOrEqualTo(10));
        expect(current, isNot(previous));
        values.add(current);
      }
      expect(values.length, greaterThan(3));
    }
  });
  test('sleep and activity retain hourly continuity', () {
    var current = 72;
    for (final activity in ['跑步', '散步', '睡觉', '休息']) {
      final previous = current;
      current = advance(current.toDouble(),
          baseline: 72, activity: activity, asleep: activity == '睡觉');
      expect((current - previous).abs(), lessThanOrEqualTo(6));
      expect(current, isNot(previous));
    }
  });
  test('hourly changes remain bounded during repeated simulation', () {
    for (final initial in [45, 55, 95, 135]) {
      var current = initial;
      for (var hour = 0; hour < 72; hour++) {
        final previous = current;
        current = advance(
          previous.toDouble(),
          baseline: initial.toDouble(),
          asleep: hour % 24 < 8,
          activity: hour % 24 == 12 ? '运动' : '休息',
          stress: (hour % 11).toDouble(),
          noise: hour.isEven ? 2 : -2,
        );
        expect(current, inInclusiveRange(40, 135));
        expect((current - initial.clamp(50, 135)).abs(), lessThanOrEqualTo(10));
      }
    }
  });
}
