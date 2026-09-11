import 'dart:convert';
import 'package:flutter/material.dart';
import 'db.dart';
import 'theme.dart';

class WorldBookDetailPage extends StatefulWidget {
  final String botId;
  final String botName;

  const WorldBookDetailPage({
    super.key,
    required this.botId,
    required this.botName,
  });

  @override
  State<WorldBookDetailPage> createState() => _WorldBookDetailPageState();
}

class _WorldBookDetailPageState extends State<WorldBookDetailPage> {
  late DBManager db;
  List<Map<String, dynamic>> worldBookEntries = [];
  List<Map<String, dynamic>> filteredEntries = [];
  String searchQuery = '';
  String selectedCategory = '全部';
  final categories = ['全部', '自我认知', '用户认知', '关系', '记忆', '日程', '事件'];

  @override
  void initState() {
    super.initState();
    db = DBManager();
    _loadWorldBook();
  }

  Future<void> _loadWorldBook() async {
    final entries = await db.queryMemories(widget.botId);
    setState(() {
      worldBookEntries = entries
          .where((e) => e['keys'] != null && e['keys'].toString().isNotEmpty)
          .toList();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = worldBookEntries;

    if (selectedCategory != '全部') {
      filtered = filtered.where((e) {
        final category = e['category'] as String?;
        return category == selectedCategory;
      }).toList();
    }

    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((e) {
        final title = (e['title'] as String?) ?? '';
        final content = (e['content'] as String?) ?? '';
        final keysStr = e['keys'].toString();
        return title.contains(searchQuery) ||
            content.contains(searchQuery) ||
            keysStr.contains(searchQuery);
      }).toList();
    }

    setState(() {
      filteredEntries = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);

    return Scaffold(
      backgroundColor: theme.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: theme.textStrong,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${widget.botName}的世界',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.textStrong,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 搜索框
                  Container(
                    decoration: BoxDecoration(
                      color: theme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      onChanged: (value) {
                        searchQuery = value;
                        _applyFilters();
                      },
                      decoration: InputDecoration(
                        hintText: '搜索记忆...',
                        hintStyle: TextStyle(color: theme.textFaint),
                        prefixIcon: Icon(
                          Icons.search,
                          color: theme.textWeak,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      style: TextStyle(color: theme.textStrong),
                    ),
                  ),
                ],
              ),
            ),
            // 分类标签
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isSelected = selectedCategory == category;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedCategory = category;
                        _applyFilters();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? theme.primary : theme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          category,
                          style: TextStyle(
                            color: isSelected ? Colors.white : theme.textWeak,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // 世界书条目列表
            Expanded(
              child: filteredEntries.isEmpty
                  ? Center(
                      child: Text(
                        '暂无记忆',
                        style: TextStyle(color: theme.textWeak, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredEntries.length,
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        return _buildEntryCard(entry, theme);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, TideTheme theme) {
    final title = entry['title'] as String? ?? '未命名';
    final content = entry['content'] as String? ?? '';
    final priority = entry['priority'] as int? ?? 50;
    final keys = _parseKeys(entry['keys']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textStrong,
                    ),
                  ),
                ),
                if (priority > 50)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '★ $priority',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textWeak,
                  height: 1.5,
                ),
              ),
            ],
            if (keys.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keys.take(3).map((key) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      key,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (keys.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '+${keys.length - 3} 更多',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textFaint,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _parseKeys(dynamic keysData) {
    if (keysData == null) return [];
    try {
      if (keysData is String) {
        final decoded = jsonDecode(keysData);
        if (decoded is List) {
          return decoded.cast<String>();
        }
      } else if (keysData is List) {
        return keysData.cast<String>();
      }
    } catch (_) {}
    return [];
  }
}
