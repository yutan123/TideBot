import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

http.BaseRequest buildBotImageRequest(
    {required String baseUrl,
    required String model,
    required String apiKey,
    required String prompt,
    List<int>? reference}) {
  final fields = {
    'model': model,
    'prompt': reference == null
        ? prompt
        : '参考所附图片中的人物外观与特征，按照以下要求创作，保持人物身份一致：$prompt',
    'n': '1',
    'size': '1024x1024'
  };
  if (reference != null) {
    return http.MultipartRequest('POST', Uri.parse('$baseUrl/images/edits'))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('image', reference,
          filename: 'reference.png', contentType: MediaType('image', 'png')));
  }
  return http.Request('POST', Uri.parse('$baseUrl/images/generations'))
    ..headers.addAll(
        {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'})
    ..body = jsonEncode({...fields, 'n': 1});
}
