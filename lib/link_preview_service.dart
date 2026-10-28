import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'link_preview_models.dart';
import 'link_page_utils.dart';
import 'platform_media_parser.dart';

class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._();
  static LinkPreviewService get instance => _instance;
  LinkPreviewService._() : _client = http.Client();
  LinkPreviewService.withClient(this._client);
  final http.Client _client;
  final Map<String, LinkPreviewData> _cache = {};
  final Map<String, Future<LinkPreviewData>> _pending = {};

  static final RegExp _urlRegex = RegExp(
    r'''https?://[^\s<>"'（）()]+''',
    caseSensitive: false,
  );
  static List<String> extractUrls(String text) => _urlRegex
      .allMatches(text)
      .map((m) => m[0]!.replaceFirst(RegExp(r'[，。！？、；：,.!?;:]+$'), ''))
      .where((url) => Uri.tryParse(url)?.host.isNotEmpty == true)
      .toSet()
      .toList();

  static LinkType identifyLinkType(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    bool matches(String domain) => host == domain || host.endsWith('.$domain');
    if (matches('douyin.com') || matches('iesdouyin.com'))
      return LinkType.douyin;
    if (matches('xiaohongshu.com') ||
        matches('xhslink.com') ||
        matches('xhslink.cn')) return LinkType.xiaohongshu;
    if (matches('bilibili.com') || matches('b23.tv')) return LinkType.bilibili;
    return LinkType.web;
  }

  Future<LinkPreviewData> fetchPreview(String url) {
    if (_cache.containsKey(url)) return Future.value(_cache[url]);
    return _pending.putIfAbsent(
        url,
        () => _fetch(url).whenComplete(() {
              _pending.remove(url);
            }));
  }

  Future<LinkPreviewData> _fetch(String url) async {
    final type = identifyLinkType(url);
    var target = url;
    try {
      var page = await fetchLinkPage(_client, Uri.parse(url), _headers(type));
      target = page.uri.toString();
      // 抖音普通页通常只有 JS 壳；分享详情页提供视频结构化数据。
      if (type == LinkType.douyin) {
        final id = videoId(target);
        if (id != null) {
          target = 'https://www.douyin.com/video/$id';
          try {
            final detail = await fetchLinkPage(
                _client,
                Uri.parse('https://www.iesdouyin.com/share/video/$id/'),
                _headers(type));
            if (detail.response.statusCode == 200) page = detail;
          } catch (_) {/* 保留短链页面的元数据 */}
        }
      }
      if (page.response.statusCode != 200) return _fallback(target, type);
      final document = html_parser
          .parse(utf8.decode(page.response.bodyBytes, allowMalformed: true));
      String? meta(String key) => document
          .querySelector('meta[property="$key"], meta[name="$key"]')
          ?.attributes['content']
          ?.trim();
      var title = meta('og:title') ??
          meta('twitter:title') ??
          document.querySelector('title')?.text.trim();
      var description = meta('og:description') ?? meta('description') ?? '';
      var image = meta('og:image') ??
          meta('twitter:image') ??
          meta('twitter:image:src') ??
          meta('image') ??
          document
              .querySelector('meta[itemprop="image"]')
              ?.attributes['content']
              ?.trim();
      // 很多中文网站没有 og:image，继续尝试 image_src、JSON-LD 和站点图标。
      image ??= document
          .querySelector('link[rel="image_src"], link[rel*="icon"]')
          ?.attributes['href']
          ?.trim();
      if (image == null || image.isEmpty) {
        for (final script in document
            .querySelectorAll('script[type="application/ld+json"]')) {
          try {
            final value = jsonDecode(script.text);
            final candidates = value is List ? value : [value];
            for (final candidate in candidates) {
              if (candidate is Map && candidate['image'] != null) {
                final candidateImage = candidate['image'];
                image = candidateImage is String
                    ? candidateImage
                    : candidateImage is List && candidateImage.isNotEmpty
                        ? candidateImage.first.toString()
                        : null;
                if (image != null && image.isNotEmpty) break;
              }
            }
          } catch (_) {}
          if (image != null && image.isNotEmpty) break;
        }
      }
      // 百度等页面可能主动不提供文章图片，使用站点图标保持卡片有视觉内容。
      if (type == LinkType.web) {
        image ??= '${page.uri.scheme}://${page.uri.host}/favicon.ico';
      }
      final html = document.outerHtml;
      if (type == LinkType.douyin) {
        for (final state in platformPageStates(html)) {
          final item = findVideoItem(state);
          if (item == null) continue;
          title = item['desc']?.toString() ?? title;
          final author = item['author'];
          if (author is Map)
            description = author['nickname']?.toString() ?? description;
          image = douyinCoverUrl(item) ?? image;
          image ??= mediaUrl(item['images']);
          break;
        }
      } else if (type == LinkType.xiaohongshu) {
        final id = RegExp(r'/(?:explore|discovery/item)/([a-zA-Z0-9]+)')
            .firstMatch(target)
            ?.group(1);
        for (final state in platformPageStates(html)) {
          final note = findNoteData(state, id);
          if (note == null) continue;
          title =
              note['title']?.toString() ?? note['desc']?.toString() ?? title;
          description = note['desc']?.toString() ?? description;
          final images = noteImageUrls(note);
          if (images.isNotEmpty) image = images.first;
          break;
        }
      } else if (type == LinkType.bilibili) {
        final id = RegExp(r'BV[0-9A-Za-z]{10}', caseSensitive: false)
            .firstMatch(target)
            ?.group(0);
        if (id != null) {
          try {
            final response = await _client
                .get(
                    Uri.https('api.bilibili.com', '/x/web-interface/view',
                        {'bvid': id}),
                    headers: _headers(type))
                .timeout(const Duration(seconds: 8));
            final data = jsonDecode(response.body);
            if (data['code'] == 0 && data['data'] is Map) {
              final aid = data['data']['aid'];
              if (aid is num && aid > 0) {
                final resolved = Uri.parse(target);
                target = resolved.replace(path: '/video/av$aid').toString();
              }
              title = data['data']['title'] as String? ?? title;
              image = data['data']['pic'] as String? ?? image;
              description = data['data']['desc'] as String? ?? description;
            }
          } catch (_) {/* 接口不可用时使用页面元数据 */}
        }
      }
      final imageUri =
          image == null || image.isEmpty ? null : page.uri.resolve(image);
      final preview = LinkPreviewData(
        url: target,
        title: title?.isNotEmpty == true ? title! : _fallbackTitle(type),
        description: description,
        imageUrl:
            imageUri != null && ['http', 'https'].contains(imageUri.scheme)
                ? imageUri.toString()
                : null,
        imageHeaders: _headers(type),
        type: type,
      );
      // 不永久缓存缺封面或受限结果，下次打开消息允许重试。
      if (type == LinkType.web || preview.imageUrl != null)
        _cache[url] = preview;
      return preview;
    } catch (_) {
      return _fallback(target, type);
    }
  }

  static String? videoId(String url) {
    final uri = Uri.tryParse(url);
    return RegExp(r'/(?:share/video|video|note|slides)/(\d+)')
            .firstMatch(uri?.path ?? '')
            ?.group(1) ??
        uri?.queryParameters['modal_id'] ??
        uri?.queryParameters['aweme_id'];
  }

  static String _fallbackTitle(LinkType type) => switch (type) {
        LinkType.douyin => '抖音视频',
        LinkType.xiaohongshu => '小红书笔记',
        LinkType.bilibili => '哔哩哔哩视频',
        _ => '网页链接',
      };
  LinkPreviewData _fallback(String url, LinkType type) => LinkPreviewData(
        url: url,
        title: _fallbackTitle(type),
        description: '预览暂不可用，点击打开原链接',
        type: type,
      );
  static Map<String, String> _headers(LinkType type) => {
        'User-Agent': type == LinkType.douyin
            ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
            : 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        if (type == LinkType.douyin) 'Referer': 'https://www.douyin.com/',
        if (type == LinkType.xiaohongshu)
          'Referer': 'https://www.xiaohongshu.com/',
        if (type == LinkType.bilibili) 'Referer': 'https://www.bilibili.com/',
      };
  // Media resolution already fetched the platform page; reuse its actual cover.
  void rememberPreview(String originalUrl, LinkPreviewData preview) {
    if (preview.imageUrl?.isNotEmpty == true) _cache[originalUrl] = preview;
  }

  void clearCache() => _cache.clear();
  void removeCachedUrl(String url) => _cache.remove(url);
}
