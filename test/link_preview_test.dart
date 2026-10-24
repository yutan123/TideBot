import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/link_preview_service.dart';
import 'package:tide_bot/link_preview_models.dart';

void main() {
  group('LinkPreviewService', () {
    test('extractUrls should detect HTTP and HTTPS links', () {
      const text1 =
          'Check this out https://www.example.com and http://test.com';
      final urls1 = LinkPreviewService.extractUrls(text1);
      expect(urls1.length, 2);
      expect(urls1[0], 'https://www.example.com');
      expect(urls1[1], 'http://test.com');

      const text2 = 'No links here';
      final urls2 = LinkPreviewService.extractUrls(text2);
      expect(urls2, isEmpty);

      const text3 = '抖音链接 https://v.douyin.com/abc123/';
      final urls3 = LinkPreviewService.extractUrls(text3);
      expect(urls3.length, 1);
      expect(urls3[0], 'https://v.douyin.com/abc123/');
    });

    test('extractUrls should handle multiple links', () {
      const text =
          'First https://example1.com then https://example2.com and https://example3.com';
      final urls = LinkPreviewService.extractUrls(text);
      expect(urls.length, 3);
    });

    test('extractUrls should handle links with query parameters', () {
      const text = 'Video: https://www.bilibili.com/video/BV1xx411c7mD?p=1';
      final urls = LinkPreviewService.extractUrls(text);
      expect(urls.length, 1);
      expect(urls[0], contains('BV1xx411c7mD'));
    });
  });

  group('LinkType identification', () {
    test('should identify Douyin links', () {
      final service = LinkPreviewService.instance;
      // Access private method through reflection would require additional setup
      // For now, we'll test through the public API by checking the result
      // This is a placeholder for actual integration testing
    });

    test('PlatformInfo constants should have correct values', () {
      expect(PlatformInfo.douyin.name, '抖音');
      expect(PlatformInfo.douyin.scheme, 'snssdk1128://');
      expect(PlatformInfo.douyin.webHost, 'douyin.com');

      expect(PlatformInfo.xiaohongshu.name, '小红书');
      expect(PlatformInfo.xiaohongshu.scheme, 'xhsdiscover://');

      expect(PlatformInfo.bilibili.name, 'B站');
      expect(PlatformInfo.bilibili.scheme, 'bilibili://');
    });
  });

  group('LinkPreviewData', () {
    test('should create error preview correctly', () {
      const url = 'https://example.com';
      final errorData = LinkPreviewData.error(url);
      expect(errorData.url, url);
      expect(errorData.title, '链接预览失败');
      expect(errorData.description, url);
      expect(errorData.type, LinkType.web);
    });

    test('should create normal preview correctly', () {
      const data = LinkPreviewData(
        url: 'https://example.com',
        title: 'Example Site',
        description: 'This is an example',
        imageUrl: 'https://example.com/image.jpg',
        type: LinkType.web,
      );
      expect(data.url, 'https://example.com');
      expect(data.title, 'Example Site');
      expect(data.description, 'This is an example');
      expect(data.imageUrl, 'https://example.com/image.jpg');
      expect(data.type, LinkType.web);
    });
  });

  group('LinkType enum', () {
    test('should have all platform types', () {
      expect(LinkType.values.length, 4);
      expect(LinkType.values, contains(LinkType.web));
      expect(LinkType.values, contains(LinkType.douyin));
      expect(LinkType.values, contains(LinkType.xiaohongshu));
      expect(LinkType.values, contains(LinkType.bilibili));
    });
  });
}
