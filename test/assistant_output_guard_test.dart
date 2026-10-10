import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/assistant_output_guard.dart';

void main() {
  test('removes adjacent internal calls but preserves chat text', () {
    expect(
        stripInternalToolPayloads(
            '刚醒。{"name":"choose_silence"}{"name":"set_emotion","parameters":{"mood":"平静","reason":"含 { 括号"}}'),
        '刚醒。');
    expect(
        stripInternalToolPayloads('{"mood":"平静","intensity":22,"reason":"休息"}'),
        '');
  });
  test('preserves ordinary JSON and quoted braces', () {
    const text = '{"name":"Alice","data":{"text":"a } b"}}';
    expect(stripInternalToolPayloads(text), text);
    expect(stripInternalToolPayloads('解释 {不是 JSON}'), '解释 {不是 JSON}');
  });
  test('expired or pre-resume events are not replayed', () {
    final now = DateTime(2026, 10, 10, 16);
    expect(isFreshLifeEndEvent(now.subtract(const Duration(hours: 3)), now),
        false);
    expect(isFreshLifeEndEvent(now.subtract(const Duration(minutes: 5)), now),
        true);
    expect(
        isFreshLifeEndEvent(now.subtract(const Duration(minutes: 5)), now,
            resumedAt: now
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch),
        false);
    expect(
        isFreshLifeEndEvent(now.add(const Duration(minutes: 1)), now), false);
  });
}
