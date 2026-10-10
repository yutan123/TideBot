import 'dart:io';
import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

/// 照片相册页面
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

class _PhotoAlbumPageState extends State<PhotoAlbumPage> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final db = DBManager();
    final photos = await db.queryPhotoMemories(widget.botId);
    if (mounted) {
      setState(() {
        _photos = photos;
        _loading = false;
      });
    }
  }

  void _showPhotoDetail(Map<String, dynamic> photo) {
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

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curvedAnim = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnim),
          child: FadeTransition(
            opacity: curvedAnim,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
                constraints: const BoxConstraints(maxWidth: 500),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 照片挂在上方
                      Hero(
                        tag: 'photo_$photoId',
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 400),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 液态玻璃描述卡片
                      FrostCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textStrong,
                                    fontFamily: 'TideFont',
                                  ),
                                ),
                                BouncyTap(
                                  onTap: () => _editDescription(photoId, description),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
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
                            const SizedBox(height: 16),
                            Text(
                              description.isEmpty
                                  ? sender == 'user'
                                      ? '这是你发给${widget.botName}的照片'
                                      : '${widget.botName}发给你的照片'
                                  : description,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: theme.textStrong,
                                fontFamily: 'TideFont',
                              ),
                            ),
                            if (description.isEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                '正在生成回忆描述...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.textFaint,
                                  fontFamily: 'TideFont',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editDescription(String photoId, String currentDescription) async {
    final theme = TideTheme.of(context);
    final controller = TextEditingController(text: currentDescription);
    
    Navigator.pop(context); // 先关闭详情弹窗

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${widget.botName}的相册',
          style: const TextStyle(fontFamily: 'TideFont'),
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
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    final imagePath = photo['image_path']?.toString() ?? '';
                    final photoId = photo['id']?.toString() ?? '';

                    if (imagePath.isEmpty) return const SizedBox.shrink();

                    return BouncyTap(
                      onTap: () => _showPhotoDetail(photo),
                      child: Hero(
                        tag: 'photo_$photoId',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
