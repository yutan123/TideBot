import 'dart:math';
import 'package:tide_bot/bot_vital_model.dart';

void main() {
  var dips = 0;
  var recoveries = 0;
  for (var seed = 0; seed < 1000; seed++) {
    final random = Random(seed);
    var previous = 50.0;
    int? lowSince;
    for (var hour = 0; hour < 168; hour++) {
      final elapsed = lowSince == null ? 0 : (hour - lowSince) * 3600000;
      final next = hourlyMeanHeartRate(
        previous: previous,
        baseline: 50,
        asleep: true,
        activity: '睡觉',
        stress: 0,
        sleepQuality: 80,
        temperature: 36.5,
        noise: -3,
        random: random,
        lowHeartDurationMs: elapsed,
      );
      if (next < 40 || next > 60) throw StateError('Invalid range: $next');
      if (previous < 50 && next < previous) {
        throw StateError('Heart rate kept falling: $previous -> $next');
      }
      if (lowSince != null && previous <= 50 && next < previous) {
        throw StateError('Recovery reversed at 50');
      }
      if (lowSince != null && hour - lowSince >= 3 && next <= 50) {
        throw StateError('Recovery missed the three-hour deadline');
      }
      if (next < 50 && lowSince == null) {
        lowSince = hour;
        dips++;
      } else if (next > 50 && lowSince != null) {
        lowSince = null;
        recoveries++;
      }
      previous = next.toDouble();
    }
    for (final start in [40.0, 45.0, 49.0, 50.0]) {
      final next = hourlyMeanHeartRate(
        previous: start,
        baseline: 50,
        asleep: true,
        activity: '睡觉',
        stress: 0,
        sleepQuality: 80,
        temperature: 36.5,
        noise: -3,
        random: random,
        lowHeartDurationMs: 10800000,
      );
      if (next <= 50) throw StateError('Deadline failed from $start');
    }
  }
  if (dips == 0 || recoveries == 0) throw StateError('No low-rate coverage');
  print('Passed 168,000 hourly samples: $dips dips, $recoveries recoveries; '
      'no further decreases and recovery above 50 within three hours.');
}
