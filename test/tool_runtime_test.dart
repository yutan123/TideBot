import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_state.dart';
import 'package:tide_bot/skill_runtime.dart';

void main() {
  group('isBotDisabled', () {
    test('accepts only explicit disabled values', () {
      expect(isBotDisabled(1), isTrue);
      expect(isBotDisabled(' true '), isTrue);
      expect(isBotDisabled(false), isFalse);
      expect(isBotDisabled(0), isFalse);
      expect(isBotDisabled('unavailable'), isFalse);
      expect(isBotDisabled(null), isFalse);
    });
  });

  group('TideSkillValidator', () {
    test('accepts a constrained HTTP skill', () {
      final result = TideSkillValidator.validate({
        'id': 'example.weather',
        'name': 'Weather',
        'version': '1.0.0',
        'tools': [
          {
            'name': 'forecast',
            'executor': 'http',
            'url': 'https://example.com/weather',
            'input_schema': {'type': 'object'},
          },
        ],
      });
      expect(result.isValid, isTrue);
    });

    test('rejects arbitrary executable definitions and duplicate tools', () {
      final result = TideSkillValidator.validate({
        'id': 'unsafe',
        'name': 'Unsafe',
        'version': '1',
        'tools': [
          {'name': 'run', 'executor': 'python'},
          {'name': 'run', 'executor': 'native'},
        ],
      });
      expect(result.isValid, isFalse);
      expect(result.error, contains('不支持执行器'));
    });
  });
}
