from pathlib import Path
r=Path('/data/data/com.ai.assistance.operit/files/workspace/TideBot')
p=r/'test/native_background_log_test.dart'; s=p.read_text(); pos=s.rfind('}')
s=s[:pos]+'''  test('keeps complete request context, original time and levels without polling noise', () async {
    SharedPreferences.setMockInitialValues({});
    await AppLogService.instance.setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => '''+"'''"+'''[
      {"time":1000,"message":"任务开始：vitals:bot"},
      {"time":2000,"message":"任务结束：status=success"},
      {"time":2500,"message":"主动回复已安排：bot=bot"},
      {"time":3000,"level":"PROACTIVE_REQUEST","message":"完整请求：system 人设，上下文 user 提问，tools choose_silence，Bearer secret123"},
      {"time":4000,"level":"PROACTIVE_NATIVE","message":"主动回复结束：sent"}
    ]'''+"'''"+''');
    await NativeBackgroundCoordinator.refreshLogs();
    final native = AppLogService.instance.entries
        .where((entry) => entry.level.startsWith('PROACTIVE')).toList();
    expect(native, hasLength(2));
    expect(native.first.level, 'PROACTIVE_REQUEST');
    expect(native.first.time.millisecondsSinceEpoch, 3000);
    expect(native.first.message, contains('system 人设，上下文 user 提问，tools choose_silence'));
    expect(native.first.message, isNot(contains('secret123')));
    expect(native.first.message, isNot(contains('[1970')));
    expect(native.last.time.millisecondsSinceEpoch, 4000);
  });
'''+s[pos:]; p.write_text(s)
p=r/'android/app/src/main/kotlin/com/yutan123/tidebot/TideRequestLeases.kt'; s=p.read_text().replace('''        if (deadlines.containsKey(id)) deadlines[id] = now() + 10 * 60_000L''','''        val time = now()
        if ((deadlines[id] ?: 0L) > time) deadlines[id] = time + 10 * 60_000L
        else deadlines.remove(id)'''); p.write_text(s)