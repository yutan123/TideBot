import 'package:flutter/material.dart';

import 'db.dart';
import 'theme.dart';

class MemoryManagerPage extends StatefulWidget {
  final String botId;
  final String botName;
  const MemoryManagerPage(
      {super.key, required this.botId, required this.botName});
  @override
  State<MemoryManagerPage> createState() => _MemoryManagerPageState();
}

class _MemoryManagerPageState extends State<MemoryManagerPage> {
  List<Map<String, dynamic>> _items = [];
  String _type = 'long';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DBManager().queryMemories(widget.botId, type: _type);
    if (mounted) setState(() => _items = data);
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final title = TextEditingController(text: item?['title']?.toString() ?? '');
    final content =
        TextEditingController(text: item?['content']?.toString() ?? '');
    final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(item == null ? '添加${_label(_type)}' : '编辑记忆',
                  style: const TextStyle(fontFamily: 'TideFont')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: '标题')),
                const SizedBox(height: 10),
                TextField(
                    controller: content,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: '内容')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('保存'))
              ],
            ));
    if (result == true && content.text.trim().isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (item == null) {
        await DBManager().insertMemory({
          'id': 'mem_$now',
          'bot_id': widget.botId,
          'title': title.text.trim(),
          'type': _type,
          'content': content.text.trim(),
          'timestamp': now
        });
      } else {
        await DBManager().updateMemory(item['id'].toString(), {
          'title': title.text.trim(),
          'content': content.text.trim(),
          'type': _type,
          'timestamp': now
        });
      }
      await _load();
    }
    title.dispose();
    content.dispose();
  }

  String _label(String type) => type == 'long'
      ? '长期记忆'
      : type == 'medium'
          ? '中期记忆'
          : '短期记忆';
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
          title: Text('${widget.botName} 的记忆',
              style: const TextStyle(fontFamily: 'TideFont')),
          actions: [
            IconButton(
                onPressed: () => _edit(), icon: const Icon(Icons.add_rounded))
          ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'long', label: Text('长期')),
                ButtonSegment(value: 'medium', label: Text('中期')),
                ButtonSegment(value: 'short', label: Text('短期'))
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() => _type = value.first);
                _load();
              },
            )),
        Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text('暂无${_label(_type)}',
                        style: TextStyle(
                            color: theme.textWeak, fontFamily: 'TideFont')))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: _items.length,
                    itemBuilder: (_, index) {
                      final item = _items[index];
                      return Card(
                          child: ListTile(
                        title: Text(
                            item['title']?.toString().isEmpty == false
                                ? item['title'].toString()
                                : _label(_type),
                            style: const TextStyle(fontFamily: 'TideFont')),
                        subtitle: Text(item['content']?.toString() ?? '',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'TideFont')),
                        onTap: () => _edit(item),
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              await DBManager()
                                  .deleteMemory(item['id'].toString());
                              _load();
                            }),
                      ));
                    },
                  )),
      ]),
    );
  }
}
