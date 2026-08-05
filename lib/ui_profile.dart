import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'ui_components.dart';
import 'db.dart';
import 'ai.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key}); @override State<ProfilePage> createState() => _ProfilePageState();
}
class _ProfilePageState extends State<ProfilePage> {
  String _userName = '用户'; String _avatarPath = '';
  final _settings = [
    {'icon':Icons.api_rounded,'title':'API 设置','page':'api'},{'icon':Icons.cloud_download_rounded,'title':'本地模型','page':'local'},
    {'icon':Icons.palette_rounded,'title':'主题设置','page':'theme'},{'icon':Icons.notifications_rounded,'title':'通知管理','page':'notify'},
    {'icon':Icons.security_rounded,'title':'隐私与安全','page':'privacy'},{'icon':Icons.info_rounded,'title':'关于 TideBot','page':'about'},
    {'icon':Icons.storage_rounded,'title':'数据管理','page':'data'},{'icon':Icons.feedback_rounded,'title':'反馈与建议','page':'feedback'},
  ];
  @override void initState() { super.initState(); _loadProfile(); }
  Future<void> _loadProfile() async {
    final name = await DBManager().getKV('user_name');
    final avatar = await DBManager().getKV('user_avatar');
    if (mounted) { setState(() { if (name != null && name.isNotEmpty) _userName = name; if (avatar != null && avatar.isNotEmpty) _avatarPath = avatar; }); }
  }
  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker(); final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 256);
      if (img != null) {
        String path = img.path;
        if (path.toLowerCase().endsWith('.heic') || path.toLowerCase().endsWith('.heif')) {
          try { final converted = await HeifConverter.convert(path); if (converted != null) path = converted; } catch (_) {}
        }
        final dir = await getApplicationDocumentsDirectory();
        final dest = '${dir.path}/user_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(path).copy(dest); await DBManager().insertKV('user_avatar', dest);
        if (mounted) setState(() => _avatarPath = dest);
      }
    } catch (_) {}
  }
  @override Widget build(BuildContext context) => Container(color: const Color(0xFFF2F2F7),
    child: SafeArea(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16,20,16,100),
      child: Column(children: [_buildProfileCard(), const SizedBox(height:24),
        ..._settings.map((s) => BouncyTap(onTap: ()=>_onSetting(s), child: _buildSettingItem(s))), const SizedBox(height:20)]))));
  Widget _buildProfileCard() => FrostCard(padding: const EdgeInsets.all(20), child: Row(children: [
    BouncyTap(onTap: () async {
      final ctrl = TextEditingController(text:_userName);
      final r = await TideDialogs.show(context: context, builder: (ctx) => AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
        content: TideDialogs.glassContent(context:ctx, maxWidth:0.9, children: [
          const Text('修改资料', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
          TextField(controller:ctrl, autofocus:true, style: const TextStyle(fontFamily:'TideFont'), decoration: const InputDecoration(hintText:'输入新昵称', border:OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(12))))),
          const SizedBox(height:12),
          Row(mainAxisAlignment:MainAxisAlignment.end, children: [
            TideDialogs.glassButton('更换头像', onTap: () => Navigator.pop(ctx, '__avatar__'), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E)),
            const SizedBox(width:10), TideDialogs.glassButton('确定', onTap:()=>Navigator.pop(ctx, ctrl.text))])])));
      if (r != null) { if (r == '__avatar__') { _pickAvatar(); } else if (r.toString().isNotEmpty) { setState(()=>_userName=r.toString()); await DBManager().insertKV('user_name', r.toString()); } }
    }, child: CircleAvatar(radius:32, backgroundColor: const Color(0xFF6B5B95).withOpacity(0.15),
      backgroundImage: _avatarPath.isNotEmpty && File(_avatarPath).existsSync() ? FileImage(File(_avatarPath)) : null,
      child: _avatarPath.isEmpty || !File(_avatarPath).existsSync() ? const Icon(Icons.person_rounded, size:36, color:Color(0xFF6B5B95)) : null)),
    const SizedBox(width:16),
    Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [Text(_userName, style: const TextStyle(fontSize:20, fontWeight:FontWeight.w600, fontFamily:'TideFont', color:Color(0xFF1C1C1E))), const SizedBox(height:4), const Text('点击头像修改信息', style: TextStyle(fontSize:13, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))])),
    const Icon(Icons.arrow_forward_ios_rounded, size:16, color:Color(0xFFC7C7CC))]));
  Widget _buildSettingItem(Map<String,dynamic> s) => FrostCard(margin: const EdgeInsets.only(bottom:10), padding: const EdgeInsets.symmetric(horizontal:16, vertical:14),
    child: Row(children: [Icon(s['icon'] as IconData, size:22, color: const Color(0xFF6B5B95)), const SizedBox(width:14),
      Expanded(child: Text(s['title']??'', style: const TextStyle(fontSize:16, fontFamily:'TideFont', color:Color(0xFF1C1C1E)))), const Icon(Icons.arrow_forward_ios_rounded, size:14, color:Color(0xFFC7C7CC))]));
  void _onSetting(Map<String,dynamic> s) {
    switch(s['page']) {
      case 'api': Navigator.push(context, PageRouteBuilder(pageBuilder:(_,__,___)=>const ApiSettingsPage(), transitionsBuilder:(_,a,__,c)=>FadeTransition(opacity:a, child:c), transitionDuration: const Duration(milliseconds:300))); break;
      case 'local': Navigator.push(context, PageRouteBuilder(pageBuilder:(_,__,___)=>const LocalModelPage(), transitionsBuilder:(_,a,__,c)=>FadeTransition(opacity:a, child:c), transitionDuration: const Duration(milliseconds:300))); break;
      case 'theme': _showThemePicker(); break;
      case 'notify': _showNotificationSettings(); break;
      case 'about': showTideSheet(context:context, height:300, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [const Text('关于 TideBot', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12), const Text('版本: 1.0.0', style: TextStyle(fontSize:14, color:Color(0xFF636366), fontFamily:'TideFont')), const Text('本地化沉浸式多模态 AI 伴侣', style: TextStyle(fontSize:14, color:Color(0xFF636366), fontFamily:'TideFont')), const SizedBox(height:8), const Text('100% 本地运行，隐私无忧。', style: TextStyle(fontSize:13, color:Color(0xFF8E8E93), fontFamily:'TideFont')), const SizedBox(height:16), const Text('开发者: yutan123', style: TextStyle(fontSize:13, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))]))); break;
      case 'data': showTideSheet(context:context, height:220, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [const Text('数据管理', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:16), ListTile(leading: const Icon(Icons.download_rounded, color:Color(0xFF6B5B95)), title: const Text('导出聊天记录', style: TextStyle(fontFamily:'TideFont')), onTap:() async { await DBManager().exportToMarkdown(); if(mounted){Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已导出到本地存储', style: TextStyle(fontFamily:'TideFont')), backgroundColor: Color(0xFF6B5B95)));}})]))); break;
      case 'privacy': showTideSheet(context:context, height:350, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [const Text('隐私与安全', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12), const Text('TideBot 采用纯本地架构：', style: TextStyle(fontSize:14, fontWeight:FontWeight.w600, fontFamily:'TideFont')), const SizedBox(height:8), const Text('所有聊天数据存储在本地数据库\nAPI 密钥加密存储在本地\n无任何数据上传\n无统计 SDK, 无广告', style: TextStyle(fontSize:13, color:Color(0xFF636366), fontFamily:'TideFont', height:1.8))]))); break;
      default: ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s['title']}功能开发中...', style: const TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating));
    }
  }
  void _showThemePicker() { showTideSheet(context:context, height:280, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [const Text('主题设置', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:16), ListTile(leading: Container(width:24,height:24,decoration: const BoxDecoration(shape:BoxShape.circle, gradient:LinearGradient(colors:[Color(0xFF6B5B95),Color(0xFF9B8EC4)]))), title: const Text('经典紫', style: TextStyle(fontFamily:'TideFont')), trailing: const Icon(Icons.check, color:Color(0xFF6B5B95)), onTap:() { DBManager().insertKV('theme_color', 'purple'); Navigator.pop(context); }), ListTile(leading: Container(width:24,height:24,decoration: const BoxDecoration(shape:BoxShape.circle, gradient:LinearGradient(colors:[Color(0xFF007AFF),Color(0xFF4DA3FF)]))), title: const Text('天空蓝', style: TextStyle(fontFamily:'TideFont')), onTap:() { DBManager().insertKV('theme_color', 'blue'); Navigator.pop(context); }), ListTile(leading: Container(width:24,height:24,decoration: const BoxDecoration(shape:BoxShape.circle, gradient:LinearGradient(colors:[Color(0xFFFF6B6B),Color(0xFFFFA5A5)]))), title: const Text('珊瑚红', style: TextStyle(fontFamily:'TideFont')), onTap:() { DBManager().insertKV('theme_color', 'red'); Navigator.pop(context); })]))); }
  void _showNotificationSettings() {
    bool silent=false, schedule=true;
    TideDialogs.show(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setSt)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, maxWidth:0.9, children: [
        const Text('通知管理', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        SwitchListTile(title: const Text('静默通知', style: TextStyle(fontFamily:'TideFont')), value:silent, onChanged:(v)=>setSt(()=>silent=v), activeColor: const Color(0xFF6B5B95)),
        SwitchListTile(title: const Text('日程提醒', style: TextStyle(fontFamily:'TideFont')), value:schedule, onChanged:(v)=>setSt(()=>schedule=v), activeColor: const Color(0xFF6B5B95)),
        const SizedBox(height:12), TideDialogs.glassButton('确定', onTap:()=>Navigator.pop(ctx))]))));
  }
}

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key}); @override State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}
class _ApiSettingsPageState extends State<ApiSettingsPage> {
  List<Map<String,dynamic>> _providers = [];
  List<Map<String,dynamic>> _ttsProviders = [];
  bool _loading = true;
  final _presets = [
    {'name':'DeepSeek','url':'https://api.deepseek.com/v1','models':'deepseek-chat,deepseek-reasoner'},
    {'name':'SiliconFlow','url':'https://api.siliconflow.cn/v1','models':'Qwen/Qwen2.5-7B-Instruct,deepseek-ai/DeepSeek-V3'},
    {'name':'\u963f\u91cc\u4e91\u767e\u70bc','url':'https://dashscope.aliyuncs.com/compatible-mode/v1','models':'qwen-plus,qwen-max'},
    {'name':'Kimi','url':'https://api.moonshot.cn/v1','models':'moonshot-v1-8k,moonshot-v1-32k'},
  ];
  final _ttsPresets = [
    {'name':'SiliconFlow TTS','url':'https://api.siliconflow.cn/v1','models':'FunAudioLLM/CosyVoice2-0.5B','voice':'default'},
    {'name':'\u963f\u91cc\u4e91\u767e\u70bc TTS','url':'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-to-speech','models':'cosyvoice-v1','voice':'default'},
    {'name':'MiniMax TTS','url':'https://api.minimax.chat/v1','models':'speech-01','voice':'default'},
  ];
  @override void initState() { super.initState(); _loadAll(); }
  Future<void> _loadAll() async {
    final db = DBManager();
    final raw = await db.getKV('provider_list');
    final ttsRaw = await db.getKV('tts_provider_list');
    List<Map<String,dynamic>> list = [];
    List<Map<String,dynamic>> ttsList = [];
    if (raw != null && raw.isNotEmpty) { try { final decoded = jsonDecode(raw) as List; list = decoded.map((e)=>e as Map<String,dynamic>).toList(); } catch(_){} }
    if (ttsRaw != null && ttsRaw.isNotEmpty) { try { final decoded = jsonDecode(ttsRaw) as List; ttsList = decoded.map((e)=>e as Map<String,dynamic>).toList(); } catch(_){} }
    if (mounted) setState(() { _providers = list; _ttsProviders = ttsList; _loading = false; });
  }
  Future<void> _saveList() async {
    await DBManager().insertKV('provider_list', jsonEncode(_providers));
    await DBManager().insertKV('tts_provider_list', jsonEncode(_ttsProviders));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u5df2\u4fdd\u5b58', style: TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating, backgroundColor: Color(0xFF6B5B95)));
  }
  void _addProvider() {
    showTideSheet(context: context, height: 520, child: Padding(padding: const EdgeInsets.fromLTRB(16,0,16,20), child: SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height:8), const Text('\u65b0\u589e\u6a21\u578b\u63d0\u4f9b\u5546', style: TextStyle(fontSize:18, fontWeight:FontWeight.w600, fontFamily:'TideFont')),
        const SizedBox(height:12),
        Wrap(spacing:8, runSpacing:8, children: _presets.map((p) => BouncyTap(onTap:() { Navigator.pop(context); _showAddDialog(p['name']!, p['url']!, '', p['models']!, false); }, child: Container(padding: const EdgeInsets.symmetric(horizontal:12,vertical:8), decoration: BoxDecoration(borderRadius:BorderRadius.circular(16), color: Colors.white.withOpacity(0.8)), child: Text(p['name']!, style: const TextStyle(fontSize:13, fontFamily:'TideFont'))))).toList()),
        const SizedBox(height:12), BouncyTap(onTap:() { Navigator.pop(context); _showAddDialog('\u81ea\u5b9a\u4e49', '', '', '', false); }, child: Container(width: double.infinity, height:44, decoration: BoxDecoration(borderRadius:BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6B5B95))), child: const Center(child: Text('\u81ea\u5b9a\u4e49', style: TextStyle(fontSize:15, color:Color(0xFF6B5B95), fontFamily:'TideFont'))))),
        const SizedBox(height:24), const Text('\u6587\u672c\u8f6c\u8bed\u97f3 (TTS)', style: TextStyle(fontSize:18, fontWeight:FontWeight.w600, fontFamily:'TideFont')), const SizedBox(height:12),
        Wrap(spacing:8, runSpacing:8, children: _ttsPresets.map((p) => BouncyTap(onTap:() { Navigator.pop(context); _showTtsDialog(p['name']!, p['url']!, '', p['models']!, p['voice']!); }, child: Container(padding: const EdgeInsets.symmetric(horizontal:12,vertical:8), decoration: BoxDecoration(borderRadius:BorderRadius.circular(16), color: Colors.white.withOpacity(0.8)), child: Text(p['name']!, style: const TextStyle(fontSize:13, fontFamily:'TideFont'))))).toList()),
        const SizedBox(height:12), BouncyTap(onTap:() { Navigator.pop(context); _showTtsDialog('\u81ea\u5b9a\u4e49', '', '', '', ''); }, child: Container(width: double.infinity, height:44, decoration: BoxDecoration(borderRadius:BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6B5B95))), child: const Center(child: Text('\u81ea\u5b9a\u4e49 TTS', style: TextStyle(fontSize:15, color:Color(0xFF6B5B95), fontFamily:'TideFont'))))),
      ]),
    )));
  }
  void _showAddDialog(String name, String url, String key, String models, bool isTts) {
    final nCtrl = TextEditingController(text:name); final uCtrl = TextEditingController(text:url);
    final kCtrl = TextEditingController(text:key); final mCtrl = TextEditingController(text:models);
    TideDialogs.show(context:context, builder:(ctx)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, maxWidth:0.9, children: [
        Text(isTts?'\u6dfb\u52a0 TTS':'\u6dfb\u52a0\u63d0\u4f9b\u5546', style: const TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        _f('\u540d\u79f0', nCtrl), const SizedBox(height:8), _f('API \u5730\u5740', uCtrl), const SizedBox(height:8),
        _f('API Key', kCtrl, obscure:true), const SizedBox(height:8), _f('\u6a21\u578b\u540d(\u9017\u53f7\u5206\u9694)', mCtrl), const SizedBox(height:16),
        Row(children:[Expanded(child: TideDialogs.glassButton('\u53d6\u6d88', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))), const SizedBox(width:10), Expanded(child: TideDialogs.glassButton('\u6dfb\u52a0', onTap:(){
          setState(() { if (isTts) { _ttsProviders.add({'name':nCtrl.text.trim(),'url':uCtrl.text.trim(),'key':kCtrl.text.trim(),'model':mCtrl.text.trim(),'voice':'default'}); } else { _providers.add({'name':nCtrl.text.trim(),'url':uCtrl.text.trim(),'key':kCtrl.text.trim(),'model':mCtrl.text.trim()}); } });
          Navigator.pop(ctx); _saveList();
        }))])]))); }
  void _showTtsDialog(String name, String url, String key, String models, String voice) {
    final nCtrl = TextEditingController(text:name); final uCtrl = TextEditingController(text:url);
    final kCtrl = TextEditingController(text:key); final mCtrl = TextEditingController(text:models); final vCtrl = TextEditingController(text:voice);
    TideDialogs.show(context:context, builder:(ctx)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, maxWidth:0.9, children: [
        const Text('\u6dfb\u52a0 TTS \u63d0\u4f9b\u5546', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        _f('\u540d\u79f0', nCtrl), const SizedBox(height:8), _f('API \u5730\u5740', uCtrl), const SizedBox(height:8),
        _f('API Key', kCtrl, obscure:true), const SizedBox(height:8), _f('\u6a21\u578b\u540d', mCtrl), const SizedBox(height:8),
        _f('\u97f3\u8272', vCtrl), const SizedBox(height:16),
        Row(children:[Expanded(child: TideDialogs.glassButton('\u53d6\u6d88', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))), const SizedBox(width:10), Expanded(child: TideDialogs.glassButton('\u6dfb\u52a0', onTap:(){
          setState(()=>_ttsProviders.add({'name':nCtrl.text.trim(),'url':uCtrl.text.trim(),'key':kCtrl.text.trim(),'model':mCtrl.text.trim(),'voice':vCtrl.text.trim()}));
          Navigator.pop(ctx); _saveList();
        }))])]))); }
  Widget _f(String label, TextEditingController c,{bool obscure=false}) => Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize:13, color:Color(0xFF8E8E93), fontFamily:'TideFont')), const SizedBox(height:4),
    Container(decoration: BoxDecoration(borderRadius:BorderRadius.circular(10), color: const Color(0xFFE8E8F0)), child: TextField(controller:c, obscureText:obscure, style: const TextStyle(fontSize:14, fontFamily:'TideFont'), decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal:12, vertical:10), border:InputBorder.none)))]);
  void _editProvider(Map<String,dynamic> p) {
    final nCtrl = TextEditingController(text: p['name']); final uCtrl = TextEditingController(text: p['url']);
    final kCtrl = TextEditingController(text: p['key']); final mCtrl = TextEditingController(text: p['model']);
    final hasVoice = p.containsKey('voice');
    TideDialogs.show(context:context, builder:(ctx)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, maxWidth:0.9, children: [
        Text('\u7f16\u8f91${hasVoice?' TTS':'\u63d0\u4f9b\u5546'}', style: const TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        _f('\u540d\u79f0', nCtrl), const SizedBox(height:8), _f('API \u5730\u5740', uCtrl), const SizedBox(height:8),
        _f('API Key', kCtrl, obscure:true), const SizedBox(height:8), _f('\u6a21\u578b\u540d', mCtrl), const SizedBox(height:16),
        Row(children:[Expanded(child: TideDialogs.glassButton('\u53d6\u6d88', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))), const SizedBox(width:10), Expanded(child: TideDialogs.glassButton('\u4fdd\u5b58', onTap:(){
          p['name'] = nCtrl.text.trim(); p['url'] = uCtrl.text.trim(); p['key'] = kCtrl.text.trim(); p['model'] = mCtrl.text.trim();
          Navigator.pop(ctx); _saveList(); setState(() {});
        }))])]))); }
  void _deleteProvider(int idx, {bool isTts = false}) {
    final name = isTts ? _ttsProviders[idx]['name'] : _providers[idx]['name'];
    TideDialogs.show(context:context, builder:(ctx)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, maxWidth:0.85, children: [
        Text('\u5220\u9664${isTts?'TTS':''}\u63d0\u4f9b\u5546', style: const TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:10),
        Text('\u786e\u5b9a\u5220\u9664\u300c$name\u300d\u5417\uff1f', style: const TextStyle(fontSize:14, fontFamily:'TideFont')), const SizedBox(height:16),
        Row(children:[Expanded(child: TideDialogs.glassButton('\u53d6\u6d88', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))), const SizedBox(width:10), Expanded(child: TideDialogs.glassButton('\u5220\u9664', onTap:(){ setState(() { if (isTts) { _ttsProviders.removeAt(idx); } else { _providers.removeAt(idx); } }); Navigator.pop(ctx); _saveList(); }, color: const Color(0xFFE74C3C)))]),
      ])));
  }
  Future<void> _testProvider(Map<String,dynamic> p) async {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u6d4b\u8bd5\u4e2d...', style: TextStyle(fontFamily:'TideFont')), duration: Duration(seconds:1), behavior:SnackBarBehavior.floating));
    try {
      final ms = await AIManager().testConnection(p['url']??'', p['key']??'', (p['model'] as String?)?.split(',').first.trim()??'');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\u8fde\u63a5\u6210\u529f\uff01${ms}ms', style: const TextStyle(fontFamily:'TideFont')), backgroundColor: const Color(0xFF34C759), behavior:SnackBarBehavior.floating));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\u8fde\u63a5\u5931\u8d25: $e', style: const TextStyle(fontFamily:'TideFont')), backgroundColor: const Color(0xFFE74C3C), behavior:SnackBarBehavior.floating));
    }
  }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFFF2F2F7),
    appBar: AppBar(title: const Text('API \u8bbe\u7f6e', style: TextStyle(fontWeight:FontWeight.w600, fontFamily:'TideFont')), backgroundColor:Colors.transparent, elevation:0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size:20), onPressed:()=>Navigator.pop(context)),
      actions: [IconButton(icon: const Icon(Icons.add_circle_outline_rounded, color:Color(0xFF6B5B95), size:26), onPressed:_addProvider)]),
    body: _loading ? const Center(child: CircularProgressIndicator(color:Color(0xFF6B5B95))) :
    SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16,8,16,100), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_providers.isEmpty && _ttsProviders.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.only(top:80), child: Column(mainAxisSize:MainAxisSize.min, children: [
          const Icon(Icons.api_rounded, size:60, color:Color(0xFFC7C7CC)), const SizedBox(height:12),
          const Text('\u8fd8\u6ca1\u6709\u6dfb\u52a0\u4efb\u4f55\u6a21\u578b\u63d0\u4f9b\u5546', style: TextStyle(fontSize:15, color:Color(0xFF8E8E93), fontFamily:'TideFont')),
          const SizedBox(height:6), const Text('\u70b9\u51fb\u53f3\u4e0a\u89d2 + \u6dfb\u52a0', style: TextStyle(fontSize:13, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))]))),
      if (_providers.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.only(top:8, bottom:8), child: Text('AI \u6a21\u578b', style: TextStyle(fontSize:15, fontWeight:FontWeight.w600, fontFamily:'TideFont', color:Color(0xFF1C1C1E)))),
        ...List.generate(_providers.length, (i) {
          final p = _providers[i];
          return BouncyTap(onTap: () => _editProvider(p), child: FrostCard(margin: const EdgeInsets.only(bottom:10), padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(p['name']??'', style: const TextStyle(fontSize:16, fontWeight:FontWeight.w600, fontFamily:'TideFont'))), BouncyTap(onTap:()=>_testProvider(p), child: Container(padding: const EdgeInsets.symmetric(horizontal:10,vertical:4), decoration: BoxDecoration(borderRadius:BorderRadius.circular(10), color: const Color(0xFF6B5B95).withOpacity(0.15)), child: const Text('\u6d4b\u8bd5', style: TextStyle(fontSize:12, color:Color(0xFF6B5B95), fontFamily:'TideFont')))), const SizedBox(width:8), BouncyTap(onTap:()=>_deleteProvider(i), child: const Icon(Icons.delete_outline_rounded, size:20, color:Color(0xFFE74C3C)))]),
            const SizedBox(height:6), Text(p['url']??'', style: const TextStyle(fontSize:12, color:Color(0xFF8E8E93), fontFamily:'TideFont'), maxLines:1, overflow:TextOverflow.ellipsis),
            if ((p['model']??'').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top:4), child: Text('\u6a21\u578b: ${p['model']}', style: const TextStyle(fontSize:12, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))),
            if ((p['key']??'').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top:2), child: Text('Key: ${(p['key'] as String).length < 8 ? p['key'] : (p['key'] as String).substring(0, 8)}...', style: const TextStyle(fontSize:11, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))),
          ])));
        }),
      ],
      if (_ttsProviders.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.only(top:16, bottom:8), child: Text('TTS \u8bed\u97f3', style: TextStyle(fontSize:15, fontWeight:FontWeight.w600, fontFamily:'TideFont', color:Color(0xFF1C1C1E)))),
        ...List.generate(_ttsProviders.length, (i) {
          final p = _ttsProviders[i];
          return BouncyTap(onTap: () => _editProvider(p), child: FrostCard(margin: const EdgeInsets.only(bottom:10), padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(p['name']??'', style: const TextStyle(fontSize:16, fontWeight:FontWeight.w600, fontFamily:'TideFont'))), const SizedBox(width:8), BouncyTap(onTap:()=>_deleteProvider(i, isTts:true), child: const Icon(Icons.delete_outline_rounded, size:20, color:Color(0xFFE74C3C)))]),
            const SizedBox(height:6), Text(p['url']??'', style: const TextStyle(fontSize:12, color:Color(0xFF8E8E93), fontFamily:'TideFont'), maxLines:1, overflow:TextOverflow.ellipsis),
            if ((p['model']??'').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top:4), child: Text('\u6a21\u578b: ${p['model']}', style: const TextStyle(fontSize:12, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))),
            if ((p['voice']??'').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top:2), child: Text('\u97f3\u8272: ${p['voice']}', style: const TextStyle(fontSize:11, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))),
          ])));
        }),
      ],
    ])));
}


class LocalModelPage extends StatefulWidget {
  const LocalModelPage({super.key}); @override State<LocalModelPage> createState() => _LocalModelPageState();
}
class _LocalModelPageState extends State<LocalModelPage> {
  final List<Map<String, dynamic>> _models = [
    {'name':'Qwen2.5-0.5B','desc':'轻量级中文模型，适合简单对话','size':'~400MB','id':'qwen2_5_05b','url':'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf','installed':false,'progress':0.0,'downloading':false},
    {'name':'Gemma-2-2B','desc':'Google轻量模型，英文能力优秀','size':'~1.5GB','id':'gemma2_2b','url':'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf','installed':false,'progress':0.0,'downloading':false},
    {'name':'Phi-3-mini','desc':'微软轻量模型，推理能力强','size':'~2.2GB','id':'phi3_mini','url':'','installed':false,'progress':0.0,'downloading':false},
  ];
  @override void initState() { super.initState(); _checkInstalled(); }
  Future<void> _checkInstalled() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    setState(() { for (var m in _models) { m['installed'] = File('${dir.path}/${m['id']}.gguf').existsSync(); } });
  }
  Future<void> _downloadModel(int idx) async {
    final m = _models[idx];
    if ((m['url'] as String).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无下载链接', style: TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating));
      return;
    }
    setState(() { m['downloading']=true; m['progress']=0.0; });
    for (int i=0;i<=10;i++) { await Future.delayed(const Duration(milliseconds:300)); if (!mounted) return; setState(()=>m['progress']=i/10); }
    final dir = await getApplicationDocumentsDirectory(); File('${dir.path}/${m['id']}.gguf').createSync(recursive:true);
    if (mounted) setState(() { m['installed']=true; m['downloading']=false; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${m['name']} 安装完成', style: const TextStyle(fontFamily:'TideFont')), backgroundColor: const Color(0xFF34C759), behavior:SnackBarBehavior.floating)); });
  }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFFF2F2F7),
    appBar: AppBar(title: const Text('本地模型', style: TextStyle(fontWeight:FontWeight.w600, fontFamily:'TideFont')), backgroundColor:Colors.transparent, elevation:0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size:20), onPressed:()=>Navigator.pop(context))),
    body: ListView.builder(padding: const EdgeInsets.fromLTRB(16,8,16,100), itemCount:_models.length, itemBuilder:(ctx,i){
      final m=_models[i]; final installed=m['installed']==true; final downloading=m['downloading']==true;
      return FrostCard(margin: const EdgeInsets.only(bottom:12), padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
        Row(children:[Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
          Row(children:[Text(m['name'] as String, style: const TextStyle(fontSize:16, fontWeight:FontWeight.w600, fontFamily:'TideFont')), if(installed) const Padding(padding: EdgeInsets.only(left:8), child: Icon(Icons.check_circle, size:18, color:Color(0xFF34C759)))]),
          const SizedBox(height:4), Text('${m['desc']} \u2022 ${m['size']}', style: const TextStyle(fontSize:12, color:Color(0xFF8E8E93), fontFamily:'TideFont'))])),
          if (!installed)
            downloading ? const SizedBox(width:24,height:24, child: CircularProgressIndicator(strokeWidth:2, color:Color(0xFF6B5B95)))
            : BouncyTap(onTap:()=>_downloadModel(i), child: Container(padding: const EdgeInsets.symmetric(horizontal:14,vertical:8), decoration: BoxDecoration(borderRadius:BorderRadius.circular(14), color: const Color(0xFF6B5B95)), child: const Text('下载', style: TextStyle(fontSize:13, color:Colors.white, fontFamily:'TideFont')))),
        ]),
        if (downloading) Padding(padding: const EdgeInsets.only(top:10), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value:m['progress'] as double, backgroundColor: const Color(0xFFE8E8F0), color: const Color(0xFF6B5B95), borderRadius:BorderRadius.circular(4)),
          const SizedBox(height:4), Text('${((m['progress']as double)*100).toInt()}%', style: const TextStyle(fontSize:12, color:Color(0xFF8E8E93), fontFamily:'TideFont'))])),
      ]));
    }));
}
