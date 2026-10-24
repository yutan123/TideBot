/// 链接预览数据模型
class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String? imageUrl;
  final LinkType type;

  const LinkPreviewData({
    required this.url,
    required this.title,
    this.description = '',
    this.imageUrl,
    required this.type,
  });

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
