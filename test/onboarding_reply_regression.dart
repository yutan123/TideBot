import 'package:tide_bot/onboarding_reply.dart';

void main() {
  void check(String name, Map<String, dynamic> result, bool expected) {
    if (isOnboardingReply(result) != expected) {
      throw StateError('Failed: $name');
    }
  }

  final textReply = {'role': 'assistant', 'type': 'text', 'content': '你好'};
  check('successful reply', {
    'success': true,
    'messages': [textReply],
  }, true);
  check('failed request', {
    'success': false,
    'messages': [textReply],
  }, false);
  check('silent result', {
    'success': true,
    'silent': true,
    'messages': [textReply],
  }, false);
  check('no reply', {'success': true}, false);
  check('only user message', {
    'success': true,
    'messages': [
      {'role': 'user', 'content': '你好'},
    ],
  }, false);
  check('thought is not a reply', {
    'success': true,
    'messages': [
      {'role': 'assistant', 'type': 'inner_thought', 'content': '思考中'},
    ],
  }, false);
  check('empty reply', {
    'success': true,
    'messages': [
      {'role': 'assistant', 'type': 'text', 'content': '  '},
    ],
  }, false);
  check('media reply', {
    'success': true,
    'messages': [
      {'role': 'assistant', 'type': 'image', 'file_path': '/image.png'},
    ],
  }, true);
  print('Onboarding reply regression passed (8 cases).');
}
