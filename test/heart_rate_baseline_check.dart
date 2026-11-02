import 'dart:math';
import 'package:tide_bot/bot_vital_model.dart';

void main() {
  final random = Random(42);
  final recovered = <int>{};
  for (final baseline in [45.0, 60.0, 80.0, 135.0]) {
    for (final start in [20.0, baseline - 10, baseline, baseline + 10, 160.0]) {
      var previous = start;
      for (var hour = 0; hour < 500; hour++) {
        final next = hourlyMeanHeartRate(
          previous: previous,
          baseline: baseline,
          asleep: hour.isEven,
          activity: hour % 3 == 0 ? '跑步运动' : '休息',
          stress: hour % 11.0,
          sleepQuality: 40,
          temperature: 39,
          noise: random.nextDouble() * 6 - 3,
          random: random,
        );
        if ((next - baseline.clamp(50, 135)).abs() > 10 ||
            next < 50 ||
            next > 135) {
          throw StateError('Out of bounds: $baseline/$previous/$next');
        }
        if (baseline == 60 && start == 160 && hour == 0) recovered.add(next);
        previous = next.toDouble();
      }
    }
  }
  for (var i = 0; i < 200; i++) {
    final next = hourlyMeanHeartRate(
        previous: 100,
        asleep: false,
        activity: '休息',
        stress: 3,
        sleepQuality: 80,
        temperature: 36.5,
        noise: 0,
        random: random);
    if (next < 50 || next > 70) throw StateError('Default is not 60');
    recovered.add(next);
  }
  if (recovered.length < 10) throw StateError('Recovery is not random');
  print('Heart-rate checks passed: default 60, custom baselines, '
      'upper/lower limits, random recovery and 10,000 hourly updates.');
}
