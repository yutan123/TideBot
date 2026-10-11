import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

/// 重新设计的照片相册页面 - 时间轴风格
class PhotoAlbumPage extends StatefulWidget {
  final String botId;
  final String botName;

  const PhotoAlbumPage({
    super.key,
    required this.botId,
    required this.botName,
  });

  @override
  State<PhotoAlbumPage> createState() => _PhotoAlbumPageState();
}

class _PhotoAlbumPageState extends State<PhotoAlbumPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadPhotos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 滚动视差效果的触发器（可扩展）
  }

  Future<void> _loadPhotos() async {
    final db = DBManager();
    final photos = await db.queryPhotoMemories(widget.botId);
    if (mounted) {
      setState(() {
        _photos = photos;
        _loading = false;
      });
      _fadeController.forward();
    }
  }

  void _showPhotoDetail(Map<String, dynamic> photo, int index) {
    final theme = TideTheme.of(context);
    final imagePath = photo['image_path']?.toString() ?? '';
    final description = photo['description']?.toString() ?? '';
    final timestamp = photo['timestamp'] as int?;
    final sender = photo['sender']?.toString() ?? '';
    final photoId = photo['id']?.toString() ?? '';

    if (imagePath.isEmpty) return;

    final date = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    final dateStr = '${date.year}年${date.month}月${date.day}日';

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.85),
        pageBuilder: (context, anim1, anim2) {
          return FadeTransition(
            opacity: anim1,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, // 阻止点击照片关闭
                    child: Hero(
                      tag: 'photo_$photoId',
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 48,
                          maxHeight: MediaQuery.of(context).size.height - 200,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 可缩放的照片
                            Flexible(
                              child: InteractiveViewer(
                                minScale: 0.5,
                                maxScale: 4.0,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.file(
                                    File(imagePath),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 描述卡片
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: theme.glass.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.border.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: theme.textStrong,
                                              fontFamily: 'TideFont',
                                            ),
                                          ),
                                          BouncyTap(
                                            onTap: () {
                                              Navigator.pop(context);
                                              _editDescription(
                                                  photoId, description);
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: theme.primary
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.edit_rounded,
                                                size: 18,
                                                color: theme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        description.isEmpty
                                            ? sender == 'user'
                                                ? '你发给${widget.botName}的照片'
                                                : '${widget.botName}发给你的照片'
                                            : description,
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.6,
                                          color: theme.textStrong,
                                          fontFamily: 'TideFont',
                                        ),
                                      ),
                                      if (description.isEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            '正在生成回忆描述...',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: theme.textFaint,
                                              fontFamily: 'TideFont',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editDescription(
      String photoId, String currentDescription) async {
    final theme = TideTheme.of(context);
    final controller = TextEditingController(text: currentDescription);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '编辑描述',
          style: TextStyle(
            fontFamily: 'TideFont',
            color: theme.textStrong,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: TextStyle(
            fontFamily: 'TideFont',
            color: theme.textStrong,
          ),
          decoration: InputDecoration(
            hintText: '写下这张照片的回忆...',
            hintStyle: TextStyle(color: theme.textFaint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                fontFamily: 'TideFont',
                color: theme.textWeak,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(
              '保存',
              style: TextStyle(
                fontFamily: 'TideFont',
                color: theme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (result != null && result != currentDescription) {
      final db = DBManager();
      await db.updatePhotoDescription(photoId, result);
      await _loadPhotos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);

    return Scaffold(
      backgroundColor: theme.pageBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BouncyTap(
          onTap: () => Navigator.pop(context),
          child:
              Icon(Icons.arrow_back_ios_new_rounded, color: theme.textStrong),
        ),
        title: Text(
          '${widget.botName}的相册',
          style: const TextStyle(fontFamily: 'TideFont'),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: theme.surface.withOpacity(0.7),
            ),
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primary))
          : _photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: theme.textFaint,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '还没有照片回忆',
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.textWeak,
                          fontFamily: 'TideFont',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '发送照片后会自动记录',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textFaint,
                          fontFamily: 'TideFont',
                        ),
                      ),
                    ],
                  ),
                )
              : FadeTransition(
                  opacity: _fadeController,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 100, 20, 40),
                    itemCount: _photos.length,
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      final imagePath = photo['image_path']?.toString() ?? '';
                      final photoId = photo['id']?.toString() ?? '';
                      final timestamp = photo['timestamp'] as int?;
                      final description =
                          photo['description']?.toString() ?? '';

                      if (imagePath.isEmpty || !File(imagePath).existsSync()) {
                        return const SizedBox.shrink();
                      }

                      final date = timestamp != null
                          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                          : DateTime.now();
                      final dateStr =
                          '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                      // 交错卡片布局
                      final isEven = index.isEven;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: 20,
                          left: isEven ? 0 : 40,
                          right: isEven ? 40 : 0,
                        ),
                        child: BouncyTap(
                          onTap: () => _showPhotoDetail(photo, index),
                          child: Hero(
                            tag: 'photo_$photoId',
                            child: FrostCard(
                              liquid: true,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 照片
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: AspectRatio(
                                      aspectRatio: 4 / 3,
                                      child: Image.file(
                                        File(imagePath),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // 日期
                                  Text(
                                    dateStr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.textFaint,
                                      fontFamily: 'TideFont',
                                    ),
                                  ),
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      description.length > 60
                                          ? '${description.substring(0, 60)}...'
                                          : description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.5,
                                        color: theme.textStrong,
                                        fontFamily: 'TideFont',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
