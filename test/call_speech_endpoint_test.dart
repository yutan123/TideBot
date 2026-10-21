import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/call_speech_endpoint.dart';

void main() {
  test('ends one second after speech despite background and a transient', () {
    final d = CallSpeechEndpoint();
    for (var t = 0; t <= 1000; t += 200) {
      d.add(-65, t);
    }
    for (var t = 1200; t <= 2400; t += 200) {
      d.add(-32, t);
    }
    expect(d.speechDetected, isTrue);
    for (var t = 2600; t <= 3400; t += 200) {
      d.add(t == 3000 ? -25 : -48, t);
    }
    expect(d.stopReason(3300), isNull);
    expect(d.stopReason(3400), 'speech_ended');
  });
  test('continuous quiet speech survives the former ten second cutoff', () {
    final d = CallSpeechEndpoint();
    for (var t = 0; t <= 15000; t += 200) {
      d.add(-50, t);
      expect(d.stopReason(t), isNull);
    }
    expect(d.speechDetected, isTrue);
  });
  test('short pauses resume; idle background does not submit', () {
    final d = CallSpeechEndpoint();
    for (var t = 0; t <= 20000; t += 200) {
      d.add(-65, t);
      expect(d.stopReason(t), isNull);
    }
    d.reset();
    d.add(-35, 0);
    d.add(-35, 200);
    d.add(-65, 400);
    expect(d.stopReason(900), isNull);
    d.add(-35, 1000);
    d.add(-35, 1200);
    expect(d.stopReason(1500), isNull);
  });
  test('missing callbacks and maximum duration have distinct reasons', () {
    final d = CallSpeechEndpoint();
    expect(d.stopReason(4900), isNull);
    expect(d.stopReason(5000), 'amplitude_unavailable');
    expect(d.stopReason(120000), 'maximum_duration');
    d.add(double.nan, 5000);
    expect(d.lastSampleMs, isNull);
  });
}
