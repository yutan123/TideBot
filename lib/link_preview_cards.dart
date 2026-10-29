import 'platform_share_cover.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'link_preview_models.dart';
import 'platform_link_launcher.dart';
import 'theme.dart';
import 'global_notice.dart';

/// 普通网页链接卡片（参考图一设计）
class WebLinkCard extends StatelessWidget {
  final LinkPreviewData data;
  final bool isUser;

  const WebLinkCard({
    super.key,
    required this.data,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final maxWidth = isPortrait ? screenWidth * 0.75 : screenWidth * 0.5;

    return GestureDetector(
      onTap: () => _launchUrl(data.url),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: theme.isDark ? 0.3 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧文字区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 15,
                          color: theme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _extractDomain(data.url),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textWeak,
                              fontFamily: 'TideFont',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.textStrong,
                        fontFamily: 'TideFont',
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        data.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textWeak,
                          fontFamily: 'TideFont',
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右侧图标/图片区域
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: data.imageUrl != null && data.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          data.imageUrl!,
                          headers: data.imageHeaders,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: theme.primary,
                                          value: progress.expectedTotalBytes ==
                                                  null
                                              ? null
                                              : progress.cumulativeBytesLoaded /
                                                  progress.expectedTotalBytes!,
                                        ),
                                      ),
                                    ),
                          errorBuilder: (_, __, ___) => _defaultIcon(theme),
                        ),
                      )
                    : _defaultIcon(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultIcon(TideTheme theme) {
    return Center(
      child: Icon(
        Icons.public_rounded,
        size: 32,
        color: theme.primary,
      ),
    );
  }

  String _extractDomain(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.host.replaceFirst('www.', '');
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 视频分享卡片（抖音/小红书/B站，参考图二设计）
class VideoShareCard extends StatelessWidget {
  final LinkPreviewData data;
  final bool isUser;

  const VideoShareCard({
    super.key,
    required this.data,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.68).clamp(0.0, 260.0);
    final info = _getPlatformInfo();
    return Semantics(
      button: true,
      label: '在${info.name}打开：${data.title}',
      child: GestureDetector(
        onTap: () => _launchVideo(data.url),
        child: Container(
          width: width,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  PlatformShareCover(
                      data: data, placeholder: _placeholderCover(theme, info)),
                  Center(
                      child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.36),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54),
                    ),
                    child: const Icon(Icons.open_in_new_rounded,
                        size: 20, color: Colors.white),
                  )),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.textStrong,
                              fontFamily: 'TideFont',
                              height: 1.3)),
                      const SizedBox(height: 6),
                      Row(children: [
                        _getPlatformIcon(info, size: 14),
                        const SizedBox(width: 5),
                        Expanded(
                            child: Text(info.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textWeak,
                                    fontFamily: 'TideFont'))),
                      ]),
                    ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderCover(TideTheme theme, PlatformInfo info) {
    return Container(
      color: theme.buttonSecondary,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _getPlatformIcon(info, size: 28),
            const SizedBox(height: 12),
            Text(
              '封面暂不可用 · 点击打开',
              style: TextStyle(
                fontSize: 11,
                color: theme.textWeak,
                fontFamily: 'TideFont',
              ),
            ),
          ],
        ),
      ),
    );
  }

  PlatformInfo _getPlatformInfo() {
    return switch (data.type) {
      LinkType.douyin => PlatformInfo.douyin,
      LinkType.xiaohongshu => PlatformInfo.xiaohongshu,
      LinkType.bilibili => PlatformInfo.bilibili,
      _ => PlatformInfo.douyin,
    };
  }

  Widget _getPlatformIcon(PlatformInfo info, {double size = 20}) {
    final iconData = switch (data.type) {
      LinkType.douyin => Icons.music_note_rounded,
      LinkType.xiaohongshu => Icons.bookmark_rounded,
      LinkType.bilibili => Icons.tv_rounded,
      _ => Icons.videocam_rounded,
    };

    return Icon(iconData, size: size, color: Colors.black87);
  }

  Future<void> _launchVideo(String url) async {
    if (await launchPlatformLink(data)) return;
    GlobalNotice.show('无法打开链接，请确认已安装浏览器或对应平台应用');
  }
}
