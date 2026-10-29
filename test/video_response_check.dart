import 'dart:convert';
import 'dart:io';

import 'package:tide_bot/chat_content.dart';
import 'package:tide_bot/video_response.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  const analysis = '分析：用户要求分析视频，需要结合画面。画面中有一只猫正在跑动。';
  // Reproduce the old loss: chat planning filters discard valid source analysis.
  check(cleanChatContent(analysis).isEmpty, '回归样例必须触发原聊天过滤器');
  String parse(Object body, {int status = 200}) =>
      parseVideoAnalysisResponse(jsonEncode(body), statusCode: status);
  final completion = {
    'choices': [
      {
        'message': {'content': analysis}
      }
    ]
  };
  check(parse(completion) == analysis, '视频分析正文不能被聊天清洗规则吞掉');
  check(parse({'output': completion}) == analysis, '支持嵌套兼容响应');
  check(parse({'data': completion}) == analysis, '支持 data 包装');
  check(
      parse({
            'output': {'text': analysis}
          }) ==
          analysis,
      '支持原生正文');
  check(
      parse({
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '画面'},
                    {'type': 'text', 'text': '声音'}
                  ]
                }
              }
            ]
          }) ==
          '画面\n声音',
      '支持多段正文');
  check(
      parse({
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': analysis}
                ]
              }
            ]
          }) ==
          analysis,
      '支持 message output');
  final sse = [
    ': keepalive',
    '',
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'reasoning_content': '不是正文'}
            }
          ]
        })}',
    '',
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '画面'}
            }
          ]
        })}',
    '',
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '声音'}
            }
          ]
        })}',
    '',
    'data: [DONE]',
    ''
  ].join('\r\n');
  check(parseVideoAnalysisResponse(sse, statusCode: 200) == '画面声音',
      '支持意外返回的 SSE，排除推理字段');
  for (final sample in [
    (
      {
        'error': {'message': 'model does not support video_url'}
      },
      200
    ),
    ({'code': 'InvalidParameter', 'message': 'bad video'}, 200),
    (
      {
        'error': {'message': 'invalid key'}
      },
      401
    ),
    ({'choices': []}, 200),
    (
      {
        'choices': [
          {
            'message': {'reasoning_content': 'thinking', 'content': ''}
          }
        ]
      },
      200
    ),
  ]) {
    var rejected = false;
    try {
      parse(sample.$1, status: sample.$2);
    } on StateError {
      rejected = true;
    }
    check(rejected, '业务错误或空正文不得视为成功：$sample');
  }
  var detailKept = false;
  try {
    parse({
      'error': {'message': 'model does not support video_url'}
    });
  } on StateError catch (error) {
    detailKept =
        error.message.toString().contains('model does not support video_url');
  }
  check(detailKept, '保留服务商错误原因');
  stdout.writeln('视频响应检查通过：复现正文误清洗、JSON/嵌套/多段/SSE、HTTP 200 业务错误及空正文');
}
