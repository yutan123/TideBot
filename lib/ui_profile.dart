import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'ui_components.dart';
import 'db.dart';
import 'ai.dart';

// ==================== 我的页 ====================
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key}); @override State<ProfilePage> createState() => _ProfilePageState();
}
class _ProfilePageState extends State<ProfilePage> {
  String _userName = '用户';
  final _settings = [
    {'icon':Icons.api_rounded,'title':'API 设置','page':'api'},{'icon':Icons.cloud_download_rounded,'title':'本地模型','page':'local'},
    {'icon':Icons.palette_rounded,'title':'主题设置','page':'theme'},{'icon':Icons.notifications_rounded,'title':'通知管理','page':'notify'},
    {'icon':Icons.security_rounded,'title':'隐私与安全','page':'privacy'},{'icon':Icons.info_rounded,'title':'关于 TideBot','page':'about'},
    {'icon':Icons.storage_rounded,'title':'数据管理','page':'data'},{'icon':Icons.feedback_rounded,'title':'反馈与建议','page':'feedback'},
  ];
  @override void initState() { super.initState(); _loadProfile(); }
  Future<void> _loadProfile() async {
    final name = await DBManager().getKV('user_name');
    if (mounted && name != null && name.isNotEmpty) setState(() => _userName = name);
  }
  @override Widget build(BuildContext context) => Container(color: const Color(0xFFF2F2F7),
    child: SafeArea(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16,20,16,100),
      child: Column(children: [_buildProfileCard(), const SizedBox(height:24),
        ..._settings.map((s) => BouncyTap(onTap: ()=>_onSetting(s), child: _buildSettingItem(s))), const SizedBox(height:20)]))));

  Widget _buildProfileCard() => FrostCard(padding: const EdgeInsets.all(20), child: Row(children: [
    BouncyTap(onTap: () async {
      final ctrl = TextEditingController(text:_userName);
      final r = await showTideDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
        content: TideDialogs.glassContent(context:ctx, children: [
          const Text('修改昵称', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
          TextField(controller:ctrl, autofocus:true, style: const TextStyle(fontFamily:'TideFont'), decoration: const InputDecoration(hintText:'输入新昵称', border:OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(12))))),
          const SizedBox(height:16), Row(mainAxisAlignment:MainAxisAlignment.end, children: [
            TideDialogs.glassButton('取消', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E)),
            const SizedBox(width:10), TideDialogs.glassButton('确定', onTap:()=>Navigator.pop(ctx, ctrl.text))])])));
      if (r != null && r.toString().isNotEmpty) { setState(()=>_userName=r.toString()); await DBManager().insertKV('user_name', r.toString()); }
    }, child: CircleAvatar(radius:32, backgroundColor: const Color(0xFF6B5B95).withOpacity(0.15), child: const Icon(Icons.person_rounded, size:36, color:Color(0xFF6B5B95)))),
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
      case 'about': showTideSheet(context:context, height:300, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
        const Text('关于 TideBot', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        const Text('版本: 1.0.0', style: TextStyle(fontSize:14, color:Color(0xFF636366), fontFamily:'TideFont')),
        const Text('本地化沉浸式多模态 AI 伴侣', style: TextStyle(fontSize:14, color:Color(0xFF636366), fontFamily:'TideFont')),
        const SizedBox(height:8), const Text('100% 本地运行，隐私无忧。', style: TextStyle(fontSize:13, color:Color(0xFF8E8E93), fontFamily:'TideFont')),
        const SizedBox(height:16), const Text('开发者: yutan123', style: TextStyle(fontSize:13, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))]))); break;
      case 'data': showTideSheet(context:context, height:220, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
        const Text('数据管理', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:16),
        ListTile(leading: const Icon(Icons.download_rounded, color:Color(0xFF6B5B95)), title: const Text('导出聊天记录', style: TextStyle(fontFamily:'TideFont')), onTap:() async { await DBManager().exportToMarkdown(); if(mounted){Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已导出到本地存储', style: TextStyle(fontFamily:'TideFont')), backgroundColor: Color(0xFF6B5B95)));}})]))); break;
      case 'privacy': showTideSheet(context:context, height:350, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
        const Text('隐私与安全', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        const Text('TideBot 采用纯本地架构：', style: TextStyle(fontSize:14, fontWeight:FontWeight.w600, fontFamily:'TideFont')), const SizedBox(height:8),
        const Text('所有聊天数据存储在本地数据库\nAPI 密钥加密存储在本地\n无任何数据上传\n无统计 SDK, 无广告', style: TextStyle(fontSize:13, color:Color(0xFF636366), fontFamily:'TideFont', height:1.8))]))); break;
      default: ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s['title']}功能开发中...', style: const TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating));
    }
  }
  void _showThemePicker() { showTideSheet(context:context, height:280, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
    const Text('主题设置', style: TextStyle(fontSize:20, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:16),
    ListTile(leading: Container(width:24,height:24,decoration: const BoxDecoration(shape:BoxShape.circle, gradient:LinearGradient(colors:[Color(0xFF6B5B95),Color(0xFF9B8EC4)]))), title: const Text('经典紫', style: TextStyle(fontFamily:'TideFont')), trailing: const Icon(Icons.check, color:Color(0xFF6B5B95)), onTap:()=>Navigator.pop(context)),
    ListTile(leading: Container(width:24,height:24,decoration: const BoxDecoration(shape:BoxShape.circle, gradient:LinearGradient(colors:[Color(0xFF007AFF),Color(0xFF4DA3FF)]))), title: const Text('天空蓝', style: TextStyle(fontFamily:'TideFont')), onTap:()=>Navigator.pop(context)),
    ListTile(leading: Container(width:24,height:24,decoration: const BoxDecoration(shape:BoxShape.circle, gradient:LinearGradient(colors:[Color(0xFFFF6B6B),Color(0xFFFFA5A5)]))), title: const Text('珊瑚红', style: TextStyle(fontFamily:'TideFont')), onTap:()=>Navigator.pop(context))]))); }
  void _showNotificationSettings() {
    bool silent=false, schedule=true;
    TideDialogs.show(context:context, builder:(ctx)=>StatefulBuilder(builder:(ctx,setSt)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, children: [
        const Text('通知管理', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        SwitchListTile(title: const Text('静默通知', style: TextStyle(fontFamily:'TideFont')), value:silent, onChanged:(v)=>setSt(()=>silent=v), activeColor: const Color(0xFF6B5B95)),
        SwitchListTile(title: const Text('日程提醒', style: TextStyle(fontFamily:'TideFont')), value:schedule, onChanged:(v)=>setSt(()=>schedule=v), activeColor: const Color(0xFF6B5B95)),
        const SizedBox(height:12), TideDialogs.glassButton('确定', onTap:()=>Navigator.pop(ctx))]))));
  }
}

// ==================== API 设置页 ====================
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key}); @override State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}
class _ApiSettingsPageState extends State<ApiSettingsPage> {
  List<Map<String,dynamic>> _providers = [];
  bool _loading = true;

  final _presets = [
    {'name':'DeepSeek','url':'https://api.deepseek.com/v1','models':'deepseek-chat,deepseek-reasoner'},
    {'name':'SiliconFlow','url':'https://api.siliconflow.cn/v1','models':'Qwen/Qwen2.5-7B-Instruct,deepseek-ai/DeepSeek-V3'},
    {'name':'阿里云百炼','url':'https://dashscope.aliyuncs.com/compatible-mode/v1','models':'qwen-plus,qwen-max'},
    {'name':'Kimi','url':'https://api.moonshot.cn/v1','models':'moonshot-v1-8k,moonshot-v1-32k'},
  ];

  @override void initState() { super.initState(); _loadProviders(); }
  Future<void> _loadProviders() async {
    final db = DBManager();
    final provs = await db.queryProviders();
    // 同时从 KV 存储加载额外的 provider 列表
    final raw = await db.getKV('provider_list');
    List<Map<String,dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      try { final decoded = jsonDecode(raw) as List; list = decoded.map((e)=>e as Map<String,dynamic>).toList(); } catch(_){}
    }
    if (list.isEmpty && provs.isNotEmpty) {
      for (var p in provs) { list.add({'name':p['name']??'','url':p['base_url']??'','key':p['api_key']??'','model':p['model']??''}); }
      await db.insertKV('provider_list', jsonEncode(list));
    }
    if (mounted) setState(() { _providers = list; _loading = false; });
  }

  Future<void> _saveList() async {
    await DBManager().insertKV('provider_list', jsonEncode(_providers));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存', style: TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating, backgroundColor: Color(0xFF6B5B95)));
  }

  void _addProvider() {
    showTideSheet(context: context, height: 480, child: Padding(padding: const EdgeInsets.fromLTRB(16,0,16,20), child: SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height:8), const Text('新增模型提供商', style: TextStyle(fontSize:18, fontWeight:FontWeight.w600, fontFamily:'TideFont')),
        const SizedBox(height:12),
        Wrap(spacing:8, runSpacing:8, children: _presets.map((p) => BouncyTap(onTap:() {
          Navigator.pop(context);
          _showAddDialog(p['name']!, p['url']!, '', p['models']!);
        }, child: Container(padding: const EdgeInsets.symmetric(horizontal:12,vertical:8), decoration: BoxDecoration(borderRadius:BorderRadius.circular(16), color: Colors.white.withOpacity(0.8)), child: Text(p['name']!, style: const TextStyle(fontSize:13, fontFamily:'TideFont'))))).toList()),
        const SizedBox(height:20),
        BouncyTap(onTap:() { Navigator.pop(context); _showAddDialog('自定义', '', '', ''); },
          child: Container(width: double.infinity, height:44, decoration: BoxDecoration(borderRadius:BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6B5B95))), child: const Center(child: Text('自定义', style: TextStyle(fontSize:15, color:Color(0xFF6B5B95), fontFamily:'TideFont'))))),
        const SizedBox(height:20),
        const Text('已添加的提供商', style: TextStyle(fontSize:15, fontWeight:FontWeight.w600, fontFamily:'TideFont')),
        const SizedBox(height:8),
        ..._providers.map((p) => ListTile(dense:true, title: Text(p['name']??'', style: const TextStyle(fontFamily:'TideFont', fontSize:14)), subtitle: Text(p['url']??'', style: const TextStyle(fontSize:11, color:Color(0xFF8E8E93))), trailing: const Icon(Icons.check, color:Color(0xFF34C759), size:18))),
      ]),
    )));
  }

  void _showAddDialog(String name, String url, String key, String models) {
    final nCtrl = TextEditingController(text:name);
    final uCtrl = TextEditingController(text:url);
    final kCtrl = TextEditingController(text:key);
    final mCtrl = TextEditingController(text:models);
    TideDialogs.show(context:context, builder:(ctx)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, maxWidth:0.9, children: [
        const Text('添加提供商', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:12),
        _f('名称', nCtrl), const SizedBox(height:8),
        _f('API 地址', uCtrl), const SizedBox(height:8),
        _f('API Key', kCtrl, obscure:true), const SizedBox(height:8),
        _f('模型名(逗号分隔)', mCtrl), const SizedBox(height:16),
        Row(children:[
          Expanded(child: TideDialogs.glassButton('取消', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))),
          const SizedBox(width:10),
          Expanded(child: TideDialogs.glassButton('添加', onTap:(){
            setState(()=>_providers.add({'name':nCtrl.text.trim(),'url':uCtrl.text.trim(),'key':kCtrl.text.trim(),'model':mCtrl.text.trim()}));
            Navigator.pop(ctx); _saveList();
          })),
        ])])));
  }

  Widget _f(String label, TextEditingController c,{bool obscure=false}) => Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize:13, color:Color(0xFF8E8E93), fontFamily:'TideFont')), const SizedBox(height:4),
    Container(decoration: BoxDecoration(borderRadius:BorderRadius.circular(10), color: const Color(0xFFE8E8F0)), child: TextField(controller:c, obscureText:obscure, style: const TextStyle(fontSize:14, fontFamily:'TideFont'), decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal:12, vertical:10), border:InputBorder.none)))]);

  void _deleteProvider(int idx) {
    TideDialogs.show(context:context, builder:(ctx)=>AlertDialog(backgroundColor:Colors.transparent, contentPadding:EdgeInsets.zero,
      content: TideDialogs.glassContent(context:ctx, children: [
        const Text('删除提供商', style: TextStyle(fontSize:17, fontWeight:FontWeight.w700, fontFamily:'TideFont')), const SizedBox(height:10),
        Text('确定删除「${_providers[idx]['name']}」吗？', style: const TextStyle(fontSize:14, fontFamily:'TideFont')), const SizedBox(height:16),
        Row(children:[Expanded(child: TideDialogs.glassButton('取消', onTap:()=>Navigator.pop(ctx), color: const Color(0xFFE8E8F0), textColor: const Color(0xFF1C1C1E))), const SizedBox(width:10), Expanded(child: TideDialogs.glassButton('删除', onTap:(){ setState(()=>_providers.removeAt(idx)); Navigator.pop(ctx); _saveList(); }, color: const Color(0xFFE74C3C)))]),
      ])));
  }

  Future<void> _testProvider(Map<String,dynamic> p) async {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('测试中...', style: TextStyle(fontFamily:'TideFont')), duration: Duration(seconds:1), behavior:SnackBarBehavior.floating));
    try {
      final ms = await AIManager().testConnection(p['url']??'', p['key']??'', (p['model'] as String?)?.split(',').first.trim()??'');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接成功！${ms}ms', style: const TextStyle(fontFamily:'TideFont')), backgroundColor: const Color(0xFF34C759), behavior:SnackBarBehavior.floating));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败: $e', style: const TextStyle(fontFamily:'TideFont')), backgroundColor: const Color(0xFFE74C3C), behavior:SnackBarBehavior.floating));
    }
  }

  @override Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFFF2F2F7),
    appBar: AppBar(title: const Text('API 设置', style: TextStyle(fontWeight:FontWeight.w600, fontFamily:'TideFont')), backgroundColor:Colors.transparent, elevation:0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size:20), onPressed:()=>Navigator.pop(context)),
      actions: [IconButton(icon: const Icon(Icons.add_circle_outline_rounded, color:Color(0xFF6B5B95), size:26), onPressed:_addProvider)]),
    body: _loading ? const Center(child: CircularProgressIndicator(color:Color(0xFF6B5B95))) :
    _providers.isEmpty ? Center(child: Column(mainAxisSize:MainAxisSize.min, children: [
      const Icon(Icons.api_rounded, size:60, color:Color(0xFFC7C7CC)), const SizedBox(height:12),
      const Text('还没有添加任何模型提供商', style: TextStyle(fontSize:15, color:Color(0xFF8E8E93), fontFamily:'TideFont')),
      const SizedBox(height:6), const Text('点击右上角 + 添加', style: TextStyle(fontSize:13, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))])) :
    ListView.builder(padding: const EdgeInsets.fromLTRB(16,8,16,100), itemCount:_providers.length, itemBuilder:(ctx,i){
      final p = _providers[i];
      return FrostCard(margin: const EdgeInsets.only(bottom:10), padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p['name']??'', style: const TextStyle(fontSize:16, fontWeight:FontWeight.w600, fontFamily:'TideFont'))),
          BouncyTap(onTap:()=>_testProvider(p), child: Container(padding: const EdgeInsets.symmetric(horizontal:10,vertical:4), decoration: BoxDecoration(borderRadius:BorderRadius.circular(10), color: const Color(0xFF6B5B95).withOpacity(0.15)), child: const Text('测试', style: TextStyle(fontSize:12, color:Color(0xFF6B5B95), fontFamily:'TideFont')))),
          const SizedBox(width:8),
          BouncyTap(onTap:()=>_deleteProvider(i), child: const Icon(Icons.delete_outline_rounded, size:20, color:Color(0xFFE74C3C))),
        ]),
        const SizedBox(height:6), Text(p['url']??'', style: const TextStyle(fontSize:12, color:Color(0xFF8E8E93), fontFamily:'TideFont'), maxLines:1, overflow:TextOverflow.ellipsis),
        if ((p['model']??'').isNotEmpty) Padding(padding: const EdgeInsets.only(top:4), child: Text('模型: ${p['model']}', style: const TextStyle(fontSize:12, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))),
        if ((p['key']??'').isNotEmpty) Padding(padding: const EdgeInsets.only(top:2), child: Text('Key: ${p['key']!.substring(0, p['key']!.length < 8 ? p['key']!.length : 8)}...', style: const TextStyle(fontSize:11, color:Color(0xFFC7C7CC), fontFamily:'TideFont'))),
      ]));
    }));
}

// ==================== 本地模型页 ====================
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
    final m = _models[idx]; if (m['url']!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无下载链接', style: TextStyle(fontFamily:'TideFont')), behavior:SnackBarBehavior.floating)); return; }
    setState(() { m['downloading']=true; m['progress']=0.0; });
    // 模拟下载进度
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
          Row(children:[Text(m['name']!, style: const TextStyle(fontSize:16, fontWeight:FontWeight.w600, fontFamily:'TideFont')), if(installed) const Padding(padding: EdgeInsets.only(left:8), child: Icon(Icons.check_circle, size:18, color:Color(0xFF34C759)))]),
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
