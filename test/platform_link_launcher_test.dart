import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/link_preview_models.dart';
import 'package:tide_bot/platform_link_launcher.dart';

void main() {
  for (final entry in [
    (
      LinkType.douyin,
      'https://v.douyin.com/test/',
      'https://www.douyin.com/video/123',
      'snssdk1128://aweme/detail/123'
    ),
    (
      LinkType.xiaohongshu,
      'https://xhslink.cn/test',
      'https://www.xiaohongshu.com/explore/abc123?xsec_token=keep',
      'xhsdiscover://item/abc123?xsec_token=keep'
    ),
    (
      LinkType.bilibili,
      'https://b23.tv/test',
      'https://www.bilibili.com/video/av123?p=2',
      'bilibili://video/123?p=2'
    ),
  ]) {
    test('${entry.$1}短链解析后直接打开App，不经过浏览器', () async {
      final opened = <String>[];
      final result = await launchPlatformLink(
        LinkPreviewData(url: entry.$2, title: '作品', type: entry.$1),
        resolvePreview: (url) async {
          expect(url, entry.$2);
          expect(opened, isEmpty);
          return LinkPreviewData(url: entry.$3, title: '作品', type: entry.$1);
        },
        openUrl: (uri) async {
          opened.add(uri.toString());
          return true;
        },
      );
      expect(result, isTrue);
      expect(opened, [entry.$4]);
    });
  }
  test('未安装客户端时才回退网页', () async {
    final opened = <String>[];
    const data = LinkPreviewData(
        url: 'https://www.bilibili.com/video/av123',
        title: '作品',
        type: LinkType.bilibili);
    expect(
        await launchPlatformLink(data, openUrl: (uri) async {
          opened.add(uri.toString());
          return uri.scheme == 'https';
        }),
        isTrue);
    expect(opened, ['bilibili://video/123', data.url]);
  });
  test('短链解析异常仍能打开原链接', () async {
    final opened = <Uri>[];
    const data = LinkPreviewData(
        url: 'https://xhslink.cn/test',
        title: '作品',
        type: LinkType.xiaohongshu);
    expect(
        await launchPlatformLink(data,
            resolvePreview: (_) async => throw StateError('offline'),
            openUrl: (uri) async {
              opened.add(uri);
              return true;
            }),
        isTrue);
    expect(opened.single.toString(), data.url);
  });
}
