import 'dart:convert';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'link_page_utils.dart';
import 'link_preview_service.dart';
import 'link_preview_models.dart';
import 'platform_media_parser.dart';

class PlatformVideoResult {
  final String platform;
  final String title;
  final String author;
  final String? description;
  final String? resolvedUrl;
  final String? videoUrl;
  final String? audioUrl;
  final String? coverUrl;
  final List<String> imageUrls;
  final Map<String, String> headers;
  final bool isGallery;
  final String? failureReason;

  const PlatformVideoResult({
    required this.platform,
    required this.title,
    required this.author,
    this.description,
    this.resolvedUrl,
    this.videoUrl,
    this.audioUrl,
    this.coverUrl,
    this.imageUrls = const [],
    this.headers = const {},
    this.isGallery = false,
    this.failureReason,
  });
}

class PlatformVideoResolver {
  static final _instance = PlatformVideoResolver._internal();
  factory PlatformVideoResolver() => _instance;
  PlatformVideoResolver._internal() : _client = http.Client();
  PlatformVideoResolver.withClient(this._client);
  final http.Client _client;

  static const _mobileUA =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _shareUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  bool canParse(String url) =>
      LinkPreviewService.identifyLinkType(url) != LinkType.web;

  List<String> extractLinks(String text) =>
      LinkPreviewService.extractUrls(text).where((url) {
        final uri = Uri.parse(url);
        return switch (LinkPreviewService.identifyLinkType(url)) {
          LinkType.douyin => uri.host == 'v.douyin.com' ||
              LinkPreviewService.videoId(url) != null,
          LinkType.xiaohongshu => uri.host == 'xhslink.com' ||
              uri.host == 'xhslink.cn' ||
              RegExp(r'^/(?:explore|discovery/item)/[^/]+').hasMatch(uri.path),
          LinkType.bilibili => uri.host == 'b23.tv' ||
              RegExp(r'^/video/(?:BV[0-9A-Za-z]{10}|av\d+)',
                      caseSensitive: false)
                  .hasMatch(uri.path),
          LinkType.web => false,
        };
      }).toList();

  Future<PlatformVideoResult?> parse(String url) async {
    final type = LinkPreviewService.identifyLinkType(url);
    if (type == LinkType.web) return null;
    final platform = switch (type) {
      LinkType.douyin => 'douyin',
      LinkType.xiaohongshu => 'xiaohongshu',
      _ => 'bilibili',
    };
    try {
      final result = type == LinkType.bilibili
          ? await _parseBilibili(url)
          : await _parseSharePage(url, type);
      if (result.failureReason == null) {
        LinkPreviewService.instance.rememberPreview(
            url,
            LinkPreviewData(
              url: result.resolvedUrl ?? url,
              type: type,
              title: result.title.isEmpty ? '分享的内容' : result.title,
              description: result.description ?? result.author,
              imageUrl: result.coverUrl ?? result.imageUrls.firstOrNull,
              imageHeaders: result.headers,
            ));
      }
      return result;
    } catch (e) {
      print('[PlatformVideoResolver] $platform: $e');
      return PlatformVideoResult(
        platform: platform,
        title: '',
        author: '',
        failureReason: '平台页面或媒体接口暂不可访问，请稍后重试或打开原链接',
      );
    }
  }

  Future<PlatformVideoResult> _parseSharePage(String url, LinkType type) async {
    final douyin = type == LinkType.douyin;
    final headers = {
      'User-Agent': douyin ? _shareUA : _mobileUA,
      'Referer':
          douyin ? 'https://www.douyin.com/' : 'https://www.xiaohongshu.com/',
      'Accept':
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
    };
    var page = await fetchLinkPage(_client, Uri.parse(url), headers);
    final id = douyin
        ? LinkPreviewService.videoId(page.uri.toString()) ??
            LinkPreviewService.videoId(url)
        : RegExp(r'/(?:explore|discovery/item)/([^/?]+)')
            .firstMatch(page.uri.path)
            ?.group(1);
    final candidates = <Uri>[
      if (douyin && id != null)
        Uri.parse('https://www.douyin.com/share/video/$id/'),
      if (douyin && id != null)
        Uri.parse('https://www.iesdouyin.com/share/video/$id/'),
      if (douyin && id != null) Uri.parse('https://www.douyin.com/video/$id'),
      if (!douyin && page.uri.path.contains('/discovery/item/'))
        page.uri.replace(
            path: page.uri.path.replaceFirst('/discovery/item/', '/explore/')),
      if (!douyin && !page.uri.path.contains('/discovery/item/')) page.uri,
    ];
    for (var attempt = 0;; attempt++) {
      if (page.response.statusCode == 200) {
        final html = utf8.decode(page.response.bodyBytes, allowMalformed: true);
        for (final state in platformPageStates(html)) {
          final item = douyin ? findVideoItem(state) : findNoteData(state, id);
          if (item == null) continue;
          final video = douyin ? douyinVideoUrl(item) : noteVideoUrl(item);
          final gallery = douyin
              ? item['images'] is List && (item['images'] as List).isNotEmpty
              : item['type'] == 'normal';
          final images = douyin
              ? (item['images'] as List? ?? [])
                  .map(mediaUrl)
                  .whereType<String>()
                  .toList()
              : noteImageUrls(item);
          final videoInfo = item['video'];
          final cover = douyin && videoInfo is Map
              ? mediaUrl(videoInfo['dynamic_cover'] ??
                  videoInfo['dynamicCover'] ??
                  videoInfo['cover'] ??
                  videoInfo['origin_cover'] ??
                  videoInfo['originCover'])
              : (images.isEmpty ? null : images.first);
          final user = item[douyin ? 'author' : 'user'];
          if (video != null || gallery && images.isNotEmpty) {
            return PlatformVideoResult(
              resolvedUrl: page.uri.toString(),
              platform: douyin ? 'douyin' : 'xiaohongshu',
              title: (item['title'] ?? item['desc'] ?? '').toString(),
              author: user is Map ? (user['nickname'] ?? '').toString() : '',
              description: item['desc']?.toString(),
              videoUrl: gallery ? null : video,
              coverUrl: cover,
              imageUrls: gallery ? images : const [],
              isGallery: gallery,
              headers: {...headers, 'Referer': page.uri.toString()},
            );
          }
        }
        final video = pageVideoUrl(html);
        if (video != null) {
          return PlatformVideoResult(
            resolvedUrl: page.uri.toString(),
            platform: douyin ? 'douyin' : 'xiaohongshu',
            title: '',
            author: '',
            videoUrl: video,
            headers: {...headers, 'Referer': page.uri.toString()},
          );
        }
      }
      if (attempt >= candidates.length) break;
      final target = candidates[attempt];
      try {
        page = await fetchLinkPage(_client, target, {
          ...headers,
          if (!douyin || target.path.startsWith('/video/'))
            'User-Agent': _desktopUA,
        });
      } catch (_) {
        if (attempt + 1 >= candidates.length) break;
      }
    }
    return PlatformVideoResult(
      platform: douyin ? 'douyin' : 'xiaohongshu',
      title: '',
      author: '',
      failureReason: '平台未提供可读取的媒体地址，可能需要登录或验证；已保留原链接',
    );
  }

  Future<Map<String, dynamic>> _biliApi(String path, Map<String, String> query,
      Map<String, String> headers) async {
    final response = await _client
        .get(Uri.https('api.bilibili.com', path, query), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw HttpException('B站接口 HTTP ${response.statusCode}');
    final envelope = jsonDecode(utf8.decode(response.bodyBytes));
    if (envelope is! Map || envelope['code'] != 0 || envelope['data'] is! Map) {
      throw const FormatException('B站接口没有返回可用数据');
    }
    return Map<String, dynamic>.from(envelope['data'] as Map);
  }

  Future<PlatformVideoResult> _parseBilibili(String url) async {
    final headers = {
      'User-Agent': _desktopUA,
      'Referer': 'https://www.bilibili.com/'
    };
    var uri = Uri.parse(url);
    if (uri.host == 'b23.tv')
      uri = (await fetchLinkPage(_client, uri, headers)).uri;
    final bv = RegExp(r'BV[0-9A-Za-z]{10}', caseSensitive: false)
        .firstMatch(uri.path)
        ?.group(0);
    final av = RegExp(r'/video/av(\d+)', caseSensitive: false)
        .firstMatch(uri.path)
        ?.group(1);
    if (bv == null && av == null) throw const FormatException('无法识别B站视频编号');
    final data = await _biliApi(
        '/x/web-interface/view',
        {
          if (bv != null) 'bvid': bv,
          if (av != null) 'aid': av,
        },
        headers);
    final pages = data['pages'] is List ? data['pages'] as List : const [];
    final part = int.tryParse(uri.queryParameters['p'] ?? '') ?? 1;
    final page =
        pages.whereType<Map>().where((p) => p['page'] == part).firstOrNull;
    final cid = page?['cid'] ?? (part == 1 ? data['cid'] : null);
    String? video;
    String? audio;
    if (cid != null) {
      for (final format in ['1', '16']) {
        try {
          final play = await _biliApi(
              '/x/player/playurl',
              {
                'bvid': (data['bvid'] ?? bv ?? '').toString(),
                'cid': cid.toString(),
                'qn': '32',
                'fnval': format,
                'fnver': '0',
                'fourk': '0',
              },
              headers);
          final segments = play['durl'];
          if (segments is List && segments.length == 1)
            video = mediaUrl(segments.first);
          if (video == null && play['dash'] is Map) {
            final dash = play['dash'] as Map;
            final videos = (dash['video'] as List? ?? [])
                .whereType<Map>()
                .toList()
              ..sort((a, b) => ((a['bandwidth'] as num?) ?? 0)
                  .compareTo((b['bandwidth'] as num?) ?? 0));
            final h264 = videos.where((v) => v['codecid'] == 7).firstOrNull;
            final track = h264 ?? videos.firstOrNull;
            video = mediaUrl(track?['baseUrl'] ?? track?['base_url']);
            final audios = (dash['audio'] as List? ?? [])
                .whereType<Map>()
                .toList()
              ..sort((a, b) => ((a['bandwidth'] as num?) ?? 0)
                  .compareTo((b['bandwidth'] as num?) ?? 0));
            final sound = audios.firstOrNull;
            audio = mediaUrl(sound?['baseUrl'] ?? sound?['base_url']);
          }
          if (video != null) break;
        } catch (_) {/* Try the alternate documented stream format. */}
      }
    }
    final owner = data['owner'];
    return PlatformVideoResult(
      resolvedUrl: data['aid'] is num && (data['aid'] as num) > 0
          ? uri.replace(path: '/video/av${data['aid']}').toString()
          : uri.toString(),
      platform: 'bilibili',
      title: (data['title'] ?? '').toString(),
      author: owner is Map ? (owner['name'] ?? '').toString() : '',
      description: data['desc']?.toString(),
      coverUrl: mediaUrl(data['pic']),
      videoUrl: video,
      audioUrl: audio,
      headers: headers,
      failureReason: video == null ? 'B站未返回可下载的播放地址，可能需要登录或内容已受限' : null,
    );
  }

  Future<void> _download(String url, Map<String, String> headers, File file,
      {bool image = false}) async {
    final response = await _client
        .send(http.Request('GET', Uri.parse(url))..headers.addAll(headers))
        .timeout(const Duration(seconds: 30));
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (![200, 206].contains(response.statusCode) ||
        type.contains('text/html') ||
        type.contains('application/json') ||
        image && !type.startsWith('image/') && !type.contains('octet-stream')) {
      await response.stream.drain<void>();
      throw HttpException('媒体下载失败 HTTP ${response.statusCode} ($type)');
    }
    final sink = file.openWrite();
    try {
      await sink
          .addStream(response.stream.timeout(const Duration(seconds: 30)));
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await file.length() == 0) throw const FormatException('媒体文件为空');
  }

  Future<String?> downloadVideo(String videoUrl, Map<String, String> headers,
      {String? audioUrl}) async {
    final files = <File>[];
    try {
      final dir = await getTemporaryDirectory();
      final prefix =
          '${dir.path}/platform_${DateTime.now().microsecondsSinceEpoch}';
      final video = File('$prefix.mp4');
      files.add(video);
      await _download(videoUrl, headers, video);
      if (audioUrl == null) {
        files.remove(video);
        return video.path;
      }
      final audio = File('$prefix.m4a');
      files.add(audio);
      await _download(audioUrl, headers, audio);
      final output = File('${prefix}_merged.mp4');
      files.add(output);
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        video.path,
        '-i',
        audio.path,
        '-map',
        '0:v:0',
        '-map',
        '1:a:0',
        '-c',
        'copy',
        '-shortest',
        output.path,
      ]);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw const FormatException('视频音轨合并失败');
      }
      files.remove(output);
      return output.path;
    } catch (e) {
      print('[PlatformVideoResolver] 下载失败: $e');
      return null;
    } finally {
      for (final file in files) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<List<String>> downloadImages(PlatformVideoResult result) async {
    final files = <File>[];
    try {
      final dir = await getTemporaryDirectory();
      final prefix =
          '${dir.path}/platform_image_${DateTime.now().microsecondsSinceEpoch}';
      for (var i = 0; i < result.imageUrls.length; i++) {
        final file = File('${prefix}_$i.jpg');
        files.add(file);
        await _download(result.imageUrls[i], result.headers, file, image: true);
      }
      return files.map((f) => f.path).toList();
    } catch (_) {
      for (final file in files) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
