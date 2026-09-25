// 流式渲染时的内心独白缓冲区，跨调用持久化以处理分段标签
String _innerThoughtBuffer = '';
bool _insideInnerThought = false;

String cleanChatContent(String value) {
  // 先移除前缀
  var cleaned = value.replaceFirst(
    RegExp(r'^\s*(?:(?:data|event)\s*:\s*)?response\s*[:：]\s*',
        caseSensitive: false),
    '',
  );

  // 移除完整闭合的 tool_call 标签
  cleaned = cleaned.replaceAll(
    RegExp(r'<tool_call>.*?</tool_call>', dotAll: true),
    '',
  );

  // 处理内心独白：状态跟踪，识别到开头标签就进入缓冲模式，直到闭合标签才清空
  final buffer = StringBuffer();
  var index = 0;

  while (index < cleaned.length) {
    if (_insideInnerThought) {
      // 正在缓冲内心独白，寻找闭合标签
      final endTag = cleaned.indexOf('</inner_thought>', index);
      if (endTag >= 0) {
        // 找到闭合标签，清空缓冲并退出内心独白模式
        _innerThoughtBuffer = '';
        _insideInnerThought = false;
        index = endTag + '</inner_thought>'.length;
      } else {
        // 未找到闭合标签，将剩余内容存入缓冲
        _innerThoughtBuffer += cleaned.substring(index);
        break;
      }
    } else {
      // 寻找开头标签
      final startTag = cleaned.indexOf('<inner_thought>', index);
      if (startTag >= 0) {
        // 找到开头标签，先输出之前的正常内容
        buffer.write(cleaned.substring(index, startTag));
        // 进入内心独白模式
        _insideInnerThought = true;
        _innerThoughtBuffer = '';
        index = startTag + '<inner_thought>'.length;
      } else {
        // 没有开头标签，输出剩余所有内容
        buffer.write(cleaned.substring(index));
        break;
      }
    }
  }

  return buffer.toString().trim();
}
