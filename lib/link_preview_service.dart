import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'link_preview_models.dart';

/// 链接预览服务
class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._();
  static LinkPreviewService get instance => _instance;
  LinkPreviewService._();

  // 缓存，避免重复请求
  final Map<String, LinkPreviewData> _cache = {};

  /// URL 正则表达式
  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  /// 从文本中提取所有链接
  static List<String> extractUrls(String text) {
    final matches = _urlRegex.allMatches(text);
    return matches.map((m) => m.group(0)!).toList();
  }

  /// 识别链接类型
  LinkType _identifyLinkType(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return LinkType.web;

    final host = uri.host.toLowerCase();

    if (host.contains('douyin.com') || host.contains('iesdouyin.com')) {
      return LinkType.douyin;
    }
    if (host.contains('xiaohongshu.com') || host.contains('xhslink.com')) {
      return LinkType.xiaohongshu;
    }
    if (host.contains('bilibili.com') || host.contains('b23.tv')) {
      return LinkType.bilibili;
    }

    return LinkType.web;
  }

  /// 获取链接预览数据
  Future<LinkPreviewData> fetchPreview(String url) async {
    // 检查缓存
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    try {
      final type = _identifyLinkType(url);
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return LinkPreviewData.error(url);
      }

      final document = html_parser.parse(response.body);

      // 提取 Open Graph 元数据
      String? title;
      String? description;
      String? imageUrl;

      // 优先使用 og:title
      final ogTitle = document.querySelector('meta[property="og:title"]');
      title = ogTitle?.attributes['content'];

      // 降级到 title 标签
      if (title == null || title.isEmpty) {
        final titleElement = document.querySelector('title');
        title = titleElement?.text.trim();
      }

      // og:description
      final ogDesc = document.querySelector('meta[property="og:description"]');
      description = ogDesc?.attributes['content'];

      // 降级到 meta description
      if (description == null || description.isEmpty) {
        final metaDesc = document.querySelector('meta[name="description"]');
        description = metaDesc?.attributes['content'];
      }

      // og:image
      final ogImage = document.querySelector('meta[property="og:image"]');
      imageUrl = ogImage?.attributes['content'];

      final preview = LinkPreviewData(
        url: url,
        title: title?.trim().isNotEmpty == true ? title!.trim() : '网页链接',
        description: description?.trim() ?? '',
        imageUrl: imageUrl?.trim(),
        type: type,
      );

      // 缓存结果
      _cache[url] = preview;

      return preview;
    } catch (e) {
      final errorPreview = LinkPreviewData.error(url);
      _cache[url] = errorPreview;
      return errorPreview;
    }
  }

  /// 清除缓存
  void clearCache() {
    _cache.clear();
  }

  /// 移除特定 URL 的缓存
  void removeCachedUrl(String url) {
    _cache.remove(url);
  }
}
