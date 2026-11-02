import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_launch_animation.dart';
import 'db.dart';
import 'legal_pages.dart';
import 'main.dart' show TideMainScaffold;
import 'theme.dart';
import 'ui_chat_room.dart';
import 'ui_create_bot.dart';
import 'ui_profile.dart';

/// Owns the launch sequence so preference loading never replaces a running splash.
class FirstLaunchFlow extends StatefulWidget {
  const FirstLaunchFlow({super.key, required this.onReady});
  final VoidCallback onReady;
  @override
  State<FirstLaunchFlow> createState() => _FirstLaunchFlowState();
}

class _FirstLaunchFlowState extends State<FirstLaunchFlow> {
  SharedPreferences? _prefs;
  Object? _error;
  bool _accepted = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _error = null;
        _accepted =
            prefs.getBool('legal_agreement_accepted') == true &&
            prefs.getBool('legal_age_confirmed') == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : TextButton(onPressed: _load, child: const Text('重新读取启动设置')),
        ),
      );
    }
    return DailyLaunchAnimation(
      force: !_accepted,
      child: _accepted
          ? _ReadyHome(onReady: widget.onReady)
          : LegalAgreementPage(
              requiredAcceptance: true,
              onAccepted: () => setState(() => _accepted = true),
            ),
    );
  }
}

class _ReadyHome extends StatefulWidget {
  const _ReadyHome({required this.onReady});
  final VoidCallback onReady;
  @override
  State<_ReadyHome> createState() => _ReadyHomeState();
}

class _ReadyHomeState extends State<_ReadyHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  @override
  Widget build(BuildContext context) => const NewUserGuide();
}

class NewUserGuide extends StatefulWidget {
  const NewUserGuide({super.key});
  @override
  State<NewUserGuide> createState() => _NewUserGuideState();
}

class _NewUserGuideState extends State<NewUserGuide> {
  int? _step;
  String? _botId;
  bool _busy = false;
  String? _hint;
  static const _titles = [
    '欢迎来到 TideBot',
    '连接你的第一个模型',
    '认识你的专属伙伴',
    '为伙伴选择模型',
    '先熟悉一下聊天室',
    '从一句你好开始',
  ];
  static const _details = [
    '潮起有时，陪伴无期。\n这里的每一段故事，都从你的一句话开始。\n花几分钟，一起让第一位伙伴来到你身边。',
    '打开模型提供商设置，添加服务地址、API Key 和聊天模型并保存。你可以使用自己的服务，调用费用由对应提供商收取。',
    '给伙伴取一个名字，写下性格、背景和说话方式。保存后，我们一起选择它使用的模型。',
    '打开聊天室的模型设置，为这位伙伴选择聊天模型。设置完成后返回这里继续。',
    '顶部的模型设置可切换聊天模型；右上角菜单管理聊天与角色。底部输入文字，扩展入口可发送图片等内容；语音等功能需要另外配置服务和权限。',
    '进入聊天室，在底部输入第一句话并发送。收到这次对话的机器人回复后，引导会自动结束。请求失败时可以修改配置后重试。',
  ];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _step = prefs.getBool('seen_onboarding') == true
          ? 6
          : (prefs.getInt('onboarding_step') ?? 0).clamp(0, 5);
      _botId = prefs.getString('onboarding_bot_id');
    });
  }

  Future<void> _advance([bool finish = false]) async {
    final next = finish ? 6 : (_step! + 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('onboarding_step', next);
    if (next >= 6) await prefs.setBool('seen_onboarding', true);
    if (mounted)
      setState(() {
        _step = next;
        _hint = null;
      });
  }

  Future<Map<String, dynamic>?> _bot() async {
    final bots = await DBManager().queryBots();
    if (bots.isEmpty) return null;
    return bots.firstWhere(
      (bot) => bot['id'] == _botId,
      orElse: () => bots.first,
    );
  }

  Future<void> _act() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hint = null;
    });
    final activeStep = _step;
    try {
      switch (_step) {
        case 0:
        case 4:
          await _advance();
          break;
        case 1:
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _GuideTaskPage(
                onSkip: _advance,
                child: const ApiSettingsPage(),
              ),
            ),
          );
          if (_step != activeStep) break;
          final providers = await DBManager().queryChatProviders();
          if (providers.any(
            (p) =>
                p['base_url'].toString().trim().isNotEmpty &&
                p['model'].toString().trim().isNotEmpty,
          )) {
            await _advance();
          } else if (mounted) {
            setState(() => _hint = '保存一个包含服务地址和聊天模型的提供商后继续，也可以跳过此步骤。');
          }
          break;
        case 2:
          if (!mounted) return;
          final before = await DBManager().queryBots();
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _GuideTaskPage(
                onSkip: _advance,
                child: const CreateBotPage(),
              ),
            ),
          );
          if (_step != activeStep) break;
          final after = await DBManager().queryBots();
          final created = after
              .where((b) => !before.any((old) => old['id'] == b['id']))
              .toList();
          if (created.isNotEmpty) {
            _botId = created.first['id'].toString();
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('onboarding_bot_id', _botId!);
            await _advance();
          }
          break;
        case 3:
        case 5:
          final bot = await _bot();
          if (bot == null) {
            if (mounted)
              setState(() => _hint = '当前没有可选机器人。可以返回创建伙伴，或跳过此步骤后自行配置。');
            break;
          }
          if (!mounted) return;
          if (_step == 3) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _GuideTaskPage(
                  onSkip: _advance,
                  child: ChatRoomPage(botData: bot, openModelSettings: true),
                ),
              ),
            );
            if (_step != activeStep) break;
            final prefs = await SharedPreferences.getInstance();
            final fresh = await _bot();
            final model =
                prefs.getString('chat_model_${bot['id']}') ??
                fresh?['chat_model']?.toString() ??
                '';
            if (model.isNotEmpty &&
                await DBManager().getChatProviderById(model) != null) {
              await _advance();
            } else if (mounted) {
              setState(() => _hint = '尚未选定可用的聊天模型，请完成配置或跳过此步骤。');
            }
          } else {
            final finished = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => _GuidedConversation(bot: bot)),
            );
            final prefs = await SharedPreferences.getInstance();
            if (finished == true || prefs.getBool('seen_onboarding') == true) {
              await _advance(true);
            }
          }
          break;
      }
    } catch (_) {
      if (mounted) setState(() => _hint = '这一步暂时没有完成，请重试，也可以先跳过。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (step == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = TideTheme.of(context);
    return Stack(
      children: [
        const TideMainScaffold(),
        if (step < 6)
          Positioned.fill(
            child: Material(
              color: theme.bgColor.withValues(alpha: .97),
              child: SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        onPressed: _busy ? null : () => _advance(step == 0),
                        child: Text(step == 0 ? '跳过引导' : '跳过此步'),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 28),
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: theme.primary.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Icon(
                                [
                                  Icons.waves_rounded,
                                  Icons.hub_rounded,
                                  Icons.person_add_alt_1_rounded,
                                  Icons.tune_rounded,
                                  Icons.chat_bubble_outline_rounded,
                                  Icons.waving_hand_rounded,
                                ][step],
                                size: 46,
                                color: theme.primary,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              step == 0 ? 'TIDE BOT · 初次见面' : '开启陪伴  $step / 5',
                              style: TextStyle(
                                color: theme.primary,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _titles[step],
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: theme.textStrong,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              _details[step],
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.8,
                                color: theme.textWeak,
                              ),
                            ),
                            if (_hint != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Text(
                                  _hint!,
                                  style: TextStyle(color: theme.primary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: _busy ? null : _act,
                          child: Text(
                            _busy
                                ? '正在等待操作完成…'
                                : [
                                    '一起开始',
                                    '添加模型提供商',
                                    '创建我的伙伴',
                                    '打开模型设置',
                                    '了解了，去打个招呼',
                                    '进入聊天室',
                                  ][step],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GuidedConversation extends StatefulWidget {
  const _GuidedConversation({required this.bot});
  final Map<String, dynamic> bot;
  @override
  State<_GuidedConversation> createState() => _GuidedConversationState();
}

class _GuidedConversationState extends State<_GuidedConversation> {
  bool _finished = false;
  bool _saving = false;
  Future<void> _finish() async {
    if (_finished || _saving) return;
    _saving = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('onboarding_step', 6);
      if (!await prefs.setBool('seen_onboarding', true)) return;
      if (mounted) setState(() => _finished = true);
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Column(
      children: [
        if (!_finished)
          Material(
            color: theme.bgColor,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '发送第一句话 · 伙伴回复后自动结束引导',
                        style: TextStyle(
                          color: theme.textStrong,
                          fontSize: 13,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _finish, child: const Text('跳过此步')),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          key: const ValueKey('guided-chat'),
          child: ChatRoomPage(botData: widget.bot, onReplyCompleted: _finish),
        ),
      ],
    );
  }
}

class _GuideTaskPage extends StatelessWidget {
  const _GuideTaskPage({required this.child, required this.onSkip});
  final Widget child;
  final Future<void> Function() onSkip;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: TideTheme.of(context).bgColor,
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  await onSkip();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('跳过此步'),
              ),
            ],
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );
}
