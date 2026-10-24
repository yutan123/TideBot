import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'link_preview_models.dart';
import 'theme.dart';

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
                          fit: BoxFit.cover,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final maxWidth = isPortrait ? screenWidth * 0.75 : screenWidth * 0.5;
    final platformInfo = _getPlatformInfo();

    return GestureDetector(
      onTap: () => _launchVideo(data.url),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 8),
        child: Stack(
          children: [
            // 视频封面
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 9 / 16, // 竖屏视频比例
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.buttonSecondary,
                  ),
                  child: data.imageUrl != null && data.imageUrl!.isNotEmpty
                      ? Image.network(
                          data.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderCover(
                            theme,
                            platformInfo,
                          ),
                        )
                      : _placeholderCover(theme, platformInfo),
                ),
              ),
            ),
            // 渐变蒙层
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 播放按钮
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 36,
                    color: theme.primary,
                  ),
                ),
              ),
            ),
            // 左下角信息
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  // 平台 Logo 占位
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: _getPlatformIcon(platformInfo),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: 'TideFont',
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          platformInfo.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.85),
                            fontFamily: 'TideFont',
                            shadows: const [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            _getPlatformIcon(info, size: 48),
            const SizedBox(height: 12),
            Text(
              info.name,
              style: TextStyle(
                fontSize: 16,
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
    final platformInfo = _getPlatformInfo();

    // 尝试打开应用，失败则降级到网页
    final uri = Uri.tryParse(url);
    if (uri != null) {
      // 先尝试检查应用是否安装并打开
      final appUri = Uri.tryParse('${platformInfo.scheme}$url');
      if (appUri != null) {
        try {
          if (await canLaunchUrl(appUri)) {
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (_) {
          // 应用未安装或无法打开，继续尝试网页
        }
      }

      // 降级到网页
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
