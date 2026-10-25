import 'dart:convert';
import 'dart:io';
import 'link_page_utils.dart';
import 'link_preview_service.dart';
import 'link_preview_models.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 平台视频解析结果
class PlatformVideoResult {
  final String platform;
  final String title;
  final String author;
  final String? description;
  final String? videoUrl;
  final List<String> imageUrls;
  final Map<String, String> headers;

  PlatformVideoResult({
    required this.platform,
    required this.title,
    required this.author,
    this.description,
    this.videoUrl,
    this.imageUrls = const [],
    this.headers = const {},
  });
}

/// 平台视频解析服务
class PlatformVideoResolver {
  static final PlatformVideoResolver _instance =
      PlatformVideoResolver._internal();
  factory PlatformVideoResolver() => _instance;
  PlatformVideoResolver._internal();

  // User-Agent
  static const String _douyinUA =
      'Mozilla/5.0 (Linux; Android 8.0.0; SM-G955U Build/R16NW) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';
  static const String _xiaohongshuUA =
      'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36 Edg/142.0.0.0';
  static const String _bilibiliUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 检测链接是否为支持的平台视频链接
  bool canParse(String url) {
    return LinkPreviewService.identifyLinkType(url) != LinkType.web;
  }

  /// 从文本中提取所有支持的平台视频链接
  List<String> extractLinks(String text) {
    return LinkPreviewService.extractUrls(text).where((url) {
      final uri = Uri.parse(url);
      return switch (LinkPreviewService.identifyLinkType(url)) {
        LinkType.douyin =>
          uri.host == 'v.douyin.com' || LinkPreviewService.videoId(url) != null,
        LinkType.xiaohongshu => uri.host == 'xhslink.com' ||
            uri.host == 'xhslink.cn' ||
            RegExp(r'^/(?:explore|discovery/item)/[^/]+').hasMatch(uri.path),
        LinkType.bilibili => uri.host == 'b23.tv' ||
            RegExp(r'^/video/(?:BV[0-9A-Za-z]{10}|av\d+)', caseSensitive: false)
                .hasMatch(uri.path),
        LinkType.web => false,
      };
    }).toList();
  }

  /// 解析视频链接
  Future<PlatformVideoResult?> parse(String url) async {
    try {
      final lower = url.toLowerCase();
      if (_isDouyinUrl(lower)) {
        return await _parseDouyin(url);
      } else if (_isXiaohongshuUrl(lower)) {
        return await _parseXiaohongshu(url);
      } else if (_isBilibiliUrl(lower)) {
        return await _parseBilibili(url);
      }
      return null;
    } catch (e) {
      print('[PlatformVideoResolver] 解析失败: $url, error: $e');
      return null;
    }
  }

  /// 下载视频到本地临时目录
  Future<String?> downloadVideo(
      String videoUrl, Map<String, String> headers) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'platform_video_$timestamp.mp4';
      final filePath = '${tempDir.path}/$filename';

      final response = await http
          .get(
            Uri.parse(videoUrl),
            headers: headers,
          )
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        print('[PlatformVideoResolver] 下载失败: status=${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[PlatformVideoResolver] 下载异常: $e');
      return null;
    }
  }

  // ========== 平台判断 ==========

  bool _isDouyinUrl(String url) =>
      LinkPreviewService.identifyLinkType(url) == LinkType.douyin;
  bool _isXiaohongshuUrl(String url) =>
      LinkPreviewService.identifyLinkType(url) == LinkType.xiaohongshu;
  bool _isBilibiliUrl(String url) =>
      LinkPreviewService.identifyLinkType(url) == LinkType.bilibili;

  // ========== 抖音解析 ==========

  Future<PlatformVideoResult?> _parseDouyin(String url) async {
    try {
      // 1. 处理短链重定向
      String fullUrl = url;
      if (url.contains('v.douyin.com')) {
        fullUrl = await _getRedirectUrl(url, {'User-Agent': _douyinUA});
      }

      // 2. 提取视频ID
      final videoId = LinkPreviewService.videoId(fullUrl);
      if (videoId == null) return null;

      // 3. 获取视频详情页
      final detailUrl = 'https://www.iesdouyin.com/share/video/$videoId/';
      final response = await http.get(
        Uri.parse(detailUrl),
        headers: {
          'User-Agent': _douyinUA,
          'Referer': 'https://www.douyin.com/',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('[Douyin] 获取详情页失败: ${response.statusCode}');
        return null;
      }

      // 4. 提取 window._ROUTER_DATA
      final html = response.body;
      final routerData = _extractRouterData(html);
      if (routerData == null) {
        print('[Douyin] 未找到 _ROUTER_DATA');
        return null;
      }

      // 5. 解析JSON
      final data = json.decode(routerData);
      final item = findVideoItem(data);
      if (item == null) return null;

      // 7. 提取视频信息
      final title = item['desc'] as String? ?? '';
      final author = (item['author'] as Map?)?['nickname'] as String? ?? '';

      // 提取视频URL
      String? videoUrl;
      final video = item['video'] as Map<String, dynamic>?;
      if (video != null) {
        final playAddr = video['play_addr'] as Map?;
        if (playAddr != null) {
          final urlList = playAddr['url_list'] as List?;
          if (urlList != null && urlList.isNotEmpty) {
            videoUrl = urlList[0] as String?;
          }
        }
      }

      if (videoUrl == null) {
        print('[Douyin] 未找到视频URL');
        return null;
      }

      // 处理URL格式
      if (videoUrl.startsWith('//')) {
        videoUrl = 'https:$videoUrl';
      } else if (videoUrl.startsWith('http://')) {
        videoUrl = videoUrl.replaceFirst('http://', 'https://');
      }

      return PlatformVideoResult(
        platform: 'douyin',
        title: title,
        author: author,
        videoUrl: videoUrl,
        headers: {
          'User-Agent': _douyinUA,
          'Referer': 'https://www.douyin.com/',
        },
      );
    } catch (e) {
      print('[Douyin] 解析异常: $e');
      return null;
    }
  }

  // ========== 小红书解析 ==========

  Future<PlatformVideoResult?> _parseXiaohongshu(String url) async {
    try {
      // 1. 处理短链重定向
      String fullUrl = url;
      if (url.contains('xhslink.com') || url.contains('xhslink.cn')) {
        fullUrl = await _getRedirectUrl(url, {'User-Agent': _xiaohongshuUA});
      }

      // 2. 转换为桌面版URL（更稳定）
      fullUrl = fullUrl.replaceAll('/discovery/item/', '/explore/');

      // 3. 获取页面内容
      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'User-Agent': _xiaohongshuUA,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('[XHS] 获取页面失败: ${response.statusCode}');
        return null;
      }

      // 4. 提取 window.__INITIAL_STATE__
      final html = response.body;
      final initialState = _extractInitialState(html);
      if (initialState == null) {
        print('[XHS] 未找到 __INITIAL_STATE__');
        return null;
      }

      // 5. 解析JSON
      final data = json.decode(initialState);

      // 6. 提取笔记ID
      final noteIdMatch =
          RegExp(r'/(?:explore|discovery/item)/([^/?]+)').firstMatch(fullUrl);
      if (noteIdMatch == null) return null;
      final noteId = noteIdMatch.group(1)!;

      // 7. 查找笔记数据
      Map<String, dynamic>? noteData;

      // 尝试移动端路径
      final mobileNote = data['noteData'] as Map?;
      if (mobileNote != null) {
        final mobileData = mobileNote['data'] as Map?;
        if (mobileData != null) {
          noteData = mobileData['noteData'] as Map<String, dynamic>?;
        }
      }

      // 尝试桌面端路径
      if (noteData == null) {
        final note = data['note'] as Map?;
        if (note != null) {
          final noteDetailMap = note['noteDetailMap'] as Map?;
          if (noteDetailMap != null) {
            final detail = noteDetailMap[noteId] as Map?;
            if (detail != null) {
              noteData = detail['note'] as Map<String, dynamic>?;
            }
          }
        }
      }

      if (noteData == null) {
        print('[XHS] 未找到笔记数据');
        return null;
      }

      // 8. 提取信息
      final noteType = noteData['type'] as String? ?? 'normal';
      final title = noteData['title'] as String? ?? '';
      final desc = noteData['desc'] as String? ?? '';
      final user = noteData['user'] as Map?;
      final author = user?['nickname'] as String? ?? '';

      String? videoUrl;
      List<String> imageUrls = [];

      if (noteType == 'video') {
        // 视频类型
        final videoInfo = noteData['video'] as Map?;
        if (videoInfo != null) {
          final media = videoInfo['media'] as Map?;
          if (media != null) {
            final stream = media['stream'] as Map?;
            if (stream != null) {
              // 优先使用 H.264
              final h264 = stream['h264'] as dynamic;
              if (h264 is List && h264.isNotEmpty) {
                final firstStream = h264[0] as Map?;
                videoUrl = firstStream?['masterUrl'] as String? ??
                    firstStream?['master_url'] as String?;
              } else if (h264 is Map) {
                videoUrl = h264['masterUrl'] as String? ??
                    h264['master_url'] as String?;
              }
            }
          }
        }

        if (videoUrl != null) {
          if (videoUrl.startsWith('//')) {
            videoUrl = 'https:$videoUrl';
          } else if (videoUrl.startsWith('http://')) {
            videoUrl = videoUrl.replaceFirst('http://', 'https://');
          }
        }
      } else {
        // 图集类型
        final imageList = noteData['imageList'] as List?;
        if (imageList != null) {
          for (final img in imageList) {
            if (img is Map) {
              String? imgUrl =
                  img['urlDefault'] as String? ?? img['url'] as String?;
              if (imgUrl != null) {
                if (imgUrl.startsWith('//')) {
                  imgUrl = 'https:$imgUrl';
                } else if (imgUrl.startsWith('http://')) {
                  imgUrl = imgUrl.replaceFirst('http://', 'https://');
                }
                imageUrls.add(imgUrl);
              }
            }
          }
        }
      }

      return PlatformVideoResult(
        platform: 'xiaohongshu',
        title: title,
        author: author,
        description: desc,
        videoUrl: videoUrl,
        imageUrls: imageUrls,
        headers: {
          'User-Agent': _xiaohongshuUA,
          'Referer': fullUrl,
        },
      );
    } catch (e) {
      print('[XHS] 解析异常: $e');
      return null;
    }
  }

  // ========== B站解析 ==========

  Future<PlatformVideoResult?> _parseBilibili(String url) async {
    try {
      // 1. 处理短链重定向
      String fullUrl = url;
      if (url.contains('b23.tv')) {
        fullUrl = await _getRedirectUrl(url, {'User-Agent': _bilibiliUA});
      }

      // 2. 提取BV号
      final bvMatch = RegExp(r'[Bb][Vv]([0-9A-Za-z]{10})').firstMatch(fullUrl);
      if (bvMatch == null) {
        print('[Bilibili] 无法提取BV号');
        return null;
      }

      final bvid = 'BV${bvMatch.group(1)}';

      // 3. 调用B站API获取视频信息
      final apiUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'User-Agent': _bilibiliUA,
          'Referer': 'https://www.bilibili.com/',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('[Bilibili] API请求失败: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      if (data['code'] != 0) {
        print('[Bilibili] API返回错误: ${data['message']}');
        return null;
      }

      final videoData = data['data'] as Map<String, dynamic>;
      final title = videoData['title'] as String? ?? '';
      final author = (videoData['owner'] as Map?)?['name'] as String? ?? '';
      final desc = videoData['desc'] as String? ?? '';
      final pic = videoData['pic'] as String? ?? '';

      // B站视频需要进一步获取播放地址，这里暂时返回封面和信息
      // 实际播放需要处理dash/flv格式和鉴权
      return PlatformVideoResult(
        platform: 'bilibili',
        title: title,
        author: author,
        description: desc,
        videoUrl: null, // B站视频获取较复杂，暂不支持直接下载
        imageUrls: pic.isNotEmpty ? [pic] : [],
        headers: {
          'User-Agent': _bilibiliUA,
          'Referer': 'https://www.bilibili.com/',
        },
      );
    } catch (e) {
      print('[Bilibili] 解析异常: $e');
      return null;
    }
  }

  // ========== 辅助方法 ==========

  Future<String> _getRedirectUrl(
      String url, Map<String, String> headers) async {
    final client = http.Client();
    try {
      final page = await fetchLinkPage(client, Uri.parse(url), headers);
      return page.uri.toString();
    } finally {
      client.close();
    }
  }

  String? _extractRouterData(String html) {
    final state = extractPageState(html, 'window._ROUTER_DATA');
    return state == null ? null : jsonEncode(state);
  }

  String? _extractInitialState(String html) {
    final state = extractPageState(html, 'window.__INITIAL_STATE__');
    return state == null ? null : jsonEncode(state);
  }
}
