import 'dart:math';
import 'package:tide_bot/bot_vital_model.dart';

void main() {
  final random = Random(42);
  var updates = 0;
  for (final baseline in [45.0, 50.0, 60.0, 72.0, 95.0, 135.0]) {
    for (final start in [20.0, baseline, 160.0]) {
      var previous = start;
      final history = <int>[];
      final base = baseline.clamp(50, 135);
      for (var hour = 0; hour < 720; hour++) {
        final next = hourlyMeanHeartRate(
          previous: previous,
          baseline: baseline,
          asleep: hour % 24 < 8,
          activity: hour % 24 == 12 ? '跑步' : '休息',
          stress: hour % 11.0,
          sleepQuality: 60,
          temperature: 36.5,
          noise: random.nextDouble() * 6 - 3,
          random: random,
          recent: history.skip(max(0, history.length - 24)),
        );
        if (next < 40 || next > 135 || (next - base).abs() > 10) {
          throw StateError('Out of bounds: $baseline/$previous/$next');
        }
        if (next == previous.round()) throw StateError('Repeated hourly value');
        if (previous >= max(40, base - 10) &&
            previous <= min(135, base + 10) &&
            (next - previous).abs() > 6) throw StateError('Abrupt hourly jump');
        history.add(next);
        if (history.length >= 24 &&
            history.length % 24 == 0 &&
            history.sublist(history.length - 24).toSet().length < 6) {
          throw StateError('Insufficient daily spread');
        }
        previous = next.toDouble();
        updates++;
      }
    }
  }
  for (var seed = 0; seed < 100; seed++) {
    final next = hourlyMeanHeartRate(
        previous: 72,
        baseline: 72,
        asleep: false,
        activity: '休息',
        stress: 3,
        sleepQuality: 80,
        temperature: 36.5,
        noise: 0,
        random: Random(seed),
        recent: [70, 70, 70, 71, 71, 71]);
    if ([70, 71, 72].contains(next))
      throw StateError('Repetition suppression failed');
  }
  double average(
      {bool asleep = false,
      String activity = '休息',
      double stress = 3,
      double temperature = 36.5}) {
    var total = 0;
    for (var seed = 0; seed < 2000; seed++) {
      total += hourlyMeanHeartRate(
          previous: 72,
          baseline: 72,
          asleep: asleep,
          activity: activity,
          stress: stress,
          sleepQuality: 80,
          temperature: temperature,
          noise: 0,
          random: Random(seed));
    }
    return total / 2000;
  }

  final resting = average();
  if (average(asleep: true) >= resting ||
      average(activity: '跑步') <= resting ||
      average(stress: 9) <= resting ||
      average(temperature: 38.5) <= resting) {
    throw StateError(
        'Activity, sleep, stress and fever must affect the distribution');
  }
  print(
      'Heart-rate regression passed: $updates hourly updates, temporary dips below 50, '
      'baseline recovery, continuity, daily spread and repetition suppression.');
}
