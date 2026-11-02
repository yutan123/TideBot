/// 链接预览数据模型
class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String? imageUrl;
  final LinkType type;
  final Map<String, String> imageHeaders;

  const LinkPreviewData({
    required this.url,
    required this.title,
    this.description = '',
    this.imageUrl,
    this.imageHeaders = const {},
    required this.type,
  });

  /// 仅在有作品 ID 时打开详情路由，短链交给 HTTPS App Link 处理。
  Uri? get appUri {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.path;
    switch (type) {
      case LinkType.douyin:
        final id = RegExp(r'/(?:video|note|slides)/(\d+)')
                .firstMatch(path)
                ?.group(1) ??
            uri.queryParameters['modal_id'] ??
            uri.queryParameters['aweme_id'];
        return id != null && RegExp(r'^\d+$').hasMatch(id)
            ? Uri.parse('snssdk1128://aweme/detail/$id')
            : null;
      case LinkType.xiaohongshu:
        final id = RegExp(r'/(?:explore|discovery/item)/([a-zA-Z0-9]+)')
            .firstMatch(path)
            ?.group(1);
        return id == null
            ? null
            : Uri(
                scheme: 'xhsdiscover',
                host: 'item',
                path: '/$id',
                queryParameters:
                    uri.queryParameters.isEmpty ? null : uri.queryParameters);
      case LinkType.bilibili:
        final id = RegExp(r'/video/((?:BV[0-9A-Za-z]{10})|(?:av\d+))',
                caseSensitive: false)
            .firstMatch(path)
            ?.group(1);
        return id == null
            ? null
            : Uri(
                scheme: 'bilibili',
                host: 'video',
                path: '/${id.startsWith('av') ? id.substring(2) : id}',
                queryParameters:
                    uri.queryParameters.isEmpty ? null : uri.queryParameters);
      case LinkType.web:
        return null;
    }
  }

  factory LinkPreviewData.error(String url) => LinkPreviewData(
        url: url,
        title: '链接预览失败',
        description: url,
        type: LinkType.web,
      );
}

/// 链接类型枚举
enum LinkType {
  web, // 普通网页
  douyin, // 抖音视频
  xiaohongshu, // 小红书
  bilibili, // 哔哩哔哩
}

/// 平台信息
class PlatformInfo {
  final String name;
  final String scheme;
  final String webHost;

  const PlatformInfo({
    required this.name,
    required this.scheme,
    required this.webHost,
  });

  static const douyin = PlatformInfo(
    name: '抖音',
    scheme: 'snssdk1128://',
    webHost: 'douyin.com',
  );

  static const xiaohongshu = PlatformInfo(
    name: '小红书',
    scheme: 'xhsdiscover://',
    webHost: 'xiaohongshu.com',
  );

  static const bilibili = PlatformInfo(
    name: 'B站',
    scheme: 'bilibili://',
    webHost: 'bilibili.com',
  );
}
