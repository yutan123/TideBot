import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';
import 'ui_components.dart';

/// 精简紧凑的照片相册页面 - 时间轴风格
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

  void _onScroll() {}

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
        barrierColor: Colors.black.withOpacity(0.9),
        pageBuilder: (context, anim1, anim2) {
          return _PhotoDetailPage(
            imagePath: imagePath,
            description: description,
            dateStr: dateStr,
            photoId: photoId,
            sender: sender,
            botName: widget.botName,
            onDescriptionUpdated: () => _loadPhotos(),
          );
        },
      ),
    );
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
                        '还没有照片',
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
                    padding: const EdgeInsets.fromLTRB(24, 100, 24, 40),
                    itemCount: _photos.length,
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      final imagePath = photo['image_path']?.toString() ?? '';
                      final photoId = photo['id']?.toString() ?? '';
                      final timestamp = photo['timestamp'] as int?;

                      if (imagePath.isEmpty || !File(imagePath).existsSync()) {
                        return const SizedBox.shrink();
                      }

                      final date = timestamp != null
                          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                          : DateTime.now();
                      final dateStr =
                          '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                      final showConnector = index < _photos.length - 1;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.primary.withOpacity(0.3),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              if (showConnector)
                                Container(
                                  width: 2,
                                  height: 140,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        theme.primary.withOpacity(0.5),
                                        theme.primary.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: BouncyTap(
                                onTap: () => _showPhotoDetail(photo, index),
                                child: Hero(
                                  tag: 'photo_$photoId',
                                  child: FrostCard(
                                    liquid: true,
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: AspectRatio(
                                            aspectRatio: 4 / 3,
                                            child: Image.file(
                                              File(imagePath),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.textFaint,
                                            fontFamily: 'TideFont',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

class _PhotoDetailPage extends StatefulWidget {
  final String imagePath;
  final String description;
  final String dateStr;
  final String photoId;
  final String sender;
  final String botName;
  final VoidCallback onDescriptionUpdated;

  const _PhotoDetailPage({
    required this.imagePath,
    required this.description,
    required this.dateStr,
    required this.photoId,
    required this.sender,
    required this.botName,
    required this.onDescriptionUpdated,
  });

  @override
  State<_PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<_PhotoDetailPage> {
  late TextEditingController _controller;
  bool _isEditing = false;
  late String _currentDescription;

  @override
  void initState() {
    super.initState();
    _currentDescription = widget.description;
    _controller = TextEditingController(text: _currentDescription);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveDescription() async {
    final newText = _controller.text.trim();
    if (newText == _currentDescription) {
      setState(() => _isEditing = false);
      return;
    }

    final db = DBManager();
    await db.updatePhotoDescription(widget.photoId, newText);
    setState(() {
      _currentDescription = newText;
      _isEditing = false;
    });
    widget.onDescriptionUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 32,
                maxHeight: MediaQuery.of(context).size.height - 120,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.glass.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.border.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.dateStr,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textStrong,
                                    fontFamily: 'TideFont',
                                  ),
                                ),
                                BouncyTap(
                                  onTap: () {
                                    if (_isEditing) {
                                      _saveDescription();
                                    } else {
                                      setState(() => _isEditing = true);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isEditing
                                              ? Icons.check_rounded
                                              : Icons.edit_rounded,
                                          size: 16,
                                          color: theme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isEditing ? '保存' : '编辑',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: theme.primary,
                                            fontFamily: 'TideFont',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _isEditing
                                ? TextField(
                                    controller: _controller,
                                    maxLines: 5,
                                    autofocus: true,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                      color: theme.textStrong,
                                      fontFamily: 'TideFont',
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '写下这张照片的回忆...',
                                      hintStyle:
                                          TextStyle(color: theme.textFaint),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide:
                                            BorderSide(color: theme.divider),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: theme.primary, width: 2),
                                      ),
                                      contentPadding: const EdgeInsets.all(12),
                                    ),
                                  )
                                : Text(
                                    _currentDescription.isEmpty
                                        ? widget.sender == 'user'
                                            ? '你发给${widget.botName}的照片'
                                            : '${widget.botName}发给你的照片'
                                        : _currentDescription,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                      color: _currentDescription.isEmpty
                                          ? theme.textFaint
                                          : theme.textStrong,
                                      fontFamily: 'TideFont',
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
    );
  }
}
