/// User photo editing is separate from generating the bot's own portraits.
/// These instructions guide tool selection; they are never appended to the
/// image provider's prompt.
const userImageEditRule =
    '编辑用户提供的原图（转动漫、换画风、换装、修图、换背景等）必须调用 edit_user_image，不能用 generate_image 代替。'
    'source=current 对应本轮用户图片，source=history 对应历史用户图片；两组编号独立，image_number 必须来自当前上下文明示的编号，禁止猜测、混用或传入路径/URL。'
    '一次调用把指定原图作为本次请求的临时参考图并立即图改，无需先设置参考图，不会替换机器人永久人像参考图。'
    'prompt 由你根据用户要求完整编写，必须自行写清需要修改的部分、画风及需要保留的人物、服装、姿势、背景或构图；不要机械保留用户明确要求修改的部分。'
    '此工具将 prompt 原样发送给图生图模型，系统不会追加任何画风、穿搭、人物身份、构图或其他提示词；generate_image 的机器人参考图和全局画风规则不适用于此工具。'
    '用户指代不清或缺少有效编号时先询问，不得擅自选图；工具失败不得声称已改好，不得退回文生图冒充原图修改。';

Map<String, dynamic> userImageEditToolSchema({
  required List<int> currentImageNumbers,
  required List<int> historyImageNumbers,
}) =>
    {
      'type': 'function',
      'function': {
        'name': 'edit_user_image',
        'description': '$userImageEditRule '
            '可用编号参见当前上下文。',
        'parameters': {
          'type': 'object',
          'properties': {
            'source': {
              'type': 'string',
              'enum': ['current', 'history'],
              'description': 'current=本轮用户图片；history=历史用户图片，必须明确选择。',
            },
            'image_number': {
              'type': 'integer',
              'minimum': 1,
              'description': '所选 source 内的图片编号，不是聊天消息 ID、路径或 URL。',
            },
            'prompt': {
              'type': 'string',
              'minLength': 1,
              'description': '你编写的完整图改提示词，将原样发送；自行写明修改目标和保留内容，系统不补写。',
            },
          },
          'required': ['source', 'image_number', 'prompt'],
          'additionalProperties': false,
        },
      },
    };

String userImageEditContext({
  required List<int> currentImageNumbers,
  required List<int> historyImageNumbers,
}) =>
    '【已授权工具：用户原图编辑】$userImageEditRule '
    '本轮编号（source=current）：${currentImageNumbers.isEmpty ? '无' : currentImageNumbers.map((n) => '[本轮图片#$n]').join('、')}；'
    '历史编号（source=history）：${historyImageNumbers.isEmpty ? '无' : historyImageNumbers.map((n) => '[图片#$n]').join('、')}。';

class UserImageEditSelection {
  const UserImageEditSelection({
    required this.source,
    required this.imageNumber,
    required this.path,
    required this.prompt,
  });
  final String source;
  final int imageNumber;
  final String path;
  final String prompt;
}

/// Resolve only request-local, application-owned attachments. No model-supplied
/// filesystem path is accepted, and no persistent reference setting is written.
UserImageEditSelection resolveUserImageEdit(
  Map<String, dynamic> args, {
  required Map<int, String> currentImages,
  required Map<int, String> historyImages,
}) {
  if (args.keys.any(
      (key) => !const {'source', 'image_number', 'prompt'}.contains(key))) {
    throw const FormatException(
        '仅支持 source、image_number、prompt；不要传入图片路径、URL 或永久参考图参数。');
  }
  final source = args['source'];
  if (source != 'current' && source != 'history') {
    throw const FormatException('source 必须为 current（本轮）或 history（历史），不能省略或猜测。');
  }
  final number = args['image_number'];
  if (number is! int || number < 1) {
    throw const FormatException('image_number 必须为上下文明示的正整数图片编号。');
  }
  final prompt = args['prompt'];
  if (prompt is! String || prompt.trim().isEmpty) {
    throw const FormatException('prompt 必须是你编写的非空完整图改提示词，系统不会自动补写。');
  }
  final images = source == 'current' ? currentImages : historyImages;
  final path = images[number];
  if (path == null || path.trim().isEmpty) {
    throw FormatException(
        'source=$source 的图片#$number 不在当前可用列表中，请核对来源和编号，不要改用其他图片。');
  }
  return UserImageEditSelection(
    source: source as String,
    imageNumber: number,
    path: path,
    prompt: prompt,
  );
}
