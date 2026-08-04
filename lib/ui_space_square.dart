import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db.dart';
import 'ai.dart';
import 'ui_chat_core.dart';

// ================== 空间页面 ==================
class SpacePage extends StatefulWidget {
  const SpacePage({Key? key}) : super(key: key);
  @override State<SpacePage> createState() => _SpacePageState();
}
class _SpacePageState extends State<SpacePage> {
  String _botName = "未连接";
  String _botId = "";
  String _dailyQuote = "今天也要开心度过哦。";
  
  @override void initState() { super.initState(); _load(); }
  void _load() async {
    final bots = await DBManager().getAllBots();
    if (bots.isNotEmpty) {
      _botName = bots.first['name']; _botId = bots.first['id'];
      _dailyQuote = await AIManager().getDailyQuote(_botId); 
    }
    setState(() {});
  }

  void _showBotSelector() async {
    final bots = await DBManager().getAllBots();
    TideDialogs.showBottomSheet(context: context, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("切换视界", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 16),
      ...bots.map((b) => ListTile(title: Text(b['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), onTap: () { setState(() { _botName = b['name']; _botId = b['id']; }); Navigator.pop(context); _load(); }))
    ]));
  }

  @override Widget build(BuildContext context) {
    final dt = DateTime.now();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 100),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("${dt.month}月${dt.day}日 星期${['一','二','三','四','五','六','日'][dt.weekday-1]}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), 
            Row(children: [Text("${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(width: 8), GestureDetector(onTap: _showBotSelector, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(16)), child: Row(children: [Text(_botName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), const Icon(Icons.arrow_drop_down, size: 16)])))])
          ]),
          const SizedBox(height: 24),
          
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))]), child: Row(children: [Container(width: 44, height: 44, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black), alignment: Alignment.center, child: Text(_botName.isNotEmpty ? _botName.substring(0,1) : "A", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))), const SizedBox(width: 16), Expanded(child: Text(_dailyQuote, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)))])),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("与创造者的第 1 天", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)), const SizedBox(height: 6), Text("${dt.year}.${dt.month}.${dt.day} 这一天你们相遇了", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))])),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text("今日心情:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)), child: const Text("😊 开心", style: TextStyle(fontSize: 14, color: Colors.orange, fontWeight: FontWeight.bold)))]), const SizedBox(height: 24), const Text("今日日程", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 12), Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 10), const Text("下午 14:00 - 喝下午茶", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))]), const SizedBox(height: 8), Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 10), const Text("晚上 20:00 - 睡前故事", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))])])),
        ],
      ),
    );
  }
}

// ================== 广场页面 ==================
class SquarePage extends StatefulWidget {
  const SquarePage({Key? key}) : super(key: key);
  @override State<SquarePage> createState() => _SquarePageState();
}
class _SquarePageState extends State<SquarePage> {
  bool isGame = false;
  @override Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(isGame ? "小游戏" : "动态", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)), GestureDetector(onTap: () { HapticFeedback.mediumImpact(); setState(() => isGame = !isGame); }, child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c), child: Container(key: ValueKey(isGame), padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: Icon(isGame ? Icons.chat_bubble_outline : Icons.videogame_asset, color: Colors.white, size: 20))))])),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: isGame ? ListView(key: const ValueKey("G"), padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100), children: [
            _buildGameCard("32张扑克牌", "无大小王真实算力决胜", Colors.teal.shade50),
            _buildGameCard("五子棋", "经典双人对弈", Colors.blue.shade50),
            _buildGameCard("20问猜物", "互猜谜底看谁知识广", Colors.purple.shade50),
          ]) : ListView(key: const ValueKey("D"), padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100), children: [
            Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)), child: const Text("生态系统与动态详情页已保留架构，等待后续模块接入。", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)))
          ]))),
        ],
      ),
    );
  }
  Widget _buildGameCard(String t, String d, Color c) => Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(32)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)), const SizedBox(height: 8), Text(d, style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 15, fontWeight: FontWeight.w600))]));
}

// ================== 我的与设置 ==================
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 100),
        children: [
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))]), child: Row(children: [Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.person, size: 32)), const SizedBox(width: 16), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("创造者", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height:4), Text("点击编辑资料", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))])])),
          const SizedBox(height: 24),
          _buildRow("API 设置", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiSetupPage()))),
          _buildRow("本地模型", onTap: (){}),
          _buildRow("主题设置", onTap: (){}),
          _buildRow("聊天背景", onTap: (){}),
          _buildRow("绑定微信", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeChatBindPage()))),
          const SizedBox(height: 20),
          _buildRow("普通设置", onTap: (){}),
          _buildRow("关于应用", onTap: (){}),
        ],
      ),
    );
  }
  Widget _buildRow(String title, {required VoidCallback onTap}) => GestureDetector(onTap: onTap, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const Icon(Icons.chevron_right, color: Colors.grey)])));
}

// ==== 微信桥接页 ====
class WeChatBindPage extends StatelessWidget {
  const WeChatBindPage({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFFF5F5F7), appBar: AppBar(title: const Text("绑定微信", style: TextStyle(fontWeight: FontWeight.w900))), body: Center(child: Container(padding: const EdgeInsets.all(32), margin: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text("使用 OpenClaw 桥接", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 24), Container(width: 200, height: 200, color: Colors.grey.shade100, alignment: Alignment.center, child: const Text("加载二维码中...", style: TextStyle(color: Colors.grey))), const SizedBox(height: 24), const Text("请使用微信扫一扫", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))]))));
  }
}

// ==== 全屏真实的 API 设置页 ====
class ApiSetupPage extends StatefulWidget {
  const ApiSetupPage({Key? key}) : super(key: key);
  @override State<ApiSetupPage> createState() => _ApiSetupPageState();
}
class _ApiSetupPageState extends State<ApiSetupPage> {
  final _urlC = TextEditingController();
  final _nameC = TextEditingController();
  final _keyC = TextEditingController();
  final _testModelC = TextEditingController(text: "deepseek-chat");
  String _provider = "DeepSeek";
  String _status = "";
  
  final Map<String, String> _presets = {
    "DeepSeek": "https://api.deepseek.com", "Siliconflow": "https://api.siliconflow.cn/v1", "Gitee": "https://ai.gitee.com/v1", "Kimi": "https://api.moonshot.cn/v1", "阿里云百炼": "https://dashscope.aliyuncs.com/api/v1"
  };

  @override void initState() { super.initState(); _urlC.text = _presets["DeepSeek"]!; _nameC.text = "DeepSeek"; }

  void _test() async {
    setState(() => _status = "测试中...");
    final res = await AIManager().testConnection(_urlC.text, _keyC.text, _testModelC.text);
    if (res['success']) setState(() => _status = "成功！延迟: ${res['delay']}ms");
    else setState(() => _status = "失败: ${res['error']}");
  }

  void _save() async {
    if (_nameC.text.isEmpty || _keyC.text.isEmpty) return;
    await DBManager().insertProvider({'id': 'prov_${DateTime.now().millisecondsSinceEpoch}', 'type': 'chat', 'name': "${_nameC.text} / ${_testModelC.text}", 'base_url': _urlC.text, 'api_key': _keyC.text, 'created_at': DateTime.now().millisecondsSinceEpoch});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存提供商')));
    Navigator.pop(context);
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(title: const Text("新增提供商", style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("预设快捷填充", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                isExpanded: true, value: _provider, underline: const SizedBox(),
                items: ["DeepSeek", "Siliconflow", "Gitee", "Kimi", "阿里云百炼", "自定义"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))).toList(),
                onChanged: (v) { setState(() { _provider = v!; if (v != "自定义") { _urlC.text = _presets[v]!; _nameC.text = v; } else { _urlC.clear(); _nameC.clear(); } }); },
              ),
              const Divider(), const SizedBox(height: 12),
              TextField(controller: _nameC, decoration: const InputDecoration(labelText: "自定义名称", border: InputBorder.none)), const Divider(),
              TextField(controller: _urlC, decoration: const InputDecoration(labelText: "Base URL", border: InputBorder.none)), const Divider(),
              TextField(controller: _testModelC, decoration: const InputDecoration(labelText: "使用的具体模型 (如 deepseek-chat)", border: InputBorder.none)), const Divider(),
              TextField(controller: _keyC, obscureText: true, decoration: const InputDecoration(labelText: "API Key", border: InputBorder.none)),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(_status, style: TextStyle(color: _status.contains("成功") ? Colors.green : Colors.red, fontWeight: FontWeight.bold))),
                Row(children: [
                  TextButton(onPressed: _test, child: const Text("测速", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))), const SizedBox(width: 8),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: _save, child: const Text("保存", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                ])
              ])
            ]),
          )
        ],
      ),
    );
  }
}