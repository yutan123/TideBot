import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tide_bot/link_page_utils.dart';
import 'package:tide_bot/link_preview_models.dart';
import 'package:tide_bot/link_preview_service.dart';
import 'package:tide_bot/platform_video_resolver.dart';

http.Response _response(String body, int status,
        {Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(body), status, headers: {
      'content-type': 'text/html; charset=utf-8',
      ...?headers,
    });

void main() {
  test('自动视频解析仅接受作品与短链，不处理主页或个人空间', () {
    final links = PlatformVideoResolver().extractLinks(
      'https://www.douyin.com/user/person https://www.bilibili.com/ '
      'https://v.douyin.com/abc/。 https://xhslink.cn/abc '
      'https://www.iesdouyin.com/share/video/1234567890123456789/',
    );
    expect(links, [
      'https://v.douyin.com/abc/',
      'https://xhslink.cn/abc',
      'https://www.iesdouyin.com/share/video/1234567890123456789/',
    ]);
  });
  test('短链 GET 多跳和相对 Location 保留最终作品地址与封面', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      expect(request.method, 'GET');
      if (request.url.host == 'b23.tv') {
        return _response('', 302,
            headers: {'location': 'https://www.bilibili.com/go'});
      }
      if (request.url.path == '/go') {
        return _response('', 307,
            headers: {'location': '/video/BV1xx411c7mD?p=2'});
      }
      if (request.url.host == 'api.bilibili.com') {
        return _response(
            jsonEncode({
              'code': 0,
              'data': {'title': '目标视频', 'pic': '//i.example.com/cover.jpg'}
            }),
            200);
      }
      return _response('<title>页面</title>', 200);
    });
    final service = LinkPreviewService.withClient(client);
    final data = await service.fetchPreview('https://b23.tv/abc');
    expect(data.url, 'https://www.bilibili.com/video/BV1xx411c7mD?p=2');
    expect(data.appUri.toString(), 'bilibili://video/BV1xx411c7mD?p=2');
    expect(data.title, '目标视频');
    expect(data.imageUrl, 'https://i.example.com/cover.jpg');
    expect(data.imageHeaders['Referer'], 'https://www.bilibili.com/');
    expect(requests.length, 4);
  });

  test('抖音结构化数据提供标题封面并生成作品详情路由', () async {
    final state = {
      'loaderData': {
        'video_(id)/page': {
          'videoInfoRes': {
            'item_list': [
              {
                'aweme_id': '1234567890123456789',
                'desc': '标题包含 } 和 undefined',
                'author': {'nickname': '作者'},
                'video': {
                  'cover': {
                    'url_list': ['https://img.example.com/a.jpg']
                  }
                }
              }
            ]
          }
        }
      }
    };
    final client = MockClient((r) async {
      if (r.url.host == 'v.douyin.com') {
        return _response('', 302, headers: {
          'location':
              'https://www.iesdouyin.com/share/video/1234567890123456789/'
        });
      }
      return _response(
          '<script>window._ROUTER_DATA=${jsonEncode(state)};</script>', 200);
    });
    final data = await LinkPreviewService.withClient(client)
        .fetchPreview('https://v.douyin.com/abc/');
    expect(data.title, '标题包含 } 和 undefined');
    expect(data.imageUrl, 'https://img.example.com/a.jpg');
    expect(data.appUri.toString(),
        'snssdk1128://aweme/detail/1234567890123456789');
  });

  test('小红书 cn 短链保留安全参数并提取笔记封面', () async {
    final client = MockClient((r) async {
      if (r.url.host == 'xhslink.cn') {
        return _response('', 302, headers: {
          'location':
              'https://www.xiaohongshu.com/explore/abcdef123?xsec_token=a%2Bb'
        });
      }
      return _response(
          '''<script>window.__INITIAL_STATE__={"note":{"noteDetailMap":{"abcdef123":{"note":{"title":"笔记标题","imageList":[{"urlDefault":"//img.example.com/x.jpg"}],"unused":undefined}}}}};</script>''',
          200);
    });
    final data = await LinkPreviewService.withClient(client)
        .fetchPreview('https://xhslink.cn/abc');
    expect(data.type, LinkType.xiaohongshu);
    expect(data.title, '笔记标题');
    expect(data.imageUrl, 'https://img.example.com/x.jpg');
    expect(data.appUri?.queryParameters['xsec_token'], 'a+b');
    expect(data.appUri?.path, '/abcdef123');
  });

  test('普通网页相对封面根据重定向后的页面解析', () async {
    final client = MockClient((r) async => r.url.path == '/short'
        ? _response('', 302, headers: {'location': '/posts/1'})
        : _response(
            '<meta name="twitter:image" content="../cover.jpg"><meta property="og:title" content="标题">',
            200));
    final data = await LinkPreviewService.withClient(client)
        .fetchPreview('https://example.com/short');
    expect(data.imageUrl, 'https://example.com/cover.jpg');
  });

  test('失败不污染平台类型或永久缓存，下一次可以恢复', () async {
    var calls = 0;
    final service = LinkPreviewService.withClient(MockClient((r) async {
      calls++;
      return calls == 1
          ? _response('', 403)
          : _response('<meta property="og:image" content="/a.jpg">', 200);
    }));
    final failed = await service.fetchPreview('https://xhslink.cn/abc');
    expect(failed.type, LinkType.xiaohongshu);
    expect(failed.imageUrl, isNull);
    expect(failed.url, 'https://xhslink.cn/abc');
    expect((await service.fetchPreview(failed.url)).imageUrl, isNotNull);
  });

  test('同一短链并发请求合并', () async {
    var calls = 0;
    final service = LinkPreviewService.withClient(MockClient((r) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return _response('<meta property="og:image" content="/a.jpg">', 200);
    }));
    await Future.wait([
      service.fetchPreview('https://example.com/a'),
      service.fetchPreview('https://example.com/a')
    ]);
    expect(calls, 1);
  });

  test('循环重定向有界结束', () async {
    final client = MockClient(
        (r) async => _response('', 302, headers: {'location': '/loop'}));
    await expectLater(
        fetchLinkPage(client, Uri.parse('https://example.com/loop'), {}),
        throwsFormatException);
  });

  test('URL 提取删除中文标点、去重，不把仿冒域名识别为平台', () {
    expect(
        LinkPreviewService.extractUrls(
            '看看 https://v.douyin.com/abc/。 https://v.douyin.com/abc/'),
        ['https://v.douyin.com/abc/']);
    expect(
        LinkPreviewService.identifyLinkType(
            'https://douyin.com.evil.example/video/1'),
        LinkType.web);
    expect(LinkPreviewService.identifyLinkType('https://xhslink.cn/a'),
        LinkType.xiaohongshu);
  });

  test('未解析出作品 ID 的短链不拼接无效 scheme', () {
    const data = LinkPreviewData(
        url: 'https://v.douyin.com/abc/', title: '抖音视频', type: LinkType.douyin);
    expect(data.appUri, isNull);
  });

  test('JSON 状态解析保留引号、转义和正文中的 undefined', () {
    const html =
        r'''<script>window.__INITIAL_STATE__ = {"text":"undefined } \" {","missing":undefined};</script>''';
    final state = extractPageState(html, 'window.__INITIAL_STATE__');
    expect(state?['text'], 'undefined } " {');
    expect(state?.containsKey('missing'), isTrue);
    expect(state?['missing'], isNull);
  });
  test('抖音200壳页设置nonce后携带cookie重试一次', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return _response('<title>shell</title>', 200,
            headers: {'set-cookie': '_ac_nonce=abc; Path=/; HttpOnly'});
      }
      expect(request.headers['Cookie'], '_ac_nonce=abc');
      return _response('<title>video</title>', 200);
    });
    final result = await fetchLinkPage(
        client, Uri.parse('https://www.douyin.com/share/video/123/'), {});
    expect(calls, 2);
    expect(result.response.body, contains('video'));
  });
  test('重定向cookie仅发给相同主机，不传递给外部CDN', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1)
        return _response('', 302,
            headers: {'location': '/step2', 'set-cookie': 'share=abc; Path=/'});
      if (calls == 2) {
        expect(request.headers['Cookie'], 'share=abc');
        return _response('', 302,
            headers: {'location': 'https://cdn.example.com/video'});
      }
      expect(request.headers['Cookie'], isNull);
      return _response('done', 200);
    });
    await fetchLinkPage(client, Uri.parse('https://example.com/share'), {});
    expect(calls, 3);
  });
}
