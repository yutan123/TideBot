import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'android_selection_menu.dart';
import 'global_notice.dart';
import 'open_source_notices_data.dart';
import 'theme.dart';

/// Bundled license texts are available without contacting pub.dev or GitHub.
class OpenSourceNoticesPage extends StatefulWidget {
  const OpenSourceNoticesPage({super.key});

  @override
  State<OpenSourceNoticesPage> createState() => _OpenSourceNoticesPageState();
}

class _OpenSourceNoticesPageState extends State<OpenSourceNoticesPage> {
  late Future<List<Map<String, dynamic>>> _notices;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notices = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final source = await rootBundle.loadString('assets/legal/notices.json');
    return compute(decodeOpenSourceNotices, source);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('开源许可与第三方声明'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Copyright (C) 2025-2026 yutan123.',
                        style: TextStyle(
                            color: theme.textStrong,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                        'TideBot 原创内容采用 AGPL-3.0-only。第三方组件保留各自的版权和许可，已收录的许可原文可在下方离线查看。',
                        style: TextStyle(color: theme.textWeak, height: 1.5)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      contextMenuBuilder: androidTextContextMenu,
                      style: TextStyle(color: theme.textStrong),
                      cursorColor: theme.primary,
                      decoration: InputDecoration(
                        hintText: '搜索组件名称或许可证',
                        hintStyle: TextStyle(color: theme.textFaint),
                        prefixIcon:
                            Icon(Icons.search_rounded, color: theme.textWeak),
                        filled: true,
                        fillColor: theme.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ]),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _notices,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _notices = _load()),
                        style: TextButton.styleFrom(
                            foregroundColor: theme.primary),
                        child: const Text('声明读取失败，点击重试'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return Center(
                        child: CircularProgressIndicator(color: theme.primary));
                  }
                  final query = _search.text.trim().toLowerCase();
                  final entries = snapshot.data!
                      .where((item) =>
                          '${item['name']} ${item['license']} ${item['category']}'
                              .toLowerCase()
                              .contains(query))
                      .toList();
                  if (entries.isEmpty) {
                    return Center(
                        child: Text('没有匹配的声明',
                            style: TextStyle(color: theme.textWeak)));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      return Material(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          title: Text(item['name'] as String,
                              style: TextStyle(
                                  color: theme.textStrong,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${item['category']} · ${item['version']}\n${item['license']}',
                              style: TextStyle(
                                  color: theme.textWeak,
                                  height: 1.5,
                                  fontSize: 12)),
                          trailing: Icon(Icons.chevron_right_rounded,
                              color: theme.textFaint),
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(
                            builder: (_) => _NoticeDetailPage(item: item),
                          )),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NoticeDetailPage extends StatelessWidget {
  const _NoticeDetailPage({required this.item});
  final Map<String, dynamic> item;

  Future<void> _openSource() async {
    final uri = Uri.tryParse(item['source'] as String);
    if (uri == null || uri.scheme != 'https') return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep the bundled license available if no browser can open the source.
    }
    GlobalNotice.show('无法打开来源链接，请稍后重试');
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final documents = (item['documents'] as List)
        .map((document) => Map<String, dynamic>.from(document as Map));
    // Long engine and native license collections are laid out in paragraphs,
    // instead of one huge text layout or an Android platform text view.
    final paragraphs = <({String text, bool heading})>[
      (text: item['license'] as String, heading: true),
      (text: item['description'] as String, heading: false),
      for (final document in documents) ...[
        (text: document['name'] as String, heading: true),
        for (final paragraph
            in (document['text'] as String).split(RegExp(r'\n\s*\n')))
          if (paragraph.trim().isNotEmpty) (text: paragraph, heading: false),
      ],
    ];
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(item['name'] as String),
          backgroundColor: Colors.transparent,
          actions: [
            if ((item['source'] as String).isNotEmpty)
              IconButton(
                  tooltip: '查看上游来源',
                  onPressed: _openSource,
                  icon: const Icon(Icons.open_in_new_rounded)),
          ],
        ),
        body: SafeArea(
          child: SelectionArea(
            contextMenuBuilder: androidSelectionContextMenu,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: paragraphs.length,
              itemBuilder: (_, index) {
                final paragraph = paragraphs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(paragraph.text,
                      style: TextStyle(
                        color: paragraph.heading
                            ? theme.textStrong
                            : theme.textWeak,
                        fontSize: paragraph.heading ? 16 : 13,
                        fontWeight: paragraph.heading
                            ? FontWeight.w600
                            : FontWeight.normal,
                        height: 1.6,
                      )),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
