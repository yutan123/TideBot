String cleanChatContent(String value) => value
    .replaceFirst(
      RegExp(r'^\s*(?:(?:data|event)\s*:\s*)?response\s*[:：]\s*',
          caseSensitive: false),
      '',
    )
    .replaceAll(RegExp(r'<tool_call>.*?</tool_call>', dotAll: true), '')
    .replaceAll(RegExp(r'<inner_thought>.*?</inner_thought>', dotAll: true), '')
    .trim();
