import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tide_bot/douyin_detail.dart';
import 'package:tide_bot/link_page_utils.dart';
import 'package:tide_bot/link_preview_service.dart';
import 'package:tide_bot/platform_media_parser.dart';

http.Response jsonResponse(Object value) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> main() async {
  const id = '7430000000000000001';
  final item = {
    'aweme_id': id,
    'desc': '目标视频',
    'video': {
      'PlayAddrStruct': {'uri': 'v0200_example'},
      'coverUrl': {
        'UrlList': ['https://cdn.example/cover.jpg']
      },
    },
  };
  check(
      douyinCoverUrl(item) == 'https://cdn.example/cover.jpg', 'cover aliases');
  check(
      Uri.parse(douyinVideoUrl(item)!).queryParameters['video_id'] ==
          'v0200_example',
      'opaque playback ID');
  check(
      douyinVideoUrl({
            'video': {
              'play_addr': {'uri': 'https://cdn.example/video.mp4'}
            }
          }) ==
          'https://cdn.example/video.mp4',
      'URI already contains URL');
  check(
      findVideoItem({
            'items': [
              {'aweme_id': 'other', 'video': {}},
              item
            ]
          }, id: id)?['desc'] ==
          '目标视频',
      'reject unrelated recommendation');
  var calls = 0;
  final client = MockClient((request) async {
    calls++;
    if (request.url.path.contains('/detail/')) {
      check(request.headers['origin'] == 'https://open.douyin.com',
          'open origin');
      return http.Response(
          jsonEncode({
            'status_code': 0,
            'aweme_detail': {'aweme_id': 'wrong', 'video': {}}
          }),
          200);
    }
    return jsonResponse({
      'status_code': 0,
      'aweme_details': [item]
    });
  });
  check((await fetchDouyinDetail(client, id))?['aweme_id'] == id && calls == 2,
      'wrong detail falls back to matching slides response');
  client.close();
  final blocked =
      MockClient((_) async => http.Response('<html>verify</html>', 200));
  check(await fetchDouyinDetail(blocked, id) == null, 'challenge is not media');
  blocked.close();
  final previewClient = MockClient((request) async {
    check(request.url.path.endsWith('/detail/'), 'direct ID skips shell');
    return jsonResponse({'status_code': 0, 'aweme_detail': item});
  });
  final preview = await LinkPreviewService.withClient(previewClient)
      .fetchPreview('https://www.douyin.com/video/$id');
  check(preview.imageUrl == 'https://cdn.example/cover.jpg', 'preview cover');
  check(preview.videoUrl?.contains('video_id=v0200_example') == true,
      'preview preserves video for frame fallback');
  previewClient.close();
  final noCover = Map<String, dynamic>.from(item);
  noCover['video'] = {
    'play_addr': {'uri': 'v0200_example'}
  };
  final noCoverClient =
      MockClient((_) async => jsonResponse({'aweme_detail': noCover}));
  final fallback = await LinkPreviewService.withClient(noCoverClient)
      .fetchPreview('https://www.douyin.com/video/$id');
  check(fallback.imageUrl == null && fallback.videoUrl != null,
      'missing cover retains playable video');
  noCoverClient.close();
  final pageClient = MockClient((request) async {
    if (request.url.path.contains('/detail/') ||
        request.url.path.contains('/slidesinfo/')) {
      return http.Response('', 403);
    }
    return http.Response.bytes(
        utf8.encode('<script>window._ROUTER_DATA = ${jsonEncode({
              'loaderData': {
                'item_list': [item]
              }
            })};</script>'),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'});
  });
  final fromPage = await LinkPreviewService.withClient(pageClient)
      .fetchPreview('https://www.douyin.com/video/$id');
  check(
      fromPage.imageUrl == 'https://cdn.example/cover.jpg' &&
          fromPage.videoUrl != null,
      'blocked API retains page fallback');
  pageClient.close();
  final shortClient = MockClient((request) async {
    if (request.url.host == 'v.douyin.com') {
      return http.Response('', 302,
          headers: {'location': 'https://www.douyin.com/video/$id'});
    }
    if (request.url.path.endsWith('/detail/')) {
      return jsonResponse({'aweme_detail': item});
    }
    return http.Response('<html>shell</html>', 200);
  });
  final shortPreview = await LinkPreviewService.withClient(shortClient)
      .fetchPreview('https://v.douyin.com/example/');
  check(
      shortPreview.imageUrl == 'https://cdn.example/cover.jpg' &&
          shortPreview.url.endsWith(id),
      'short redirect resolves matching detail');
  shortClient.close();
  print('Douyin parser and preview checks passed.');
}
