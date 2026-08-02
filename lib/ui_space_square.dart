import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;

// ==========================================
// 全局通用玻璃卡片基类 (严格 iOS 圆角与毛玻璃)
// ==========================================
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.borderRadius = 20.0,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap!();
        },
        child: card,
      );
    }
    return card;
  }
}

// 纯 SVG 图标库 (扩展)
class SpaceIcons {
  static String get switchDynamic => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIiPjxwYXRoIGQ9Ik0yMSAxMS41YTguMzggOC4zOCAwIDAxLS45IDMuOCA4LjUgOC41IDAgMDEtNy42IDQuNyA4LjM4IDguMzggMCAwMS0zLjgtLjlMMyAyMWwxLjktNS43YTguMzggOC4zOCAwIDAxLS45LTMuOCA4LjUgOC41IDAgMDE0LjctNy42IDguMzggOC4zOCAwIDAxMy44LS45aC41YTguNDggOC40OCAwIDAxOCA4di41eiIvPjwvc3ZnPg=='));
  static String get switchGame => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIiPjxyZWN0IHg9IjIiIHk9IjYiIHdpZHRoPSIyMCIgaGVpZ2h0PSIxMiIgcng9IjIiIHJ5PSIyIi8+PGNpcmNsZSBjeD0iMTciIGN5PSIxMiIgcj0iMSIvPjxjaXJjbGUgY3g9IjE1IiBjeT0iMTAiIHI9IjEiLz48cGF0aCBkPSJNNiAxMmg0TTggMTB2NCIvPjwvc3ZnPg=='));
  static String get heart => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIiPjxwYXRoIGQ9Ik0yMC44NCA0LjYxYTUuNSA1LjUgMCAwMC03Ljc4IDBMMTIgNS42N2wtMS4wNi0xLjA2YTUuNSA1LjUgMCAwMC03Ljc4IDcuNzhsMS4wNiAxLjA2TDEyIDIxLjIzbDcuNzgtNy43OCAxLjA2LTEuMDZhNS41IDUuNSAwIDAwMC03Ljc4eiIvPjwvc3ZnPg=='));
  static String get share => utf8.decode(base64Decode('PHN2ZyB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIiPjxjaXJjbGUgY3g9IjE4IiBjeT0iNSIgcj0iMyIvPjxjaXJjbGUgY3g9IjYiIGN5PSIxMiIgcj0iMyIvPjxjaXJjbGUgY3g9IjE4IiBjeT0iMTkiIHI9IjMiLz48bGluZSB4MT0iOC41OSIgeTE9IjEzLjUxIiB4Mj0iMTUuNDIiIHkyPSIxNy40OSIvPjxsaW5lIHgxPSIxNS40MSIgeTE9IjYuNTEiIHgyPSI4LjU5IiB5Mj0iMTAuNDkiLz48L3N2Zz4='));
}

Widget renderSvg(String svgStr, {double size = 20, Color? color}) {
  return SvgPicture.string(svgStr, width: size, height: size, colorFilter: color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null);
}

// ==========================================
// 界面二：空间 (SpacePage - 数字生命日常)
// ==========================================
class SpacePage extends StatefulWidget {
  const SpacePage({Key? key}) : super(key: key);
  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  String selectedBot = "加载中...";
  
  // 动态获取当前时间
  String get _currentDate {
    final now = DateTime.now();
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return "${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}";
  }
  String get _currentTime {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_currentDate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Row(
                    children: [
                      Text(_currentTime, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          // TODO: 弹出机器人选择弹窗
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Text(selectedBot, style: TextStyle(fontSize: 14, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
                              const Icon(Icons.keyboard_arrow_down, size: 18),
                            ],
                          ),
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
            
            // 空间内容流
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
                children: [
                  // 1. 今日一言卡片
                  GlassCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).primaryColor.withOpacity(0.2))),
                        const SizedBox(width: 12),
                        const Expanded(child: Text("正在生成今日感悟...", style: TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ),

                  // 2. 羁绊记录卡片
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("与 未知生命体 的第 1 天", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text("${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day} 这一天你们相遇了", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),

                  // 3. 今日心情卡片
                  const GlassCard(
                    child: Row(
                      children: [
                        Text("今日心情", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Spacer(),
                        Text("分析中...", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),

                  // 4. 今日日程卡片 (仅展示最新两条)
                  GlassCard(
                    onTap: () { /* TODO: 展开当天的详细日程 */ },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("今日日程", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        _buildListItem("暂无近期日程安排"),
                      ],
                    ),
                  ),

                  // 5. 机器人日记卡片 (仅展示最新两条中期记忆)
                  GlassCard(
                    onTap: () { /* TODO: 跳转进入完整的日记/记忆管理界面 */ },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("专属日记", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        _buildListItem("暂未触发深层记忆沉淀"),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(margin: const EdgeInsets.only(top: 6, right: 8), width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).primaryColor)),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4))),
        ],
      ),
    );
  }
}

// ==========================================
// 界面三：广场 (SquarePage - 动态社区与小游戏)
// ==========================================
class SquarePage extends StatefulWidget {
  const SquarePage({Key? key}) : super(key: key);
  @override
  State<SquarePage> createState() => _SquarePageState();
}

class _SquarePageState extends State<SquarePage> with SingleTickerProviderStateMixin {
  bool isGameMode = false;

  void _toggleMode() {
    HapticFeedback.mediumImpact();
    setState(() { isGameMode = !isGameMode; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isGameMode ? "小游戏引擎" : "广场动态", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  // 涟漪翻转切换按钮
                  GestureDetector(
                    onTap: _toggleMode,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: RotationTransition(turns: anim, child: child)),
                      child: Container(
                        key: ValueKey<bool>(isGameMode),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: renderSvg(isGameMode ? SpaceIcons.switchDynamic : SpaceIcons.switchGame, color: Colors.white, size: 22),
                      ),
                    ),
                  )
                ],
              ),
            ),

            // 视图主体
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(animation), child: child)),
                child: isGameMode ? _buildGameFeed() : _buildDynamicFeed(),
              ),
            )
          ],
        ),
      ),
      floatingActionButton: isGameMode ? null : Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          onPressed: () { /* TODO: 发布图文动态 */ },
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 8,
          child: const Icon(Icons.add, size: 30, color: Colors.white),
        ),
      ),
    );
  }

  // 小游戏列表 (4张大卡片)
  Widget _buildGameFeed() {
    return ListView(
      key: const ValueKey("game_mode"),
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
      children: [
        _buildGameCard("五子棋", "经典双人对弈，考验逻辑与防守", Colors.blueAccent),
        _buildGameCard("井字棋", "轻松休闲，AI随时奉陪", Colors.orangeAccent),
        _buildGameCard("20问猜物", "互猜谜底，看看谁的知识面更广", Colors.purpleAccent),
        _buildGameCard("32张棋牌对战", "特殊无大小王规则，全凭真实算力决胜", Colors.teal),
      ],
    );
  }

  Widget _buildGameCard(String title, String desc, Color color) {
    return GlassCard(
      onTap: () {
        // TODO: 弹出机器人选择，选择后通过 System Prompt 注入规则进入对局
      },
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(width: 60, height: 60, decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(16))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // 动态广场流
  Widget _buildDynamicFeed() {
    return ListView(
      key: const ValueKey("dynamic_mode"),
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
      children: [
        // 占位动态卡片
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade300)),
                  const SizedBox(width: 10),
                  const Expanded(child: Text("系统指引", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  Text("刚刚", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 12),
              const Text("欢迎来到纯本地的动态广场。您的数字生命将在此处自由冲浪、发帖或对您的动态进行留言互动。", style: TextStyle(fontSize: 15, height: 1.5)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildActionBtn(SpaceIcons.heart, "赞"),
                  _buildActionBtn(SpaceIcons.switchDynamic, "评论"),
                  _buildActionBtn(SpaceIcons.share, "分享"),
                ],
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildActionBtn(String svg, String label) {
    return Row(
      children: [
        renderSvg(svg, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ==========================================
// 界面四：我的 (ProfilePage - API配置与微信挂载)
// ==========================================
class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 100),
          children: [
            // 1. 个人名片
            GlassCard(
              onTap: () { /* TODO: 编辑个人资料 */ },
              child: Row(
                children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).primaryColor)),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("创造者", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text("点击编辑个人资料", style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey)
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text("核心引擎与生态", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey))),

            // 2. API 设置
            _buildSettingItem("API 设置 (大模型/识图/STT/TTS)", onTap: _openApiSettingsModal),
            // 3. 本地轻量模型
            _buildSettingItem("本地轻量模型下载", onTap: () {}),
            // 4. 主题与背景
            _buildSettingItem("主题色彩与聊天背景", onTap: () {}),
            // 5. 绑定微信 (OpenClaw 桥接)
            _buildSettingItem("挂载至微信 (OpenClaw生态)", onTap: () {}),

            const SizedBox(height: 20),
            const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text("系统预留", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey))),
            
            _buildSettingItem("普通设置", onTap: () {}),
            _buildSettingItem("高级设置", onTap: () {}),
            _buildSettingItem("支持我们", onTap: () {}),
            _buildSettingItem("关于应用", onTap: () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(String title, {required VoidCallback onTap}) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  // 弹出 API 配置大面板
  void _openApiSettingsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("引擎 API 配置池", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      children: [
                        _buildApiSection("文本 / 识图 / 生图 / STT 模型池", ["DeepSeek", "Siliconflow", "Gitee", "Kimi", "阿里云百炼", "自定义 (兼容 OpenAI)"]),
                        const SizedBox(height: 24),
                        _buildApiSection("文本转语音 (TTS) 模型池", ["Siliconflow", "阿里云百炼", "MiniMax", "自定义"]),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildApiSection(String title, List<String> providers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            GestureDetector(
              onTap: () { /* TODO: 弹窗让用户在 providers 中选择并填入 API Key */ },
              child: Text("+ 新增", style: TextStyle(fontSize: 14, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w800)),
            )
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.04), borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Text("暂未配置任何引擎", style: TextStyle(fontSize: 13, color: Colors.grey))),
        )
      ],
    );
  }
}
