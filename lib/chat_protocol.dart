String chatListPreview({
  required String type,
  required String rawContent,
}) {
  if (type == 'shared_post') return '[动态]';
  final raw = rawContent.replaceAll('\n', ' ').trim();
  if (raw.isNotEmpty) return raw;
  return switch (type) {
    'image' => '[图片]',
    'audio' => '[语音]',
    'video' => '[视频]',
    'document' || 'file' => '[文件]',
    'sticker' => '[表情包]',
    'call_summary' => '[通话]',
    _ => '[消息]',
  };
}

String formatImagePlaceholder(int number, {String caption = ''}) {
  final tag = '[图片#$number]';
  final text = caption.trim();
  return text.isEmpty ? tag : '$tag\n$text';
}

int? parseImageNumber(dynamic value) {
  if (value is num) {
    final number = value.toInt();
    return number > 0 ? number : null;
  }
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final tagged = RegExp(r'(?:图片\s*#\s*)?(\d+)').firstMatch(raw);
  final number = int.tryParse(tagged?.group(1) ?? raw);
  if (number == null || number <= 0) return null;
  return number;
}

const sharedPostDeletedUserCopy = '原动态已删除';
const sharedPostDeletedModelCopy = '此动态已被删除，暂无法获取动态内容';

String sharedPostModelContext({
  required bool deleted,
  String author = '',
  String content = '',
  String time = '',
  bool hasImage = false,
}) {
  if (deleted) return sharedPostDeletedModelCopy;
  final imageNote = hasImage ? '动态附有一张图片。' : '';
  return '用户分享了一条动态。作者：${author.isEmpty ? '匿名' : author}；发布时间：$time；内容：$content；$imageNote'
      .trim();
}

Map<String, dynamic> sendStickerToolSchema(List<String> types) => {
      'type': 'function',
      'function': {
        'name': 'send_sticker',
        'description':
            '本轮表情包概率已命中，必须且只能调用一次。按类型选择表情包，type 必须来自允许列表；不要编造 sticker_id，不要把文件路径或 URL 写进参数或正文。',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': types,
              'description': '表情包类型/情绪分类',
            },
          },
          'required': ['type'],
          'additionalProperties': false,
        },
      },
    };

Map<String, dynamic> inspectImageToolSchema({
  String name = 'inspect_image',
  List<int> numbers = const [],
}) {
  final available =
      numbers.isEmpty ? '当前上下文中的 [图片#n]' : numbers.map((n) => '#$n').join('、');
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description':
          '查看用户发送的图片。图片在上下文中以 [图片#n] 表示，可用编号：$available。默认不会自动看图；只有需要理解画面时才调用。不要编造未提供的编号，不要要求或输出文件路径。',
      'parameters': {
        'type': 'object',
        'properties': {
          'image_number': {
            'type': 'integer',
            'minimum': 1,
            'description': '图片编号，例如 1 表示 [图片#1]',
          },
        },
        'required': ['image_number'],
        'additionalProperties': false,
      },
    },
  };
}
