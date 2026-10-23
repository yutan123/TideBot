import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/assistant_output_guard.dart';

void main() {
  test('discards bracket tool imitations from proactive replies', () {
    expect(stripInternalToolPayloads('[tool_call choose_silence]'), '');
    expect(
        stripInternalToolPayloads(' \n[ TOOL_CALL  choose_silence ]\n '), '');
    expect(
        stripInternalToolPayloads(
            '[tool_call choose_silence][tool_call set_emotion]'),
        '');
  });
  test('keeps chat text around bracket tool imitations', () {
    expect(stripInternalToolPayloads('晚安。[tool_call choose_silence]'), '晚安。');
    expect(
        stripInternalToolPayloads(
            '[tool_call choose_silence]刚醒。{"name":"set_emotion"}'),
        '刚醒。');
  });
  test('preserves ordinary mentions and unrelated bracket text', () {
    const text = 'choose_silence 是工具名。[平静] [tool_calling choose_silence]';
    expect(stripInternalToolPayloads(text), text);
  });
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
