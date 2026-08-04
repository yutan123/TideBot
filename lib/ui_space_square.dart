import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db.dart';
import 'ai.dart';
import 'ui_chat_core.dart';

// ==== 空间页面 ====
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
      _dailyQuote = await AIManager().getDailyQuote(_botId); // 真实生成今日一言
    }
    setState(() {});
  }

  @override Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${DateTime.now().month}月${DateTime.now().day}日", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(_botName, style: const TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 24),
          // 今日一言
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)), child: Row(children: [Container(width: 40, height: 40, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black), alignment: Alignment.center, child: Text(_botName.isNotEmpty ? _botName.substring(0,1) : "A", style: const TextStyle(color: Colors.white, fontSize: 18))), const SizedBox(width: 12), Expanded(child: Text(_dailyQuote, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))])),
          const SizedBox(height: 12),
          // 相遇
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("与创造者的第 1 天", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text("${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day} 这一天你们相遇了", style: const TextStyle(color: Colors.grey))])),
        ],
      ),
    );
  }
}

// ==== 广场/小游戏 ====
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
          Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(isGame ? "小游戏" : "动态", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), IconButton(icon: const Icon(Icons.swap_calls, size: 30), onPressed: () => setState(() => isGame = !isGame))])),
          Expanded(child: isGame ? ListView(padding: const EdgeInsets.all(16), children: [
            _buildGameCard("32张扑克牌", "无大小王真实算力决胜", Colors.teal.shade50),
            _buildGameCard("五子棋", "经典双人对弈", Colors.blue.shade50),
            _buildGameCard("20问猜物", "互猜谜底看谁知识广", Colors.purple.shade50),
          ]) : const Center(child: Text("动态生态开发中..."))),
        ],
      ),
    );
  }
  Widget _buildGameCard(String t, String d, Color c) => Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(28)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 8), Text(d, style: TextStyle(color: Colors.black.withOpacity(0.6)))]));
}

// ==== 我的页面 ====
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)), child: const Row(children: [Icon(Icons.account_circle, size: 48), SizedBox(width: 16), Text("创造者", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))])),
          const SizedBox(height: 24),
          _buildRow("API 设置", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiSetupPage()))),
          _buildRow("本地模型", onTap: (){}),
          _buildRow("聊天背景", onTap: (){}),
          _buildRow("绑定微信", onTap: (){}),
        ],
      ),
    );
  }
  Widget _buildRow(String title, {required VoidCallback onTap}) => GestureDetector(onTap: onTap, child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const Icon(Icons.chevron_right, color: Colors.grey)])));
}

// ==== API 真实设置页 (全页而非弹窗) ====
class ApiSetupPage extends StatefulWidget {
  const ApiSetupPage({Key? key}) : super(key: key);
  @override State<ApiSetupPage> createState() => _ApiSetupPageState();
}
class _ApiSetupPageState extends State<ApiSetupPage> {
  final _urlC = TextEditingController(text: "https://api.deepseek.com");
  final _keyC = TextEditingController();
  final _modelC = TextEditingController(text: "deepseek-chat");
  String _provider = "DeepSeek";
  String _status = "";

  void _test() async {
    setState(() => _status = "测试中...");
    final res = await AIManager().testConnection(_urlC.text, _keyC.text, _modelC.text);
    if (res['success']) {
      setState(() => _status = "连接成功！延迟: ${res['delay']}ms");
    } else {
      setState(() => _status = "失败: ${res['error']}");
    }
  }

  void _save() async {
    await DBManager().insertProvider({
      'id': 'prov_${DateTime.now().millisecondsSinceEpoch}', 'type': 'chat', 'name': _provider,
      'base_url': _urlC.text, 'api_key': _keyC.text, 'created_at': DateTime.now().millisecondsSinceEpoch
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    Navigator.pop(context);
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(title: const Text("API 核心配置", style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text("文本/视觉模型提供商", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _provider, decoration: const InputDecoration(border: InputBorder.none),
                items: ["DeepSeek", "Siliconflow", "Gitee", "Kimi", "自定义"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                onChanged: (v) => setState(() => _provider = v!),
              ),
              TextField(controller: _urlC, decoration: const InputDecoration(labelText: "Base URL")),
              TextField(controller: _modelC, decoration: const InputDecoration(labelText: "测试用 Model (如 deepseek-chat)")),
              TextField(controller: _keyC, obscureText: true, decoration: const InputDecoration(labelText: "API Key (sk-...)")),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_status, style: TextStyle(color: _status.contains("成功") ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                Row(children: [
                  TextButton(onPressed: _test, child: const Text("测速")),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black), onPressed: _save, child: const Text("保存", style: TextStyle(color: Colors.white))),
                ])
              ])
            ]),
          )
        ],
      ),
    );
  }
}