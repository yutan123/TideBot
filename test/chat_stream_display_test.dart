import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/chat_message_display.dart';
import 'package:tide_bot/chat_stream_pacing.dart';

Map<String, dynamic> body(String id, int time) => {
      'id': id,
      'role': 'assistant',
      'type': 'text',
      'content': '',
      'inner_thought': '想法',
      'reply_group_id': 'g',
      'timestamp': time,
      'is_streaming': true,
    };
Map<String, dynamic> thought() => {
      'id': 't',
      'role': 'assistant',
      'type': 'inner_thought',
      'content': '想法',
      'reply_group_id': 'g',
      'timestamp': 1,
    };

void main() {
  test('empty streamed body remains attached beside its thought', () {
    final message = body('m', 2);
    var rows = normalizeChatMessages([thought(), message]);
    expect(rows.map((row) => row['id']), ['t', 'm']);
    expect(identical(rows.last, message), isTrue);
    message['content'] = '正';
    rows = normalizeChatMessages([
      ...rows,
      {
        'id': 'u',
        'role': 'user',
        'type': 'text',
        'content': '继续',
        'timestamp': 3,
      }
    ]);
    message['content'] = '正文';
    expect(rows.singleWhere((row) => row['id'] == 'm')['content'], '正文');
    message.remove('is_streaming');
    rows = normalizeChatMessages(rows);
    expect(rows.map((row) => row['id']), ['t', 'm', 'u']);
    expect(rows.where((row) => row['type'] == 'inner_thought'), hasLength(1));
  });

  test('empty completed text is still omitted', () {
    final message = body('m', 2)..remove('is_streaming');
    expect(normalizeChatMessages([message]), isEmpty);
  });

  testWidgets('thought and segmented bodies update without reopening the chat',
      (tester) async {
    var rows = <Map<String, dynamic>>[thought()];
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (_, setState) {
        update = setState;
        return Column(children: [
          for (final row in rows) Text(row['content'].toString()),
        ]);
      },
    )));
    for (var index = 0; index < 2; index++) {
      final message = body('m$index', 2 + index);
      update(() => rows = normalizeChatMessages([...rows, message]));
      await tester.pump();
      final stream = chatStreamText(index == 0 ? '你好' : '再见', 100);
      final reveal = stream.forEach((content) {
        update(() => message['content'] = content);
      });
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text(index == 0 ? '你' : '再'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      await reveal;
      update(() {
        message.remove('is_streaming');
        rows = normalizeChatMessages(rows);
      });
      await tester.pump();
    }
    expect(find.text('想法'), findsOneWidget);
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('再见'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
