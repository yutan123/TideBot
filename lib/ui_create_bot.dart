import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:path_provider/path_provider.dart';
import 'db.dart';
import 'ui_components.dart';

class CreateBotPage extends StatefulWidget {
  final Map<String, dynamic>? editBot;
  const CreateBotPage({Key? key, this.editBot}) : super(key: key);
  @override State<CreateBotPage> createState() => _CreateBotPageState();
}

class _CreateBotPageState extends State<CreateBotPage> {
  final _nameC = TextEditingController();
  final _promptC = TextEditingController();
  final _styleC = TextEditingController();
  String _avatar = '';
  bool get _isEdit => widget.editBot != null;

  @override void initState() {
    super.initState();
    if (_isEdit) {
      _nameC.text = widget.editBot!['name'] ?? '';
      _promptC.text = widget.editBot!['desc'] ?? '';
      _styleC.text = widget.editBot!['prompt'] ?? '';
      _avatar = widget.editBot!['avatar'] ?? '';
    }
  }
  @override void dispose() { _nameC.dispose(); _promptC.dispose(); _styleC.dispose(); super.dispose(); }

  void _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名字不能为空', style: TextStyle(fontFamily: 'TideFont')), behavior: SnackBarBehavior.floating));
      return;
    }
    final basePrompt = _styleC.text.trim();
    final Map<String, dynamic> data = {
      'name': name, 'desc': _promptC.text.trim(),
      'prompt': basePrompt.isNotEmpty ? '$basePrompt\n\n【输出格式】每条回复最前面用方括号标明心情，如：[开心] [难过] [生气] [平静] [期待]' : '【输出格式】每条回复最前面用方括号标明心情，如：[开心] [难过] [生气] [平静] [期待]',
      'avatar': _avatar,
    };
    try {
      if (_isEdit) {
        data['id'] = widget.editBot!['id'];
        await DBManager().updateBot(data['id'] as String, data);
      } else {
        data['id'] = 'bot_${DateTime.now().millisecondsSinceEpoch}';
        data['created_at'] = DateTime.now().millisecondsSinceEpoch;
        await DBManager().insertBot(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e', style: const TextStyle(fontFamily: 'TideFont')), behavior: SnackBarBehavior.floating));
    }
  }

  void _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512);
      if (img != null) {
        String path = img.path;
        if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
          try {
            final converted = await HeifConverter.convert(path);
            if (converted != null) path = converted;
          } catch (_) {}
        }
        final dir = await getApplicationDocumentsDirectory();
        final dest = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(path).copy(dest);
        setState(() => _avatar = dest);
      }
    } catch (_) {}
  }

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.65), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.5), width: 0.5)), child: TextField(controller: ctrl, maxLines: maxLines, style: const TextStyle(fontSize: 15, fontFamily: 'TideFont'), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontFamily: 'TideFont'), contentPadding: const EdgeInsets.all(16), border: InputBorder.none)))));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(title: Text(_isEdit ? '编辑机器人' : '创建机器人', style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'TideFont', fontSize: 18)), centerTitle: true, leading: GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.arrow_back_ios_rounded, size: 20))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('名字'), const SizedBox(height: 6), _field(_nameC, '给机器人取个名字'),
        const SizedBox(height: 20),
        _label('人格设定'), const SizedBox(height: 6), _field(_promptC, '简要描述机器人的性格和背景', maxLines: 3),
        const SizedBox(height: 20),
        _label('说话方式'), const SizedBox(height: 6), _field(_styleC, '详细描述说话风格、用词习惯等', maxLines: 4),
        const SizedBox(height: 20),
        _label('头像（可选）'), const SizedBox(height: 6),
        GestureDetector(onTap: _pickAvatar, child: Container(width: 72, height: 72, decoration: BoxDecoration(borderRadius: BorderRadius.circular(36), color: const Color(0xFFE8E8F0)), child: _avatar.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(36), child: Image.file(File(_avatar), fit: BoxFit.cover)) : const Center(child: Icon(Icons.add_a_photo_rounded, color: Color(0xFF8E8E93), size: 26)))),
        const SizedBox(height: 28),
        BouncyTap(onTap: _save, child: SizedBox(width: double.infinity, height: 48, child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: LinearGradient(colors: [TideTheme.of(context).primary, TideTheme.of(context).primaryLight]), boxShadow: [BoxShadow(color: TideTheme.of(context).primary.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))]), child: Center(child: Text(_isEdit ? '保存修改' : '创建', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'TideFont')))))),
      ])),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3C3C43), fontFamily: 'TideFont'));
}
