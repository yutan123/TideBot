import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'global_notice.dart';

class CodeCard extends StatefulWidget {
  final String code;
  final String language;
  final bool isUser;

  const CodeCard({
    super.key,
    required this.code,
    required this.language,
    required this.isUser,
  });

  @override
  State<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<CodeCard> {
  bool _showPreview = false;

  bool get _supportsPreview => widget.language.toLowerCase() == 'html';

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isUser
            ? theme.primary.withValues(alpha: 0.15)
            : theme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isUser
              ? theme.primary.withValues(alpha: 0.3)
              : theme.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isUser
                  ? theme.primary.withValues(alpha: 0.08)
                  : theme.surface.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // 语言标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.language.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.primary,
                      fontFamily: 'TideFont',
                    ),
                  ),
                ),
                const Spacer(),
                // 切换按钮（仅 HTML 显示）
                if (_supportsPreview) ...[
                  GestureDetector(
                    onTap: () => setState(() => _showPreview = !_showPreview),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _showPreview
                            ? theme.primary.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.primary.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showPreview
                                ? Icons.code_rounded
                                : Icons.web_rounded,
                            size: 14,
                            color: theme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showPreview ? '代码' : '预览',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.primary,
                              fontFamily: 'TideFont',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // 复制按钮
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    GlobalNotice.show('已复制到剪贴板');
                  },
                  child: Icon(
                    Icons.content_copy_rounded,
                    size: 16,
                    color: theme.textWeak,
                  ),
                ),
                const SizedBox(width: 8),
                // 保存按钮
                GestureDetector(
                  onTap: () => _saveFile(),
                  child: Icon(
                    Icons.save_alt_rounded,
                    size: 16,
                    color: theme.textWeak,
                  ),
                ),
              ],
            ),
          ),
          // 代码/预览内容
          if (_showPreview && _supportsPreview)
            GestureDetector(
              onTap: () => _showFullscreenPreview(),
              child: Container(
                height: 200,
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: _buildHtmlPreview(),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Courier',
                    color: theme.textStrong,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHtmlPreview() {
    return FutureBuilder(
      future: _prepareWebViewController(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.data == null) {
          return Container(
            color: Colors.white,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return WebViewWidget(controller: snapshot.data!);
      },
    );
  }

  Future<WebViewController> _prepareWebViewController() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF));
    await controller.loadHtmlString(widget.code);
    return controller;
  }

  void _showFullscreenPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title:
                const Text('HTML 预览', style: TextStyle(fontFamily: 'TideFont')),
            actions: [
              IconButton(
                icon: const Icon(Icons.content_copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  GlobalNotice.show('已复制到剪贴板');
                },
              ),
              IconButton(
                icon: const Icon(Icons.save_alt_rounded),
                onPressed: () => _saveFile(),
              ),
            ],
          ),
          body: _buildHtmlPreview(),
        ),
      ),
    );
  }

  Future<void> _saveFile() async {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        GlobalNotice.show('无法访问下载目录');
        return;
      }

      final ext = _getFileExtension(widget.language);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final basename =
          widget.language.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final filename = '${basename}_$timestamp.$ext';
      final file = File('${downloadDir.path}/$filename');

      await file.writeAsString(widget.code);
      GlobalNotice.show('已保存到 ${file.path}');
    } catch (e) {
      GlobalNotice.show('保存失败：$e');
    }
  }

  String _getFileExtension(String language) {
    final lang = language.toLowerCase();
    switch (lang) {
      case 'javascript':
      case 'js':
        return 'js';
      case 'typescript':
      case 'ts':
        return 'ts';
      case 'python':
      case 'py':
        return 'py';
      case 'java':
        return 'java';
      case 'dart':
        return 'dart';
      case 'html':
        return 'html';
      case 'css':
        return 'css';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'markdown':
      case 'md':
        return 'md';
      case 'cpp':
      case 'c++':
        return 'cpp';
      case 'c':
        return 'c';
      case 'rust':
      case 'rs':
        return 'rs';
      case 'go':
        return 'go';
      case 'kotlin':
      case 'kt':
        return 'kt';
      case 'swift':
        return 'swift';
      case 'xml':
        return 'xml';
      case 'sql':
        return 'sql';
      case 'bash':
      case 'sh':
      case 'shell':
        return 'sh';
      default:
        return 'txt';
    }
  }
}
