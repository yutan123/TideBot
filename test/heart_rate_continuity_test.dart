import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_vital_model.dart';

void main() {
  int advance(
    double heart, {
    bool asleep = false,
    String activity = '休息',
    double stress = 3,
    double quality = 80,
    double temperature = 36.5,
    double noise = 0,
  }) =>
      hourlyMeanHeartRate(
        previous: heart,
        asleep: asleep,
        activity: activity,
        stress: stress,
        sleepQuality: quality,
        temperature: temperature,
        noise: noise,
      );

  test('resting heart rate continues from manual values across two days', () {
    for (final edited in [55, 95]) {
      var current = edited;
      for (var hour = 0; hour < 48; hour++) {
        current = advance(current.toDouble());
        expect(current, edited, reason: 'hour $hour after editing to $edited');
      }
    }
  });

  test('activity and sleep change the latest value instead of resetting it',
      () {
    var current = advance(55, activity: '跑步');
    expect(current, 57);
    current = advance(current.toDouble(), activity: '散步');
    expect(current, 58);
    current = advance(current.toDouble(), asleep: true);
    expect(current, 57);
  });

  test('stress, poor sleep and fever affect the current heart rate gradually',
      () {
    expect(advance(55, stress: 7), 56);
    expect(advance(55, quality: 50), 56);
    expect(advance(55, temperature: 38.5), 56);
    expect(
        advance(55,
            activity: '运动', stress: 10, quality: 40, temperature: 40, noise: 2),
        59);
  });

  test('hourly changes remain bounded during repeated simulation', () {
    for (final initial in [45, 55, 95, 135]) {
      var current = initial;
      for (var hour = 0; hour < 72; hour++) {
        final previous = current;
        current = advance(
          previous.toDouble(),
          asleep: hour % 24 < 8,
          activity: hour % 24 == 12 ? '运动' : '休息',
          stress: (hour % 11).toDouble(),
          noise: hour.isEven ? 2 : -2,
        );
        expect(current, inInclusiveRange(45, 135));
        expect((current - previous).abs(), lessThanOrEqualTo(4));
      }
    }
  });
}
