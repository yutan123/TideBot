import 'dart:convert';
import 'package:http/http.dart' as http;
import 'link_page_utils.dart';

const douyinShareUserAgent =
    'Mozilla/5.0 (Linux; Android 8.0.0; SM-G955U Build/R16NW) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';

/// The open-platform request context also serves ordinary shared works.
/// Keep this separate so preview and media analysis use the same fallback.
Future<Map<String, dynamic>?> fetchDouyinDetail(
    http.Client client, String id) async {
  if (!RegExp(r'^\d+$').hasMatch(id)) return null;
  final endpoints = [
    Uri.https('www.douyin.com', '/aweme/v1/web/aweme/detail/',
        {'aweme_id': id, 'aid': '6383'}),
    Uri.https('www.iesdouyin.com', '/web/api/v2/aweme/slidesinfo/',
        {'aweme_ids': '[$id]', 'request_source': '200'}),
  ];
  for (final uri in endpoints) {
    try {
      final response = await client.get(uri, headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
        'Origin': 'https://open.douyin.com',
        'Referer': 'https://open.douyin.com/',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) continue;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || ![null, 0, '0'].contains(data['status_code']))
        continue;
      final item = findVideoItem(data, id: id);
      if (item != null) return item;
    } catch (_) {
      // A challenge, empty body or transport failure must allow page fallback.
    }
  }
  return null;
}
