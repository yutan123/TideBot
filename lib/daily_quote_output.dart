/// Return exactly one quote, including for old multi-item cached responses.
String singleDailyQuote(String raw) {
  var text = raw
      .replaceAll(
          RegExp(
              r'<(?:think|thinking|inner_thought)>[\s\S]*?</(?:think|thinking|inner_thought)>',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'```[^\n]*\n?|```'), '')
      .trim();
  final lines = text.split(RegExp(r'[\r\n]+|\|\|\|'));
  for (var line in lines) {
    line = line
        .trim()
        .replaceFirst(RegExp(r'^今日一言\s*[:：]?\s*'), '')
        .replaceFirst(RegExp(r'^(?:[-*•]|\d+[.、)）]|[一二三四五六七八九十]+[、.])\s*'), '')
        .replaceAll(RegExp(r'^[「『“"\s]+|[」』”"\s]+$'), '')
        .trim();
    if (line.isEmpty) continue;
    // A model may put multiple alternatives on the same line: keep one sentence.
    final end = RegExp(r'[。！？!?]|\.(?:\s|$)').firstMatch(line);
    if (end != null) line = line.substring(0, end.start + 1);
    return line;
  }
  return '今天也要认真照顾自己。';
}
