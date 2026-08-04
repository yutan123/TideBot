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
      const Text("切换视界", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), const SizedBox(height: 24),
      ...bots.map((b) => ListTile(title: Text(b['name'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)), onTap: () { setState(() { _botName = b['name']; _botId = b['id']; }); Navigator.pop(context); _load(); }))
    ]));
  }

  @override Widget build(BuildContext context) {
    final dt = DateTime.now();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 120),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("${dt.month}月${dt.day}日 星期${['一','二','三','四','五','六','日'][dt.weekday-1]}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), 
            Row(children: [Text("${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(width: 12), GestureDetector(onTap: _showBotSelector, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(20)), child: Row(children: [Text(_botName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)), const Icon(Icons.arrow_drop_down_rounded, size: 20)])))])
          ]),
          const SizedBox(height: 32),
          
          // 今日一言卡片
          Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 24, offset: const Offset(0, 12))]), child: Row(children: [Container(width: 52, height: 52, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black), alignment: Alignment.center, child: Text(_botName.isNotEmpty ? _botName.substring(0,1) : "A", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))), const SizedBox(width: 20), Expanded(child: Text(_dailyQuote, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.5)))])),
          const SizedBox(height: 20),
          
          // 相遇卡片
          Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 24, offset: const Offset(0, 12))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("与 $_botName 的第 1 天", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)), const SizedBox(height: 8), Text("${dt.year}.${dt.month}.${dt.day} 这一天你们相遇了", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 15))])),
          const SizedBox(height: 20),
          
          // 日程与心情卡片
          Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 24, offset: const Offset(0, 12))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text("今日心情:", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(width: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)), child: Row(children: [const Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.orange, size: 18), const SizedBox(width: 6), const Text("开心", style: TextStyle(fontSize: 15, color: Colors.orange, fontWeight: FontWeight.bold))]))]), const SizedBox(height: 32), const Text("今日日程", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 16), Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 14), const Text("下午 14:00 - 喝下午茶", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))]), const SizedBox(height: 12), Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)), const SizedBox(width: 14), const Text("晚上 20:00 - 睡前故事", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))])])),
          const SizedBox(height: 20),

          // 日记卡片 (展示最近两条)
          Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 24, offset: const Offset(0, 12))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("记忆日记", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 16), const Text("1. 主人今天提到了喜欢喝咖啡。", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5, color: Colors.black87)), const SizedBox(height: 8), const Text("2. 设定了明天早起的闹钟，一定不能让主人迟到。", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5, color: Colors.black87))]))
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
          Padding(padding: const EdgeInsets.all(24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isGame ? "小游戏" : "动态", style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1)), 
            GestureDetector(
              onTap: () { HapticFeedback.mediumImpact(); setState(() => isGame = !isGame); }, 
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), switchInCurve: Curves.easeOutCubic, switchOutCurve: Curves.easeInCubic, transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c), child: Container(key: ValueKey(isGame), padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: Icon(isGame ? Icons.chat_bubble_rounded : Icons.videogame_asset_rounded, color: Colors.white, size: 24)))
            )
          ])),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), switchInCurve: Curves.easeOutCubic, switchOutCurve: Curves.easeInCubic, child: isGame ? ListView(key: const ValueKey("G"), padding: const EdgeInsets.only(left: 24, right: 24, bottom: 120), children: [
            _buildGameCard("32张扑克牌", "无大小王真实算力决胜，对子、顺子、炸弹！", Colors.teal.shade50),
            _buildGameCard("五子棋", "经典双人对弈，考验逻辑与推理", Colors.blue.shade50),
            _buildGameCard("20问猜物", "AI出题你来猜，或者你出题让AI猜", Colors.purple.shade50),
            _buildGameCard("井字棋", "轻量级破冰游戏，随时开局", Colors.orange.shade50),
          ]) : ListView(key: const ValueKey("D"), padding: const EdgeInsets.only(left: 24, right: 24, bottom: 120), children: [
            Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))]), child: Column(children: [const Icon(Icons.construction_rounded, size: 48, color: Colors.grey), const SizedBox(height: 16), const Text("动态与生态系统", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text("已按照规范预留了点赞、评论、收藏与随机互动架构，等待后续模块深度接入。", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey, height: 1.5))]))
          ]))),
        ],
      ),
    );
  }
  Widget _buildGameCard(String t, String d, Color c) => Container(margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(40)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)), const SizedBox(height: 12), Text(d, style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.w700, height: 1.4))]));
}

// ================== 我的与设置 ==================
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 120),
        children: [
          Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 24, offset: const Offset(0, 12))]), child: Row(children: [Container(width: 72, height: 72, decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.person_rounded, size: 36)), const SizedBox(width: 20), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("创造者", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), SizedBox(height:6), Text("点击编辑资料", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 15))]))])),
          const SizedBox(height: 28),
          _buildRow("API 设置", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApiSetupPage()))),
          _buildRow("本地轻量模型", onTap: (){}),
          _buildRow("主题设置", onTap: (){}),
          _buildRow("聊天背景", onTap: (){}),
          _buildRow("绑定微信", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeChatBindPage()))),
          const SizedBox(height: 20),
          _buildRow("普通设置", onTap: (){}),
          _buildRow("高级设置", onTap: (){}),
          _buildRow("关于 TideBot", onTap: (){}),
        ],
      ),
    );
  }
  Widget _buildRow(String title, {required VoidCallback onTap}) => GestureDetector(onTap: onTap, child: Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 6))]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Icon(Icons.chevron_right_rounded, color: Colors.grey)])));
}

// ==== 微信桥接页 ====
class WeChatBindPage extends StatelessWidget {
  const WeChatBindPage({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFFF2F2F7), appBar: AppBar(title: const Text("OpenClaw 桥接", style: TextStyle(fontWeight: FontWeight.w900))), body: Center(child: Container(padding: const EdgeInsets.all(36), margin: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 15))]), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.wechat_rounded, color: Colors.green, size: 56), const SizedBox(height: 20), const Text("微信托管协议", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 28), Container(width: 220, height: 220, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: const Text("加载 CLI 二维码中...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))), const SizedBox(height: 28), const Text("请使用微信扫一扫", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16))]))));
  }
}

// ==== API 设置页 ====
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
    if (res['success']) setState(() => _status = "连通成功！\n延迟: ${res['delay']}ms");
    else setState(() => _status = "失败: ${res['error']}");
  }

  void _save() async {
    if (_nameC.text.isEmpty || _keyC.text.isEmpty) return;
    await DBManager().insertProvider({'id': 'prov_${DateTime.now().millisecondsSinceEpoch}', 'type': 'chat', 'name': "${_nameC.text} / ${_testModelC.text}", 'base_url': _urlC.text, 'api_key': _keyC.text, 'created_at': DateTime.now().millisecondsSinceEpoch});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存模型提供商')));
    Navigator.pop(context);
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(title: const Text("配置提供商", style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("预设快捷填充", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
              DropdownButton<String>(
                isExpanded: true, value: _provider, underline: const SizedBox(),
                items: ["DeepSeek", "Siliconflow", "Gitee", "Kimi", "阿里云百炼", "自定义"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)))).toList(),
                onChanged: (v) { setState(() { _provider = v!; if (v != "自定义") { _urlC.text = _presets[v]!; _nameC.text = v; } else { _urlC.clear(); _nameC.clear(); } }); },
              ),
              const Divider(height: 32),
              TextField(controller: _nameC, decoration: const InputDecoration(labelText: "自定义名称", border: InputBorder.none, labelStyle: TextStyle(fontWeight: FontWeight.bold))), const Divider(),
              TextField(controller: _urlC, decoration: const InputDecoration(labelText: "Base URL", border: InputBorder.none, labelStyle: TextStyle(fontWeight: FontWeight.bold))), const Divider(),
              TextField(controller: _testModelC, decoration: const InputDecoration(labelText: "绑定的具体模型 (如 deepseek-chat)", border: InputBorder.none, labelStyle: TextStyle(fontWeight: FontWeight.bold))), const Divider(),
              TextField(controller: _keyC, obscureText: true, decoration: const InputDecoration(labelText: "API Key", border: InputBorder.none, labelStyle: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(_status, style: TextStyle(color: _status.contains("成功") ? Colors.green : Colors.red, fontWeight: FontWeight.bold, height: 1.4))),
                Row(children: [
                  TextButton(onPressed: _test, child: const Text("测速", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16))), const SizedBox(width: 8),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), onPressed: _save, child: const Text("保存", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                ])
              ])
            ]),
          )
        ],
      ),
    );
  }
}