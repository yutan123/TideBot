import 'dart:convert';
import 'dart:io';
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
    final lower = url.toLowerCase();
    return _isDouyinUrl(lower) ||
        _isXiaohongshuUrl(lower) ||
        _isBilibiliUrl(lower);
  }

  /// 从文本中提取所有支持的平台视频链接
  List<String> extractLinks(String text) {
    final List<String> links = [];
    final Set<String> seen = {};

    // 抖音链接
    final douyinPatterns = [
      RegExp(r'https?://v\.douyin\.com/[^\s<>"()]+', caseSensitive: false),
      RegExp(
          r'https?://(?:www\.)?douyin\.com/(?:video|note|slides)/\d+[^\s<>"()]*',
          caseSensitive: false),
    ];
    for (final pattern in douyinPatterns) {
      for (final match in pattern.allMatches(text)) {
        final link = match.group(0)!;
        if (!seen.contains(link.toLowerCase())) {
          seen.add(link.toLowerCase());
          links.add(link);
        }
      }
    }

    // 小红书链接
    final xhsPatterns = [
      RegExp(r'https?://xhslink\.(?:com|cn)/[^\s<>"()]+', caseSensitive: false),
      RegExp(
          r'https?://(?:www\.)?xiaohongshu\.com/(?:explore|discovery/item)/[^\s<>"()]+',
          caseSensitive: false),
    ];
    for (final pattern in xhsPatterns) {
      for (final match in pattern.allMatches(text)) {
        final link = match.group(0)!;
        if (!seen.contains(link.toLowerCase())) {
          seen.add(link.toLowerCase());
          links.add(link);
        }
      }
    }

    // B站链接
    final biliPatterns = [
      RegExp(r'https?://b23\.tv/[^\s<>"()]+', caseSensitive: false),
      RegExp(
          r'https?://(?:www\.)?bilibili\.com/video/[Bb][Vv][0-9A-Za-z]{10}[^\s<>"()]*',
          caseSensitive: false),
    ];
    for (final pattern in biliPatterns) {
      for (final match in pattern.allMatches(text)) {
        final link = match.group(0)!;
        if (!seen.contains(link.toLowerCase())) {
          seen.add(link.toLowerCase());
          links.add(link);
        }
      }
    }

    return links;
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

  bool _isDouyinUrl(String url) {
    return url.contains('douyin.com') || url.contains('iesdouyin.com');
  }

  bool _isXiaohongshuUrl(String url) {
    return url.contains('xiaohongshu.com') ||
        url.contains('xhslink.com') ||
        url.contains('xhslink.cn');
  }

  bool _isBilibiliUrl(String url) {
    return url.contains('bilibili.com') || url.contains('b23.tv');
  }

  // ========== 抖音解析 ==========

  Future<PlatformVideoResult?> _parseDouyin(String url) async {
    try {
      // 1. 处理短链重定向
      String fullUrl = url;
      if (url.contains('v.douyin.com')) {
        fullUrl = await _getRedirectUrl(url, {'User-Agent': _douyinUA});
      }

      // 2. 提取视频ID
      final videoIdMatch = RegExp(r'/video/(\d+)').firstMatch(fullUrl) ??
          RegExp(r'/note/(\d+)').firstMatch(fullUrl) ??
          RegExp(r'(\d{19})').firstMatch(fullUrl);

      if (videoIdMatch == null) {
        print('[Douyin] 无法提取视频ID');
        return null;
      }

      final videoId = videoIdMatch.group(1)!;

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
      final loaderData = data['loaderData'] as Map<String, dynamic>?;
      if (loaderData == null) return null;

      // 查找 videoInfoRes
      Map<String, dynamic>? videoInfo;
      for (final value in loaderData.values) {
        if (value is Map && value.containsKey('videoInfoRes')) {
          videoInfo = value['videoInfoRes'] as Map<String, dynamic>?;
          break;
        }
      }

      if (videoInfo == null) return null;

      // 6. 提取item_list中的第一个视频
      final itemList = videoInfo['item_list'] as List?;
      if (itemList == null || itemList.isEmpty) return null;

      final item = itemList[0] as Map<String, dynamic>;

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

  /// 获取重定向后的URL
  Future<String> _getRedirectUrl(
      String url, Map<String, String> headers) async {
    try {
      final request = await HttpClient().headUrl(Uri.parse(url));
      headers.forEach((key, value) => request.headers.set(key, value));

      final response = await request.close();
      final redirectUrl = response.headers.value('location');

      if (redirectUrl != null) {
        return redirectUrl;
      }

      // 如果HEAD失败，尝试GET
      final getRequest = await HttpClient().getUrl(Uri.parse(url));
      headers.forEach((key, value) => getRequest.headers.set(key, value));
      final getResponse = await getRequest.close();

      return getResponse.redirects.isNotEmpty
          ? getResponse.redirects.last.location.toString()
          : url;
    } catch (e) {
      print('[Redirect] 获取重定向失败: $e');
      return url;
    }
  }

  /// 从HTML中提取 window._ROUTER_DATA
  String? _extractRouterData(String html) {
    final startMarker = 'window._ROUTER_DATA = ';
    final startIdx = html.indexOf(startMarker);
    if (startIdx == -1) return null;

    final braceStart = html.indexOf('{', startIdx);
    if (braceStart == -1) return null;

    int braceCount = 0;
    int index = braceStart;

    while (index < html.length) {
      if (html[index] == '{') {
        braceCount++;
      } else if (html[index] == '}') {
        braceCount--;
        if (braceCount == 0) {
          return html.substring(braceStart, index + 1);
        }
      }
      index++;
    }

    return null;
  }

  /// 从HTML中提取 window.__INITIAL_STATE__
  String? _extractInitialState(String html) {
    final pattern = RegExp(
        r'window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*</script>',
        dotAll: true);
    final match = pattern.firstMatch(html);

    if (match != null) {
      var jsonStr = match.group(1)!;
      // 替换 undefined 为 null
      jsonStr = jsonStr.replaceAll(RegExp(r'\bundefined\b'), 'null');
      return jsonStr;
    }

    // 备用方法：手动提取
    final startMarker = 'window.__INITIAL_STATE__';
    final startIdx = html.indexOf(startMarker);
    if (startIdx == -1) return null;

    final braceStart = html.indexOf('{', startIdx);
    if (braceStart == -1) return null;

    final scriptEnd = html.indexOf('</script>', startIdx);

    int braceCount = 0;
    int index = braceStart;
    bool inString = false;
    bool escapeNext = false;

    while (index < html.length && (scriptEnd == -1 || index < scriptEnd)) {
      final char = html[index];

      if (escapeNext) {
        escapeNext = false;
        index++;
        continue;
      }

      if (char == '\\') {
        escapeNext = true;
        index++;
        continue;
      }

      if (char == '"' && !inString) {
        inString = true;
      } else if (char == '"' && inString) {
        inString = false;
      }

      if (!inString) {
        if (char == '{') {
          braceCount++;
        } else if (char == '}') {
          braceCount--;
          if (braceCount == 0) {
            var jsonStr = html.substring(braceStart, index + 1);
            jsonStr = jsonStr.replaceAll(RegExp(r'\bundefined\b'), 'null');
            return jsonStr;
          }
        }
      }

      index++;
    }

    return null;
  }
}
