const portraitReferenceRule =
    '已设置的人像参考图是你自己的照片，用于保持人物外观与身份一致。调用 generate_image 时必须明确填写 use_portrait_reference：分享美食、景点、风景、物件等不含人物的画面可以填写 false，提示词应明确不出现人物，不要为了使用参考图额外添加人物；如果画面出现人物（包括自拍、合照或局部人像），必须填写 true。false 使用文生图，true 附带你的人像参考图进行图改。参考图只用于人物身份，不要求照搬原图背景、构图或姿势。';

Map<String, dynamic> botImageToolSchema({required bool hasPortraitReference}) =>
    {
      'type': 'function',
      'function': {
        'name': 'generate_image',
        'description':
            '当用户明确需要照片、图片、插画、绘制或创作视觉内容时必须调用；在你判断图片能明显帮助当前回答时也可以调用。只有画面包含人物时才描述穿搭，结合画面地点、时间、天气、活动、姿势与镜头范围选择合理穿搭，只保留当前画面可见且需要的服装细节；不得机械照搬完整日常穿搭。床上、居家、睡前、洗漱等场景优先自然的睡衣、居家服、袜子或赤足状态，不得无故写鞋或白天正装；被被子遮挡、坐姿或半身镜头时不要补写不可见的下半身穿搭。'
                '${hasPortraitReference ? portraitReferenceRule : '当前未设置人像参考图，使用文生图。'}',
        'parameters': {
          'type': 'object',
          'properties': {
            'prompt': {'type': 'string', 'description': '完整的绘图提示词'},
            if (hasPortraitReference)
              'use_portrait_reference': {
                'type': 'boolean',
                'description':
                    '是否加入你自己的照片作为人像参考图。画面出现人物必须为 true；美食、景点等不含人物的画面为 false。',
              },
          },
          'required': [
            'prompt',
            if (hasPortraitReference) 'use_portrait_reference',
          ],
          'additionalProperties': false,
        },
      },
    };

/// Reject ambiguous model decisions instead of silently choosing an image API.
bool resolvePortraitReference({
  required bool hasPortraitReference,
  required dynamic selection,
}) {
  if (selection != null && selection is! bool) {
    throw const FormatException('use_portrait_reference 必须是布尔值 true 或 false');
  }
  if (hasPortraitReference && selection == null) {
    throw const FormatException(
      '已设置你的人像参考图，请明确填写 use_portrait_reference：画面有人物为 true，不含人物为 false',
    );
  }
  if (!hasPortraitReference && selection == true) {
    throw const FormatException('当前未设置人像参考图，无法图改；请使用文生图');
  }
  return selection == true;
}
