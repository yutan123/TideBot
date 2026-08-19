String cleanChatContent(String value) => value
    .replaceFirst(
      RegExp(r'^\s*(?:(?:data|event)\s*:\s*)?response\s*[:：]\s*',
          caseSensitive: false),
      '',
    )
    .trim();
