import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tide_bot/platform_video_resolver.dart';
import 'package:tide_bot/platform_media_parser.dart';
import 'package:tide_bot/link_preview_service.dart';

http.Response page(String html) => http.Response.bytes(utf8.encode(html), 200,
    headers: {'content-type': 'text/html; charset=utf-8'});
http.Response api(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200,
        headers: {'content-type': 'application/json'});

void main() {
  const bili = 'https://www.bilibili.com/video/BV1xx411c7mD?p=2';
  test('B站按分P请求播放地址，封面不作为图集', () async {
    final resolver = PlatformVideoResolver.withClient(MockClient((r) async {
      if (r.url.path.endsWith('/view')) {
        return api({
          'bvid': 'BV1xx411c7mD',
          'cid': 11,
          'title': '视频',
          'pic': '//img.example.com/cover.jpg',
          'pages': [
            {'page': 1, 'cid': 11},
            {'page': 2, 'cid': 22}
          ]
        });
      }
      expect(r.url.path, '/x/player/playurl');
      expect(r.url.queryParameters['cid'], '22');
      return api({
        'durl': [
          {'url': 'https://media.example.com/video.mp4'}
        ]
      });
    }));
    final result = (await resolver.parse(bili))!;
    expect(result.videoUrl, 'https://media.example.com/video.mp4');
    expect(result.coverUrl, 'https://img.example.com/cover.jpg');
    expect(result.isGallery, isFalse);
    expect(result.imageUrls, isEmpty);
  });
  test('B站DASH保留独立音轨并优先H264', () async {
    final resolver = PlatformVideoResolver.withClient(MockClient((r) async {
      if (r.url.path.endsWith('/view')) {
        return api({'bvid': 'BV1xx411c7mD', 'cid': 1});
      }
      if (r.url.queryParameters['fnval'] == '1') return api({});
      return api({
        'dash': {
          'video': [
            {
              'codecid': 12,
              'bandwidth': 1,
              'baseUrl': 'https://cdn.example.com/hevc'
            },
            {
              'codecid': 7,
              'bandwidth': 2,
              'base_url': 'https://cdn.example.com/h264'
            },
          ],
          'audio': [
            {'base_url': 'https://cdn.example.com/audio'}
          ],
        }
      });
    }));
    final result = (await resolver.parse(bili.split('?').first))!;
    expect(result.videoUrl, 'https://cdn.example.com/h264');
    expect(result.audioUrl, 'https://cdn.example.com/audio');
  });
  test('B站只有封面或多段媒体时明确失败，不误判图集', () async {
    final resolver = PlatformVideoResolver.withClient(MockClient((r) async {
      if (r.url.path.endsWith('/view')) {
        return api({
          'bvid': 'BV1xx411c7mD',
          'cid': 1,
          'pic': 'https://img.example.com/a'
        });
      }
      return api({
        'durl': [
          {'url': 'https://cdn.example.com/1'},
          {'url': 'https://cdn.example.com/2'}
        ]
      });
    }));
    final result = (await resolver.parse(bili.split('?').first))!;
    expect(result.videoUrl, isNull);
    expect(result.isGallery, isFalse);
    expect(result.imageUrls, isEmpty);
    expect(result.failureReason, isNotEmpty);
  });
  test('抖音短链多跳后读取百分号编码RENDER_DATA和驼峰播放地址', () async {
    final state = {
      'aweme': {
        'detail': {
          'awemeId': '1234567890123456789',
          'desc': '视频标题',
          'video': {
            'playAddr': {
              'urlList': ['//cdn.example.com/douyin.mp4']
            },
            'cover': {
              'urlList': ['https://img.example.com/cover.jpg']
            }
          },
        }
      }
    };
    final resolver = PlatformVideoResolver.withClient(MockClient((r) async {
      if (r.url.host == 'v.douyin.com') {
        return http.Response('', 302, headers: {
          'location': 'https://www.douyin.com/video/1234567890123456789'
        });
      }
      return page(
          '<script id="RENDER_DATA">${Uri.encodeComponent(jsonEncode(state))}</script>');
    }));
    final result = (await resolver.parse('https://v.douyin.com/test/'))!;
    expect(result.videoUrl, 'https://cdn.example.com/douyin.mp4');
    expect(result.title, '视频标题');
    expect(result.isGallery, isFalse);
  });
  for (final isVideo in [true, false]) {
    test('小红书${isVideo ? '视频封面与视频地址分离' : '图文提取全部图片'}并保留访问token', () async {
      final note = {
        'noteId': 'abc123',
        'type': isVideo ? 'video' : 'normal',
        'title': '笔记',
        'desc': '正文',
        'imageList': [
          {
            'infoList': [
              {'url': '//img.example.com/1.jpg'}
            ]
          },
          {'urlDefault': 'https://img.example.com/2.jpg'},
        ],
        if (isVideo)
          'video': {
            'media': {
              'stream': {
                'h264': [
                  {'masterUrl': 'https://cdn.example.com/note.mp4'}
                ]
              }
            }
          },
      };
      final resolver = PlatformVideoResolver.withClient(MockClient((r) async {
        expect(r.url.queryParameters['xsec_token'], 'keep');
        return page('<script>window.__INITIAL_STATE__=${jsonEncode({
              'note': {
                'noteDetailMap': {
                  'abc123': {'note': note}
                }
              }
            })}</script>');
      }));
      final result = (await resolver.parse(
          'https://www.xiaohongshu.com/explore/abc123?xsec_token=keep'))!;
      expect(result.coverUrl, 'https://img.example.com/1.jpg');
      expect(result.isGallery, !isVideo);
      expect(result.imageUrls.length, isVideo ? 0 : 2);
      expect(
          result.videoUrl, isVideo ? 'https://cdn.example.com/note.mp4' : null);
    });
  }
  test('抖音图集不拿封面视频冒充作品视频', () async {
    final resolver = PlatformVideoResolver.withClient(
        MockClient((r) async => page('<script>window._ROUTER_DATA=${jsonEncode({
                  'aweme_id': '123',
                  'desc': '图文',
                  'video': {
                    'play_addr': {
                      'url_list': ['https://cdn.example.com/cover.mp4']
                    }
                  },
                  'images': [
                    {
                      'url_list': ['https://img.example.com/1.jpg']
                    }
                  ],
                })}</script>')));
    final result = (await resolver.parse('https://www.douyin.com/note/123'))!;
    expect(result.isGallery, isTrue);
    expect(result.videoUrl, isNull);
    expect(result.imageUrls, ['https://img.example.com/1.jpg']);
  });
  test('抖音桌面壳页回退移动分享页，保留作品地址供App直达', () async {
    var shareFetched = false;
    final resolver =
        PlatformVideoResolver.withClient(MockClient((request) async {
      if (request.url.host == 'v.douyin.com') {
        return http.Response('', 302, headers: {
          'location': 'https://www.douyin.com/video/1234567890123456789'
        });
      }
      if (request.url.path.startsWith('/share/video/')) {
        shareFetched = true;
        expect(request.headers['User-Agent'], contains('iPhone'));
        return page('<script>_ROUTER_DATA = ${jsonEncode({
              'loaderData': {
                'video_(id)/page': {
                  'videoInfoRes': {
                    'item_list': [
                      {
                        'aweme_id': '1234567890123456789',
                        'desc': '实际视频',
                        'video': {
                          'download_addr': {
                            'url_list': ['https://cdn.example.com/play.mp4']
                          },
                          'cover': {
                            'url_list': ['https://img.example.com/share.jpg']
                          }
                        }
                      }
                    ]
                  }
                }
              }
            })}</script>');
      }
      return page('<title>抖音</title>');
    }));
    const original = 'https://v.douyin.com/fallback/';
    final result = (await resolver.parse(original))!;
    expect(shareFetched, isTrue);
    expect(result.videoUrl, 'https://cdn.example.com/play.mp4');
    expect(result.resolvedUrl, contains('/share/video/1234567890123456789/'));
    final preview = await LinkPreviewService.instance.fetchPreview(original);
    expect(preview.appUri.toString(),
        'snssdk1128://aweme/detail/1234567890123456789');
    LinkPreviewService.instance.clearCache();
  });
  test('验证页保留失败原因，不伪造媒体', () async {
    final resolver = PlatformVideoResolver.withClient(MockClient((r) async => page(
        '<title>请登录</title><meta property="og:video" content="https://www.douyin.com/video/123">')));
    final result = (await resolver.parse('https://www.douyin.com/video/123'))!;
    expect(result.videoUrl, isNull);
    expect(result.isGallery, isFalse);
    expect(result.failureReason, isNotEmpty);
  });
  test('网页video标签媒体回退支持协议相对地址并拒绝非HTTP地址', () {
    expect(
        pageVideoUrl('<video><source src="//cdn.example.com/a.mp4"></video>'),
        'https://cdn.example.com/a.mp4');
    expect(
        pageVideoUrl(
            '<meta property="og:video" content="javascript:alert(1)">'),
        isNull);
  });
}
