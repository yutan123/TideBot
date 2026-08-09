import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_permissions.dart';
import 'ui_components.dart';
import 'db.dart';
import 'ai.dart';
import 'global_notice.dart';
import 'theme.dart';
import 'data_dashboard.dart';
import 'sticker_manager_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _userName = '用户';
  String _avatarPath = '';
  final _settings = [
    {'icon': Icons.api_rounded, 'title': 'API 设置', 'page': 'api'},
    {'icon': Icons.cloud_download_rounded, 'title': '本地模型', 'page': 'local'},
    {'icon': Icons.palette_rounded, 'title': '主题设置', 'page': 'theme'},
    {'icon': Icons.tune_rounded, 'title': '普通设置', 'page': 'general'},
    {
      'icon': Icons.settings_suggest_rounded,
      'title': '高级设置',
      'page': 'advanced'
    },
    {'icon': Icons.notifications_rounded, 'title': '通知管理', 'page': 'notify'},
    {'icon': Icons.analytics_rounded, 'title': '数据大盘', 'page': 'dashboard'},
    {'icon': Icons.info_rounded, 'title': '关于 TideBot', 'page': 'about'},
    {'icon': Icons.storage_rounded, 'title': '数据管理', 'page': 'data'},
    {'icon': Icons.feedback_rounded, 'title': '反馈与建议', 'page': 'feedback'},
  ];
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await DBManager().getKV('user_name');
    final avatar = await DBManager().getKV('user_avatar');
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _userName = name;
        if (avatar != null && avatar.isNotEmpty) _avatarPath = avatar;
      });
    }
  }

  Future<void> _pickAvatar() async {
    if (!await AppPermissions.photos(context, feature: '更换头像')) return;
    try {
      final img = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 256);
      if (img == null) return;
      String path = img.path;
      if (path.toLowerCase().endsWith('.heic') ||
          path.toLowerCase().endsWith('.heif')) {
        final converted = await HeifConverter.convert(path);
        if (converted != null) path = converted;
      }
      final dir = await getApplicationDocumentsDirectory();
      final dest =
          '${dir.path}/user_avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).copy(dest);
      await DBManager().insertKV('user_avatar', dest);
      if (mounted) setState(() => _avatarPath = dest);
    } catch (_) {}
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _userName);
    final name = await TideDialogs.show<String>(
        context: context,
        builder: (ctx) => AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            content: TideDialogs.glassContent(context: ctx, children: [
              Text('修改昵称',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont',
                      color: TideTheme.of(ctx).textStrong)),
              const SizedBox(height: 12),
              TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(
                      fontFamily: 'TideFont',
                      color: TideTheme.of(ctx).textStrong),
                  decoration: const InputDecoration(hintText: '输入新昵称')),
              const SizedBox(height: 12),
              TideDialogs.glassButton('保存',
                  onTap: () => Navigator.pop(ctx, ctrl.text.trim())),
            ])));
    if (name != null && name.isNotEmpty && mounted) {
      setState(() => _userName = name);
      await DBManager().insertKV('user_name', name);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
      color: TideTheme.of(context).bgColor,
      child: SafeArea(
          child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(children: [
                _buildProfileCard(),
                const SizedBox(height: 24),
                ..._settings.map((s) => BouncyTap(
                    onTap: () => _onSetting(s), child: _buildSettingItem(s))),
                const SizedBox(height: 20)
              ]))));
  Widget _buildProfileCard() => FrostCard(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        BouncyTap(
            onTap: _pickAvatar,
            child: CircleAvatar(
                radius: 32,
                backgroundColor:
                    TideTheme.of(context).primary.withValues(alpha: 0.15),
                backgroundImage:
                    _avatarPath.isNotEmpty && File(_avatarPath).existsSync()
                        ? FileImage(File(_avatarPath))
                        : null,
                child: _avatarPath.isEmpty || !File(_avatarPath).existsSync()
                    ? Icon(Icons.person_rounded,
                        size: 36, color: TideTheme.of(context).primary)
                    : null)),
        const SizedBox(width: 16),
        Expanded(
            child: BouncyTap(
                onTap: _editName,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_userName,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'TideFont',
                              color: TideTheme.of(context).textStrong)),
                      const SizedBox(height: 4),
                      Text('点击昵称修改名字',
                          style: TextStyle(
                              fontSize: 13,
                              color: TideTheme.of(context).textFaint,
                              fontFamily: 'TideFont')),
                    ]))),
        Icon(Icons.edit_rounded,
            size: 18, color: TideTheme.of(context).textFaint),
      ]));
  Widget _buildSettingItem(Map<String, dynamic> s) => FrostCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(s['icon'] as IconData,
            size: 22, color: TideTheme.of(context).primary),
        const SizedBox(width: 14),
        Expanded(
            child: Text(s['title'] ?? '',
                style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'TideFont',
                    color: TideTheme.of(context).textStrong))),
        Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: TideTheme.of(context).textFaint)
      ]));
  Future<String?> _pickDataBot(String title) async {
    final bots = await DBManager().exportableBots();
    if (!mounted || bots.isEmpty) return null;
    return showTideSheet<String>(
      context: context,
      height: 420,
      child: ListView(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'TideFont',
                    color: TideTheme.of(context).textStrong))),
        ...bots.map((bot) => ListTile(
              leading: TideBotAvatar(
                  name: bot['name']?.toString() ?? '未命名',
                  path: bot['avatar']?.toString(),
                  size: 42),
              title: Text(bot['name']?.toString() ?? '未命名机器人',
                  style: const TextStyle(fontFamily: 'TideFont')),
              onTap: () => Navigator.pop(context, bot['id']?.toString()),
            )),
      ]),
    );
  }

  Future<void> _exportSelectedChat() async {
    final botId = await _pickDataBot('选择要导出的机器人');
    if (botId == null) return;
    final path = await DBManager().exportBotChat(botId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('聊天记录已导出：$path',
            style: const TextStyle(fontFamily: 'TideFont')),
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _importSelectedChat() async {
    final botId = await _pickDataBot('选择要导入到的机器人');
    if (botId == null) return;
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final count = await DBManager().importBotChat(botId, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导入 $count 条聊天记录',
              style: const TextStyle(fontFamily: 'TideFont')),
          behavior: SnackBarBehavior.floating));
    } on FormatException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message,
                style: const TextStyle(fontFamily: 'TideFont'))));
    }
  }

  void _onSetting(Map<String, dynamic> s) {
    switch (s['page']) {
      case 'api':
        Navigator.push(
            context,
            PageRouteBuilder(
                pageBuilder: (_, __, ___) => const ApiSettingsPage(),
                transitionsBuilder: (_, a, __, c) =>
                    FadeTransition(opacity: a, child: c),
                transitionDuration: const Duration(milliseconds: 300)));
        break;
      case 'local':
        Navigator.push(
            context,
            PageRouteBuilder(
                pageBuilder: (_, __, ___) => const LocalModelPage(),
                transitionsBuilder: (_, a, __, c) =>
                    FadeTransition(opacity: a, child: c),
                transitionDuration: const Duration(milliseconds: 300)));
        break;
      case 'theme':
        _showThemePicker();
        break;
      case 'general':
        _showGeneralSettings();
        break;
      case 'advanced':
        _showAdvancedSettings();
        break;
      case 'notify':
        _showNotificationSettings();
        break;
      case 'about':
        showTideSheet(
            context: context,
            height: 300,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('关于 TideBot',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 12),
                      Text('版本: 1.0.0',
                          style: TextStyle(
                              fontSize: 14,
                              color: TideTheme.of(context).textWeak,
                              fontFamily: 'TideFont')),
                      Text('本地化沉浸式多模态 AI 伴侣',
                          style: TextStyle(
                              fontSize: 14,
                              color: TideTheme.of(context).textWeak,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 8),
                      Text('100% 本地运行，隐私无忧。',
                          style: TextStyle(
                              fontSize: 13,
                              color: TideTheme.of(context).textWeak,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 16),
                      Text('开发者: yutan123',
                          style: TextStyle(
                              fontSize: 13,
                              color: TideTheme.of(context).textFaint,
                              fontFamily: 'TideFont'))
                    ])));
        break;
      case 'data':
        showTideSheet(
            context: context,
            height: 290,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('数据管理',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 16),
                      ListTile(
                          leading: Icon(Icons.download_rounded,
                              color: TideTheme.of(context).primary),
                          title: const Text('导出聊天记录',
                              style: TextStyle(fontFamily: 'TideFont')),
                          onTap: () async {
                            Navigator.pop(context);
                            await _exportSelectedChat();
                          }),
                      ListTile(
                          leading: Icon(Icons.upload_file_rounded,
                              color: TideTheme.of(context).primary),
                          title: const Text('导入聊天记录',
                              style: TextStyle(fontFamily: 'TideFont')),
                          subtitle: const Text('仅支持 TideBot 导出的 JSON 文件',
                              style: TextStyle(
                                  fontFamily: 'TideFont', fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(context);
                            await _importSelectedChat();
                          })
                    ])));
        break;
      case 'dashboard':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataDashboardPage()),
        );
        break;
      case 'privacy':
        showTideSheet(
            context: context,
            height: 350,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('隐私与安全',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 12),
                      const Text('TideBot 采用纯本地架构：',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'TideFont')),
                      const SizedBox(height: 8),
                      Text(
                          '所有聊天数据存储在本地数据库\nAPI 密钥加密存储在本地\n无任何数据上传\n无统计 SDK, 无广告',
                          style: TextStyle(
                              fontSize: 13,
                              color: TideTheme.of(context).textWeak,
                              fontFamily: 'TideFont',
                              height: 1.8))
                    ])));
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${s['title']}功能开发中...',
                style: const TextStyle(fontFamily: 'TideFont')),
            behavior: SnackBarBehavior.floating));
    }
  }

  // 主题设置的配色圆点（取 theme.dart 的日间主色作为预览）
  Color _themeDotPrimary(String id) {
    final map = {
      'rose': const Color(0xFFD98C94),
      'aurora': const Color(0xFF6C8CD5),
      'lavender': const Color(0xFF9B8AC4),
      'sky': const Color(0xFF5D9BC5),
      'mint': const Color(0xFF5FAF8A),
      'peach': const Color(0xFFE39A6B),
      'plum': const Color(0xFF8E74B4),
      'teal': const Color(0xFF4FA79C),
      'sunset': const Color(0xFFE06A5A),
      'ocean': const Color(0xFF3E7CB1),
      'pinkg': const Color(0xFFE07A9A),
      'night': const Color(0xFF6B5FAE),
    };
    return map[id] ?? const Color(0xFF6C8CD5);
  }

  void _showThemePicker() {
    showTideSheet(
        context: context,
        height: 560,
        child: StatefulBuilder(builder: (ctx, setSt) {
          final t = TideTheme.of(ctx, listen: false);
          String mi = 'auto';
          if (!t.hasManualMode) {
            mi = 'auto';
          } else if (t.mode == ThemeMode.dark)
            mi = 'dark';
          else
            mi = 'light';
          final options = TideTheme.themeOptions;
          return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题 + 右上角日/夜切换按钮
                    Row(children: [
                      const Expanded(
                          child: Text('主题设置',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'TideFont'))),
                      // 日/夜/跟随 循环切换（system->light->dark->system）
                      GestureDetector(
                        onTap: () => t.cycleMode().then((_) {
                          if (ctx.mounted) setSt(() {});
                        }),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: t.bgColor == const Color(0xFFF2F2F7)
                                    ? t.primary.withValues(alpha: 0.12)
                                    : Colors.white.withValues(alpha: 0.12)),
                            child: Row(children: [
                              Icon(
                                  mi == 'dark'
                                      ? Icons.dark_mode_rounded
                                      : (mi == 'auto'
                                          ? Icons.brightness_auto_rounded
                                          : Icons.wb_sunny_rounded),
                                  size: 16,
                                  color: t.primary),
                              const SizedBox(width: 6),
                              Text(
                                  mi == 'dark'
                                      ? '夜间'
                                      : (mi == 'auto' ? '跟随系统' : '日间'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'TideFont',
                                      color: t.primary)),
                            ])),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('选择你喜欢的配色方案，日夜均跟随系统',
                        style: TextStyle(
                            fontSize: 13,
                            color: TideTheme.of(context).textWeak,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 16),
                    Expanded(
                        child: ListView(
                            children: options.map((item) {
                      final id = item['id']!;
                      final name = item['name']!;
                      final active = t.name == id;
                      return BouncyTap(
                        onTap: () {
                          t.setTheme(id);
                          setSt(() {});
                        },
                        child: FrostCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _themeDotPrimary(id)),
                                child: active
                                    ? const Icon(Icons.check,
                                        color: Colors.white, size: 18)
                                    : null),
                            const SizedBox(width: 14),
                            Expanded(
                                child: Text(name,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontFamily: 'TideFont',
                                        color:
                                            TideTheme.of(context).textStrong))),
                            if (active)
                              Icon(Icons.check_circle,
                                  color: TideTheme.of(ctx).primary, size: 20),
                          ]),
                        ),
                      );
                    }).toList())),
                    const SizedBox(height: 12),
                    BouncyTap(
                      onTap: () async {
                        await t.restoreDefaults();
                        if (ctx.mounted) setSt(() {});
                      },
                      child: Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: t.buttonSecondary),
                          child: Center(
                              child: Text('恢复默认主题与背景',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: t.textStrong,
                                      fontFamily: 'TideFont')))),
                    ),
                    const SizedBox(height: 8),
                    // 背景设置入口：上传图片作为聊天背景
                    BouncyTap(
                      onTap: () {
                        _pickChatBg();
                      },
                      child: Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: TideTheme.of(ctx).primary)),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.wallpaper_rounded,
                                    size: 20, color: TideTheme.of(ctx).primary),
                                const SizedBox(width: 8),
                                Text('聊天背景',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: TideTheme.of(ctx).primary,
                                        fontFamily: 'TideFont')),
                                if (t.chatBg.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check_circle,
                                      size: 16, color: Color(0xFF34C759))
                                ],
                              ])),
                    ),
                    const SizedBox(height: 8),
                  ]));
        }));
  }

  // 选择聊天背景图片
  Future<void> _pickChatBg() async {
    final tide = TideTheme.of(context, listen: false);
    try {
      if (!await AppPermissions.photos(context, feature: '设置聊天背景')) return;
      final picker = ImagePicker();
      final img =
          await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (img != null) {
        String path = img.path;
        if (path.toLowerCase().endsWith('.heic') ||
            path.toLowerCase().endsWith('.heif')) {
          try {
            final converted = await HeifConverter.convert(path);
            if (converted != null) path = converted;
          } catch (_) {}
        }
        final dir = await getApplicationDocumentsDirectory();
        final dest =
            '${dir.path}/chat_bg_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(path).copy(dest);
        await tide.setChatBg(dest);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('聊天背景已更新', style: TextStyle(fontFamily: 'TideFont')),
              backgroundColor: Color(0xFF34C759),
              behavior: SnackBarBehavior.floating));
        }
      }
    } catch (_) {}
  }

  void _showGeneralSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
    );
  }

  void _showAdvancedSettings() {
    showTideSheet(
        context: context,
        height: 210,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('高级设置',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont',
                      color: TideTheme.of(context).textStrong)),
              const SizedBox(height: 12),
              Text('高级模型、后台任务与调试选项将逐步在这里提供。',
                  style: TextStyle(
                      fontFamily: 'TideFont',
                      color: TideTheme.of(context).textWeak)),
            ])));
  }

  void _showNotificationSettings() async {
    final db = DBManager();
    final unread = (await db.getKV('unread_notifications')) != 'false';
    final keepRunning = (await db.getKV('persistent_notification')) == 'true';
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NotificationSettingsPage(
        initialUnread: unread,
        initialKeepRunning: keepRunning,
      ),
    ));
  }
}

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  bool _showTime = true;
  bool _showAvatar = false;
  bool _streaming = true;
  bool _segmentedReply = true;
  bool _randomReplyDelay = false;
  bool _timeAwareness = true;
  bool _proactiveReply = true;
  bool _botPosts = false;
  bool _imageGeneration = true;
  bool _webSearch = false;
  bool _stickers = false;
  String _imageStyle = '写实';
  String _searchProvider = 'Tavily';
  int _stickerChance = 50;
  final TextEditingController _searchKeyController = TextEditingController();
  bool _showSearchKey = false;
  final TextEditingController _stickerChanceController =
      TextEditingController(text: '50');
  int _proactiveMin = 60;
  int _proactiveMax = 90;
  int _speed = 50;
  final TextEditingController _streamSpeedController =
      TextEditingController(text: '50');
  final TextEditingController _replyDelayMinController =
      TextEditingController(text: '0');
  final TextEditingController _replyDelayMaxController =
      TextEditingController(text: '2');
  final TextEditingController _proactiveMinController =
      TextEditingController(text: '60');
  final TextEditingController _proactiveMaxController =
      TextEditingController(text: '90');
  final TextEditingController _botPostsPerDayController =
      TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DBManager();
    final speed = int.tryParse(await db.getKV('streaming_speed') ?? '');
    if (!mounted) return;
    setState(() {
      _showTime = true;
      _showAvatar = false;
      _streaming = true;
      _speed = (speed ?? 50).clamp(1, 100);
      _streamSpeedController.text = _speed.toString();
    });
    final time = await db.getKV('show_message_time');
    final avatar = await db.getKV('show_chat_avatar');
    final stream =
        await db.getKV('streaming_output') ?? await db.getKV('streaming_input');
    final segmentedReply = await db.getKV('segmented_reply_enabled');
    final randomReplyDelay = await db.getKV('random_reply_delay_enabled');
    final replyDelayMin = await db.getKV('random_reply_delay_min_seconds');
    final replyDelayMax = await db.getKV('random_reply_delay_max_seconds');
    final timeAwareness = await db.getKV('time_awareness');
    final proactiveReply = await db.getKV('proactive_reply');
    final botPosts = await db.getKV('bot_posts_enabled');
    final imageGeneration = await db.getKV('bot_image_generation_enabled');
    final imageStyle = await db.getKV('bot_image_style');
    final webSearch = await db.getKV('web_search_enabled');
    final searchProvider = await db.getKV('web_search_provider');
    final searchKey = await db.getKV('web_search_api_key');
    final stickers = await db.getKV('bot_stickers_enabled');
    final stickerChance =
        int.tryParse(await db.getKV('bot_sticker_chance') ?? '');
    final botPostsPerDay =
        int.tryParse(await db.getKV('bot_posts_per_day') ?? '');
    final proactiveMin =
        int.tryParse(await db.getKV('proactive_min_minutes') ?? '');
    final proactiveMax =
        int.tryParse(await db.getKV('proactive_max_minutes') ?? '');
    if (!mounted) return;
    setState(() {
      _showTime = time != 'false';
      _showAvatar = avatar == 'true';
      _streaming = stream != 'false';
      _segmentedReply = segmentedReply != 'false';
      _randomReplyDelay = randomReplyDelay == 'true';
      _replyDelayMinController.text =
          (int.tryParse(replyDelayMin ?? '') ?? 0).clamp(0, 60).toString();
      _replyDelayMaxController.text =
          (int.tryParse(replyDelayMax ?? '') ?? 2).clamp(0, 60).toString();
      _timeAwareness = timeAwareness != 'false';
      _proactiveReply = proactiveReply != 'false';
      _botPosts = botPosts == 'true';
      _imageGeneration = imageGeneration != 'false';
      _imageStyle =
          ['写实', '动漫', '科幻', '自定义'].contains(imageStyle) ? imageStyle! : '写实';
      _webSearch = webSearch == 'true';
      _searchProvider = _displaySearchProvider(
          searchProvider?.isNotEmpty == true ? searchProvider! : '');
      _searchKeyController.text = searchKey ?? '';
      _stickers = stickers == 'true';
      _stickerChance = (stickerChance ?? 50).clamp(1, 100);
      _stickerChanceController.text = _stickerChance.toString();
      _botPostsPerDayController.text =
          (botPostsPerDay ?? 1).clamp(1, 10).toString();
      _proactiveMin = (proactiveMin ?? 60).clamp(1, 1440);
      _proactiveMax = (proactiveMax ?? 90).clamp(_proactiveMin, 1440);
      _proactiveMinController.text = _proactiveMin.toString();
      _proactiveMaxController.text = _proactiveMax.toString();
      _streamSpeedController.text = _speed.toString();
    });
  }

  @override
  void dispose() {
    _streamSpeedController.dispose();
    _replyDelayMinController.dispose();
    _replyDelayMaxController.dispose();
    _proactiveMinController.dispose();
    _proactiveMaxController.dispose();
    _botPostsPerDayController.dispose();
    _searchKeyController.dispose();
    _stickerChanceController.dispose();
    super.dispose();
  }

  String _displaySearchProvider(String raw) {
    if (raw.contains('Tavily')) return 'Tavily';
    if (raw.contains('博查') || raw.contains('Bocha')) return '博查 Bocha';
    if (raw.contains('Serper')) return 'Serper';
    if (raw.contains('Brave')) return 'Brave Search';
    if (raw.contains('Bing')) return 'Bing Web Search';
    return 'Tavily';
  }

  String _searchKeyLabel(TideTheme theme) => '搜索 API Key';

  String get _searchKeyHint => '填写所选搜索服务商提供的 API Key；常规搜索无结果时会自动尝试内部兜底能力。';

  Future<void> _save(String key, String value) async {
    await DBManager().insertKV(key, value);
  }

  Widget _choiceField({
    required TideTheme theme,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onPick,
    Widget? icon,
  }) {
    return BouncyTap(
      onTap: () async {
        final picked = await showTideSheet<String>(
          context: context,
          height: 360,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              Text(label,
                  style: TextStyle(
                      color: theme.textStrong,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 8),
              ...options.map((option) => ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    title: Text(option,
                        style: TextStyle(
                            color: theme.textStrong, fontFamily: 'TideFont')),
                    trailing: option == value
                        ? Icon(Icons.check_rounded, color: theme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, option),
                  )),
            ],
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          if (icon != null) ...[icon, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        color: theme.textWeak,
                        fontSize: 11,
                        fontFamily: 'TideFont')),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: theme.textStrong, fontFamily: 'TideFont')),
              ],
            ),
          ),
          Icon(Icons.expand_more_rounded, color: theme.iconMuted),
        ]),
      ),
    );
  }

  Widget _settingSwitch(
          {required TideTheme theme,
          required String title,
          String? help,
          required bool value,
          required ValueChanged<bool> onChanged,
          Widget? child}) =>
      Column(children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Row(children: [
            Text(title, style: const TextStyle(fontFamily: 'TideFont')),
            if (help != null)
              IconButton(
                  icon: Icon(Icons.help_outline_rounded,
                      size: 18, color: theme.textWeak),
                  tooltip: '说明',
                  onPressed: () => TideDialogs.show(
                      context: context,
                      builder: (ctx) => AlertDialog(
                              backgroundColor: theme.surface,
                              title: Text(title,
                                  style: TextStyle(
                                      color: theme.textStrong,
                                      fontFamily: 'TideFont')),
                              content: Text(help,
                                  style: TextStyle(
                                      color: theme.textWeak,
                                      fontFamily: 'TideFont',
                                      height: 1.5)),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('知道了',
                                        style:
                                            TextStyle(fontFamily: 'TideFont')))
                              ])))
          ]),
          value: value,
          activeThumbColor: theme.primary,
          onChanged: onChanged,
        ),
        if (child != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: child),
      ]);

  InputDecoration _roundInput(TideTheme theme,
      {required String label, Widget? icon}) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.border));
    return InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: icon,
        filled: true,
        fillColor: theme.surfaceVariant,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: BorderSide(color: theme.primary, width: 1.5)),
        border: border);
  }

  Widget _replyDelayRange(TideTheme theme) => Row(children: [
        Expanded(
            child: TextField(
                controller: _replyDelayMinController,
                keyboardType: TextInputType.number,
                style:
                    TextStyle(color: theme.textStrong, fontFamily: 'TideFont'),
                decoration: _roundInput(theme, label: '最短（秒）'),
                onChanged: (value) {
                  final n = int.tryParse(value);
                  final max = int.tryParse(_replyDelayMaxController.text) ?? 2;
                  if (n != null && n >= 0 && n <= max && n <= 60) {
                    _save('random_reply_delay_min_seconds', '$n');
                  }
                })),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('至',
                style:
                    TextStyle(color: theme.textWeak, fontFamily: 'TideFont'))),
        Expanded(
            child: TextField(
                controller: _replyDelayMaxController,
                keyboardType: TextInputType.number,
                style:
                    TextStyle(color: theme.textStrong, fontFamily: 'TideFont'),
                decoration: _roundInput(theme, label: '最长（秒）'),
                onChanged: (value) {
                  final n = int.tryParse(value);
                  final min = int.tryParse(_replyDelayMinController.text) ?? 0;
                  if (n != null && n >= min && n <= 60) {
                    _save('random_reply_delay_max_seconds', '$n');
                  }
                })),
      ]);

  Widget _compactRange(TideTheme theme) => Row(children: [
        Expanded(
            child: TextField(
                controller: _proactiveMinController,
                keyboardType: TextInputType.number,
                style:
                    TextStyle(color: theme.textStrong, fontFamily: 'TideFont'),
                decoration: _roundInput(theme, label: '最短（分钟）'),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 1 && n <= _proactiveMax) {
                    _proactiveMin = n;
                    _save('proactive_min_minutes', '$n');
                  }
                })),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('至',
                style:
                    TextStyle(color: theme.textWeak, fontFamily: 'TideFont'))),
        Expanded(
            child: TextField(
                controller: _proactiveMaxController,
                keyboardType: TextInputType.number,
                style:
                    TextStyle(color: theme.textStrong, fontFamily: 'TideFont'),
                decoration: _roundInput(theme, label: '最长（分钟）'),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= _proactiveMin && n <= 1440) {
                    _proactiveMax = n;
                    _save('proactive_max_minutes', '$n');
                  }
                })),
      ]);

  Widget _compactPostsPerDay(TideTheme theme) => TextField(
      controller: _botPostsPerDayController,
      keyboardType: TextInputType.number,
      style: TextStyle(color: theme.textStrong, fontFamily: 'TideFont'),
      decoration: _roundInput(theme,
          label: '每个机器人每天发布数量（1–10）',
          icon:
              Icon(Icons.dynamic_feed_rounded, color: theme.primary, size: 19)),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null && n >= 1 && n <= 10) _save('bot_posts_per_day', '$n');
      });

  Widget _compactSpeed(TideTheme theme) => TextField(
      controller: _streamSpeedController,
      keyboardType: TextInputType.number,
      style: TextStyle(color: theme.textStrong, fontFamily: 'TideFont'),
      decoration: _roundInput(theme,
          label: '显示速度（1–100）',
          icon: Icon(Icons.speed_rounded, color: theme.primary, size: 19)),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null && n >= 1 && n <= 100) {
          _speed = n;
          _save('streaming_speed', '$n');
        }
      });

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        title: const Text('普通设置', style: TextStyle(fontFamily: 'TideFont')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _sectionHeader(theme, '对话表现', Icons.forum_outlined),
          FrostCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _settingSwitch(
                theme: theme,
                title: '显示消息发送时间',
                value: _showTime,
                onChanged: (v) {
                  setState(() => _showTime = v);
                  _save('show_message_time', '$v');
                },
              ),
              _settingSwitch(
                theme: theme,
                title: '聊天界面显示头像',
                value: _showAvatar,
                onChanged: (v) {
                  setState(() => _showAvatar = v);
                  _save('show_chat_avatar', '$v');
                },
              ),
              _settingSwitch(
                theme: theme,
                title: '现实时间感知',
                help: '发送请求时，在末尾附注现实时间；稳定人设提示保持不变，以提升缓存命中率。',
                value: _timeAwareness,
                onChanged: (v) {
                  setState(() => _timeAwareness = v);
                  _save('time_awareness', '$v');
                },
              ),
              _settingSwitch(
                theme: theme,
                title: '分段回复',
                help: '默认开启。模型回复会按自然句逐段呈现，让聊天节奏更接近真人。',
                value: _segmentedReply,
                onChanged: (v) {
                  setState(() => _segmentedReply = v);
                  _save('segmented_reply_enabled', '$v');
                },
              ),
              _settingSwitch(
                theme: theme,
                title: '随机延迟回复',
                help: '开启后，模型生成完成及每一段后续消息都会在下方秒数范围内随机等待。',
                value: _randomReplyDelay,
                onChanged: (v) {
                  setState(() => _randomReplyDelay = v);
                  _save('random_reply_delay_enabled', '$v');
                },
                child: _randomReplyDelay ? _replyDelayRange(theme) : null,
              ),
              _settingSwitch(
                theme: theme,
                title: '流式输出',
                help: '模型支持时逐步呈现回复；速度仅影响界面显示，不影响模型生成。',
                value: _streaming,
                onChanged: (v) {
                  setState(() => _streaming = v);
                  _save('streaming_output', '$v');
                },
                child: _streaming ? _compactSpeed(theme) : null,
              ),
            ]),
          ),
          _sectionHeader(theme, '主动与智能', Icons.auto_awesome_outlined),
          FrostCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _settingSwitch(
                theme: theme,
                title: '主动回复',
                help: '应用保持运行时，机器人会在连续沉默达到下方随机区间后尝试自然开启话题。',
                value: _proactiveReply,
                onChanged: (v) {
                  setState(() => _proactiveReply = v);
                  _save('proactive_reply', '$v');
                },
                child: _proactiveReply ? _compactRange(theme) : null,
              ),
              _settingSwitch(
                theme: theme,
                title: '联网搜索',
                help: '仅开启后机器人才能按需搜索实时信息。填写对应搜索服务商 API Key 后可用。',
                value: _webSearch,
                onChanged: (v) {
                  setState(() => _webSearch = v);
                  _save('web_search_enabled', '$v');
                },
                child: _webSearch
                    ? Column(children: [
                        _choiceField(
                          theme: theme,
                          label: '搜索服务商',
                          value: _searchProvider,
                          options: const [
                            'Tavily',
                            '博查 Bocha',
                            'Serper',
                            'Brave Search',
                            'Bing Web Search',
                          ],
                          icon: Icon(Icons.travel_explore_rounded,
                              color: theme.primary),
                          onPick: (value) {
                            setState(() => _searchProvider = value);
                            _save('web_search_provider', value);
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchKeyController,
                          obscureText: !_showSearchKey,
                          style: TextStyle(
                              color: theme.textStrong, fontFamily: 'TideFont'),
                          decoration: _roundInput(theme,
                                  label: _searchKeyLabel(theme),
                                  icon: Icon(Icons.key_rounded,
                                      color: theme.primary))
                              .copyWith(
                            suffixIcon: IconButton(
                              tooltip:
                                  _showSearchKey ? '隐藏 API Key' : '显示 API Key',
                              onPressed: () => setState(
                                  () => _showSearchKey = !_showSearchKey),
                              icon: Icon(
                                _showSearchKey
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: theme.textWeak,
                              ),
                            ),
                          ),
                          onChanged: (value) =>
                              _save('web_search_api_key', value.trim()),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchKeyHint,
                          style: TextStyle(
                              color: theme.textWeak,
                              fontSize: 11,
                              fontFamily: 'TideFont',
                              height: 1.5),
                        ),
                      ])
                    : null,
              ),
              _settingSwitch(
                theme: theme,
                title: '机器人生图',
                help: '开启后机器人可在需要生成图片时使用生图能力，并遵循下方默认风格。关闭后机器人不会感知此工具存在。',
                value: _imageGeneration,
                onChanged: (v) {
                  setState(() => _imageGeneration = v);
                  _save('bot_image_generation_enabled', '$v');
                },
                child: _imageGeneration
                    ? _choiceField(
                        theme: theme,
                        label: '默认生图风格',
                        value: _imageStyle,
                        options: const ['写实', '动漫', '科幻', '自定义'],
                        icon:
                            Icon(Icons.palette_outlined, color: theme.primary),
                        onPick: (value) {
                          setState(() => _imageStyle = value);
                          _save('bot_image_style', value);
                        },
                      )
                    : null,
              ),
            ]),
          ),
          _sectionHeader(theme, '机器人互动', Icons.emoji_emotions_outlined),
          FrostCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _settingSwitch(
                theme: theme,
                title: '机器人发送表情包',
                help: '仅从你自己维护的素材池中选择。关闭后机器人不知道表情包功能存在。',
                value: _stickers,
                onChanged: (v) {
                  setState(() => _stickers = v);
                  _save('bot_stickers_enabled', '$v');
                },
                child: _stickers
                    ? Column(children: [
                        TextField(
                          controller: _stickerChanceController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              color: theme.textStrong, fontFamily: 'TideFont'),
                          decoration: _roundInput(theme,
                              label: '发送概率（1–100）',
                              icon: Icon(Icons.sentiment_satisfied_alt_rounded,
                                  color: theme.primary)),
                          onChanged: (value) {
                            final chance = int.tryParse(value);
                            if (chance != null &&
                                chance >= 1 &&
                                chance <= 100) {
                              _stickerChance = chance;
                              _save('bot_sticker_chance', '$chance');
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                  Icons.add_photo_alternate_outlined),
                              label: const Text('添加和管理表情包',
                                  style: TextStyle(fontFamily: 'TideFont')),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const StickerManagerPage())),
                            )),
                      ])
                    : null,
              ),
              _settingSwitch(
                theme: theme,
                title: '机器人发布动态',
                help: '开启后，每位已配置聊天模型的机器人会在进入广场时按设置数量生成独立动态，并按日期去重。',
                value: _botPosts,
                onChanged: (v) {
                  setState(() => _botPosts = v);
                  _save('bot_posts_enabled', '$v');
                },
                child: _botPosts ? _compactPostsPerDay(theme) : null,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(TideTheme theme, String title, IconData icon) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(children: [
          Icon(icon, size: 16, color: theme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  color: theme.textStrong,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  fontFamily: 'TideFont')),
        ]),
      );
}

class NotificationSettingsPage extends StatefulWidget {
  final bool initialUnread;
  final bool initialKeepRunning;

  const NotificationSettingsPage({
    super.key,
    required this.initialUnread,
    required this.initialKeepRunning,
  });

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late bool _unread;
  late bool _keepRunning;
  bool _switchingPersistentNotification = false;

  @override
  void initState() {
    super.initState();
    _unread = widget.initialUnread;
    _keepRunning = widget.initialKeepRunning;
  }

  Future<void> _setValue(String key, bool value) async {
    await DBManager().insertKV(key, value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar: AppBar(
        title: const Text('通知管理', style: TextStyle(fontFamily: 'TideFont')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          FrostCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('机器人未读消息通知',
                      style: TextStyle(fontFamily: 'TideFont')),
                  subtitle: const Text('APP 不在前台时提醒',
                      style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                  value: _unread,
                  activeThumbColor: theme.primary,
                  onChanged: (value) async {
                    if (value && !await AppPermissions.notifications(context)) {
                      return;
                    }
                    setState(() => _unread = value);
                    await _setValue('unread_notifications', value);
                  },
                ),
                SwitchListTile(
                  title: const Text('TideBot 正在运行中',
                      style: TextStyle(fontFamily: 'TideFont')),
                  subtitle: const Text('开启后显示持久化状态通知',
                      style: TextStyle(fontFamily: 'TideFont', fontSize: 12)),
                  value: _keepRunning,
                  activeThumbColor: theme.primary,
                  onChanged: _switchingPersistentNotification
                      ? null
                      : (value) async {
                          if (value &&
                              !await AppPermissions.notifications(context)) {
                            return;
                          }
                          if (!mounted) return;
                          setState(
                              () => _switchingPersistentNotification = true);
                          try {
                            // The service is configured during app startup. On a
                            // fast first visit it may still be initializing, so
                            // persist the opt-in before requesting its start.
                            await _setValue('persistent_notification', value);
                            final service = FlutterBackgroundService();
                            if (value) {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 250),
                              );
                              await service.startService();
                            } else {
                              service.invoke('stopService');
                            }
                            if (!mounted) return;
                            setState(() => _keepRunning = value);
                          } catch (e) {
                            if (!mounted) return;
                            GlobalNotice.show(
                              '无法切换运行通知：$e',
                              color: Theme.of(context).colorScheme.error,
                            );
                          } finally {
                            if (mounted) {
                              setState(() =>
                                  _switchingPersistentNotification = false);
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});
  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _ttsProviders = [];
  bool _loading = true;
  final _presets = [
    {
      'name': 'DeepSeek',
      'url': 'https://api.deepseek.com/v1',
      'models': 'deepseek-chat'
    },
    {
      'name': 'SiliconFlow',
      'url': 'https://api.siliconflow.cn/v1',
      'models': 'Qwen/Qwen2.5-7B-Instruct'
    },
    {
      'name': '阿里云百炼',
      'url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'models': 'qwen-plus'
    },
    {
      'name': 'Kimi',
      'url': 'https://api.moonshot.cn/v1',
      'models': 'moonshot-v1-8k'
    },
    {
      'name': 'Gitee AI',
      'url': 'https://ai.gitee.com/v1',
      'models': 'Qwen2.5-7B-Instruct'
    },
  ];
  final _ttsPresets = [
    {
      'name': 'SiliconFlow TTS',
      'url': 'https://api.siliconflow.cn/v1',
      'models': 'FunAudioLLM/CosyVoice2-0.5B',
      'voice': 'default'
    },
    {
      'name': '阿里云百炼 TTS',
      'url':
          'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-to-speech',
      'models': 'cosyvoice-v1',
      'voice': 'default'
    },
    {
      'name': 'MiniMax TTS',
      'url': 'https://api.minimax.chat/v1',
      'models': 'speech-01',
      'voice': 'default'
    },
  ];
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final db = DBManager();
    final raw = await db.getKV('provider_list');
    final ttsRaw = await db.getKV('tts_provider_list');
    List<Map<String, dynamic>> list = [];
    List<Map<String, dynamic>> ttsList = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        list = decoded.map((e) => e as Map<String, dynamic>).toList();
      } catch (_) {}
    }
    if (ttsRaw != null && ttsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(ttsRaw) as List;
        ttsList = decoded.map((e) => e as Map<String, dynamic>).toList();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _providers = list;
        _ttsProviders = ttsList;
        _loading = false;
      });
    }
  }

  Future<void> _saveList() async {
    await DBManager().insertKV('provider_list', jsonEncode(_providers));
    await DBManager().insertKV('tts_provider_list', jsonEncode(_ttsProviders));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('已保存', style: TextStyle(fontFamily: 'TideFont')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: TideTheme.of(context).primary));
    }
  }

  void _addProvider() {
    showTideSheet(
        context: context,
        height: 520,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('新增模型提供商',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presets
                            .map((p) => BouncyTap(
                                onTap: () {
                                  Navigator.pop(context);
                                  _showAddDialog(p['name']!, p['url']!, '',
                                      p['models']!, false);
                                },
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.white
                                            .withValues(alpha: 0.8)),
                                    child: Text(p['name']!,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontFamily: 'TideFont')))))
                            .toList()),
                    const SizedBox(height: 12),
                    BouncyTap(
                        onTap: () {
                          Navigator.pop(context);
                          _showAddDialog('自定义', '', '', '', false);
                        },
                        child: Container(
                            width: double.infinity,
                            height: 44,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: TideTheme.of(context).primary)),
                            child: Center(
                                child: Text('自定义',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: TideTheme.of(context).primary,
                                        fontFamily: 'TideFont'))))),
                    const SizedBox(height: 24),
                    const Text('文本转语音 (TTS)',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'TideFont')),
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ttsPresets
                            .map((p) => BouncyTap(
                                onTap: () {
                                  Navigator.pop(context);
                                  _showTtsDialog(p['name']!, p['url']!, '',
                                      p['models']!, p['voice']!);
                                },
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.white
                                            .withValues(alpha: 0.8)),
                                    child: Text(p['name']!,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontFamily: 'TideFont')))))
                            .toList()),
                    const SizedBox(height: 12),
                    BouncyTap(
                        onTap: () {
                          Navigator.pop(context);
                          _showTtsDialog('自定义', '', '', '', '');
                        },
                        child: Container(
                            width: double.infinity,
                            height: 44,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: TideTheme.of(context).primary)),
                            child: Center(
                                child: Text('自定义 TTS',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: TideTheme.of(context).primary,
                                        fontFamily: 'TideFont'))))),
                  ]),
            )));
  }

  void _showAddDialog(
      String name, String url, String key, String models, bool isTts) {
    final nCtrl = TextEditingController(text: name);
    final uCtrl = TextEditingController(text: url);
    final kCtrl = TextEditingController(text: key);
    final mCtrl = TextEditingController(text: models);
    TideDialogs.show(
        context: context,
        builder: (ctx) => AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            content: TideDialogs.glassContent(
                context: ctx,
                maxWidth: 0.9,
                children: [
                  Text(isTts ? '添加 TTS' : '添加提供商',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'TideFont')),
                  const SizedBox(height: 12),
                  _f('名称', nCtrl),
                  const SizedBox(height: 8),
                  _f('API 地址', uCtrl),
                  const SizedBox(height: 8),
                  _f('API Key', kCtrl, obscure: true),
                  const SizedBox(height: 8),
                  _f('模型名（仅填一个）', mCtrl),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: TideDialogs.glassButton('取消',
                            onTap: () => Navigator.pop(ctx),
                            color: TideTheme.of(context).buttonSecondary,
                            textColor: TideTheme.of(context).textStrong)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TideDialogs.glassButton('添加', onTap: () {
                      final raw = mCtrl.text.trim();
                      // 只允许一个模型：若含逗号/换行等多值分隔，取第一个并提示
                      String model = raw;
                      if (raw.contains(',') || raw.contains('，')) {
                        final parts = raw.split(RegExp('[，,]'));
                        if (parts.isNotEmpty) model = parts.first.trim();
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('只能填一个模型，已按「$model」保存',
                                style: const TextStyle(fontFamily: 'TideFont')),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFFE74C3C),
                            duration: const Duration(seconds: 2)));
                      }
                      setState(() {
                        final p = {
                          'name': nCtrl.text.trim(),
                          'url': uCtrl.text.trim(),
                          'key': kCtrl.text.trim(),
                          'model': model
                        };
                        final idx = _providers
                            .indexWhere((e) => e['name'] == p['name']);
                        if (idx >= 0) {
                          _providers[idx] = p;
                        } else {
                          _providers.add(p);
                        }
                      });
                      Navigator.pop(ctx);
                      _saveList();
                    }))
                  ])
                ])));
  }

  void _showTtsDialog(
      String name, String url, String key, String models, String voice) {
    final nCtrl = TextEditingController(text: name);
    final uCtrl = TextEditingController(text: url);
    final kCtrl = TextEditingController(text: key);
    final mCtrl = TextEditingController(text: models);
    final vCtrl = TextEditingController(text: voice);
    TideDialogs.show(
        context: context,
        builder: (ctx) => AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            content: TideDialogs.glassContent(
                context: ctx,
                maxWidth: 0.9,
                children: [
                  const Text('添加 TTS 提供商',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'TideFont')),
                  const SizedBox(height: 12),
                  _f('名称', nCtrl),
                  const SizedBox(height: 8),
                  _f('API 地址', uCtrl),
                  const SizedBox(height: 8),
                  _f('API Key', kCtrl, obscure: true),
                  const SizedBox(height: 8),
                  _f('模型名（仅填一个）', mCtrl),
                  const SizedBox(height: 8),
                  _f('音色', vCtrl),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: TideDialogs.glassButton('取消',
                            onTap: () => Navigator.pop(ctx),
                            color: TideTheme.of(context).buttonSecondary,
                            textColor: TideTheme.of(context).textStrong)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TideDialogs.glassButton('添加', onTap: () {
                      String model = mCtrl.text.trim();
                      if (model.contains(',') || model.contains('，')) {
                        final parts = model.split(RegExp('[，,]'));
                        if (parts.isNotEmpty) model = parts.first.trim();
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('只能填一个模型，已按「$model」保存',
                                style: const TextStyle(fontFamily: 'TideFont')),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFFE74C3C),
                            duration: const Duration(seconds: 2)));
                      }
                      setState(() {
                        final p = {
                          'name': nCtrl.text.trim(),
                          'url': uCtrl.text.trim(),
                          'key': kCtrl.text.trim(),
                          'model': model,
                          'voice': vCtrl.text.trim()
                        };
                        final i = _ttsProviders
                            .indexWhere((e) => e['name'] == p['name']);
                        if (i >= 0) {
                          _ttsProviders[i] = p;
                        } else {
                          _ttsProviders.add(p);
                        }
                      });
                      Navigator.pop(ctx);
                      _saveList();
                    }))
                  ])
                ])));
  }

  Widget _f(String label, TextEditingController c, {bool obscure = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: TideTheme.of(context).textWeak,
                fontFamily: 'TideFont')),
        const SizedBox(height: 4),
        Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: TideTheme.of(context).surfaceVariant),
            child: TextField(
                controller: c,
                obscureText: obscure,
                style: const TextStyle(fontSize: 14, fontFamily: 'TideFont'),
                decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: InputBorder.none)))
      ]);
  void _editProvider(Map<String, dynamic> p) {
    final nCtrl = TextEditingController(text: p['name']);
    final uCtrl = TextEditingController(text: p['url']);
    final kCtrl = TextEditingController(text: p['key']);
    final mCtrl = TextEditingController(text: p['model']);
    final hasVoice = p.containsKey('voice');
    TideDialogs.show(
        context: context,
        builder: (ctx) => AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            content: TideDialogs.glassContent(
                context: ctx,
                maxWidth: 0.9,
                children: [
                  Text('编辑${hasVoice ? ' TTS' : '提供商'}',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'TideFont')),
                  const SizedBox(height: 12),
                  _f('名称', nCtrl),
                  const SizedBox(height: 8),
                  _f('API 地址', uCtrl),
                  const SizedBox(height: 8),
                  _f('API Key', kCtrl, obscure: true),
                  const SizedBox(height: 8),
                  _f('模型名', mCtrl),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: TideDialogs.glassButton('取消',
                            onTap: () => Navigator.pop(ctx),
                            color: TideTheme.of(context).buttonSecondary,
                            textColor: TideTheme.of(context).textStrong)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TideDialogs.glassButton('保存', onTap: () {
                      p['name'] = nCtrl.text.trim();
                      p['url'] = uCtrl.text.trim();
                      p['key'] = kCtrl.text.trim();
                      p['model'] = mCtrl.text.trim();
                      Navigator.pop(ctx);
                      _saveList();
                      setState(() {});
                    }))
                  ])
                ])));
  }

  void _deleteProvider(int idx, {bool isTts = false}) {
    final name = isTts ? _ttsProviders[idx]['name'] : _providers[idx]['name'];
    TideDialogs.show(
        context: context,
        builder: (ctx) => AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            content: TideDialogs
                .glassContent(context: ctx, maxWidth: 0.85, children: [
              Text('删除${isTts ? 'TTS' : ''}提供商',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'TideFont')),
              const SizedBox(height: 10),
              Text('确定删除「$name」吗？',
                  style: const TextStyle(fontSize: 14, fontFamily: 'TideFont')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: TideDialogs.glassButton('取消',
                        onTap: () => Navigator.pop(ctx),
                        color: TideTheme.of(context).buttonSecondary,
                        textColor: TideTheme.of(context).textStrong)),
                const SizedBox(width: 10),
                Expanded(
                    child: TideDialogs.glassButton('删除', onTap: () {
                  setState(() {
                    if (isTts) {
                      _ttsProviders.removeAt(idx);
                    } else {
                      _providers.removeAt(idx);
                    }
                  });
                  Navigator.pop(ctx);
                  _saveList();
                }, color: const Color(0xFFE74C3C)))
              ]),
            ])));
  }

  Future<void> _testProvider(Map<String, dynamic> p) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('测试中...', style: TextStyle(fontFamily: 'TideFont')),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating));
    }
    try {
      final ms = await AIManager().testConnection(
          p['url'] ?? '',
          p['key'] ?? '',
          (p['model'] as String?)?.split(',').first.trim() ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('连接成功！${ms}ms',
                style: const TextStyle(fontFamily: 'TideFont')),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('连接失败: $e',
                style: const TextStyle(fontFamily: 'TideFont')),
            backgroundColor: const Color(0xFFE74C3C),
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: TideTheme.of(context).bgColor,
      appBar: AppBar(
          title: const Text('API 设置',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
                icon: Icon(Icons.add_circle_outline_rounded,
                    color: TideTheme.of(context).primary, size: 26),
                onPressed: _addProvider)
          ]),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  color: TideTheme.of(context).primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_providers.isEmpty && _ttsProviders.isEmpty)
                      Center(
                          child: Padding(
                              padding: const EdgeInsets.only(top: 80),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.api_rounded,
                                        size: 60, color: Color(0xFFC7C7CC)),
                                    const SizedBox(height: 12),
                                    Text('还没有添加任何模型提供商',
                                        style: TextStyle(
                                            fontSize: 15,
                                            color:
                                                TideTheme.of(context).textWeak,
                                            fontFamily: 'TideFont')),
                                    const SizedBox(height: 6),
                                    Text('点击右上角 + 添加',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                TideTheme.of(context).textFaint,
                                            fontFamily: 'TideFont'))
                                  ]))),
                    if (_providers.isNotEmpty) ...[
                      Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: Text('AI 模型',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'TideFont',
                                  color: TideTheme.of(context).textStrong))),
                      ...List.generate(_providers.length, (i) {
                        final p = _providers[i];
                        return BouncyTap(
                            onTap: () => _editProvider(p),
                            child: FrostCard(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(p['name'] ?? '',
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'TideFont'))),
                                        BouncyTap(
                                            onTap: () => _testProvider(p),
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    color: TideTheme.of(context)
                                                        .primary
                                                        .withValues(
                                                            alpha: 0.15)),
                                                child: Text('测试',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: TideTheme.of(
                                                                context)
                                                            .primary,
                                                        fontFamily:
                                                            'TideFont')))),
                                        const SizedBox(width: 8),
                                        BouncyTap(
                                            onTap: () => _deleteProvider(i),
                                            child: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: Color(0xFFE74C3C)))
                                      ]),
                                      const SizedBox(height: 6),
                                      Text(p['url'] ?? '',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: TideTheme.of(context)
                                                  .textWeak,
                                              fontFamily: 'TideFont'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      if ((p['model'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text('模型: ${p['model']}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: TideTheme.of(context)
                                                        .textFaint,
                                                    fontFamily: 'TideFont'))),
                                      if ((p['key'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                                'Key: ${(p['key'] as String).length < 8 ? p['key'] : (p['key'] as String).substring(0, 8)}...',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: TideTheme.of(context)
                                                        .textFaint,
                                                    fontFamily: 'TideFont'))),
                                    ])));
                      }),
                    ],
                    if (_ttsProviders.isNotEmpty) ...[
                      Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text('TTS 语音',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'TideFont',
                                  color: TideTheme.of(context).textStrong))),
                      ...List.generate(_ttsProviders.length, (i) {
                        final p = _ttsProviders[i];
                        return BouncyTap(
                            onTap: () => _editProvider(p),
                            child: FrostCard(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(p['name'] ?? '',
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'TideFont'))),
                                        const SizedBox(width: 8),
                                        BouncyTap(
                                            onTap: () =>
                                                _deleteProvider(i, isTts: true),
                                            child: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: Color(0xFFE74C3C)))
                                      ]),
                                      const SizedBox(height: 6),
                                      Text(p['url'] ?? '',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: TideTheme.of(context)
                                                  .textWeak,
                                              fontFamily: 'TideFont'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      if ((p['model'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text('模型: ${p['model']}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: TideTheme.of(context)
                                                        .textFaint,
                                                    fontFamily: 'TideFont'))),
                                      if ((p['voice'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text('音色: ${p['voice']}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: TideTheme.of(context)
                                                        .textFaint,
                                                    fontFamily: 'TideFont'))),
                                    ])));
                      }),
                    ],
                  ])));
}

class LocalModelPage extends StatefulWidget {
  const LocalModelPage({super.key});
  @override
  State<LocalModelPage> createState() => _LocalModelPageState();
}

class _LocalModelPageState extends State<LocalModelPage> {
  final List<Map<String, dynamic>> _models = [
    {
      'name': 'Qwen2.5-0.5B',
      'desc': '轻量级中文模型，适合简单对话',
      'size': '~400MB',
      'id': 'qwen2_5_05b',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'installed': false,
      'progress': 0.0,
      'downloading': false
    },
    {
      'name': 'Gemma-2-2B',
      'desc': 'Google轻量模型，英文能力优秀',
      'size': '~1.5GB',
      'id': 'gemma2_2b',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'installed': false,
      'progress': 0.0,
      'downloading': false
    },
    {
      'name': 'Phi-3-mini',
      'desc': '微软轻量模型，推理能力强',
      'size': '~2.2GB',
      'id': 'phi3_mini',
      'url': '',
      'installed': false,
      'progress': 0.0,
      'downloading': false
    },
    {
      'name': 'SmolLM2-1.7B',
      'desc': '轻量多语言模型，适合离线实验',
      'size': '~1.1GB',
      'id': 'smollm2_17b',
      'url':
          'https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf',
      'installed': false,
      'progress': 0.0,
      'downloading': false
    },
  ];
  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String _progressLabel(Map<String, dynamic> model) {
    final received = model['receivedBytes'] as int? ?? 0;
    final total = model['totalBytes'] as int? ?? 0;
    if (total > 0) {
      return '${_mb(received)} / ${_mb(total)} · '
          '${(received * 100 / total).clamp(0, 100).toStringAsFixed(1)}%';
    }
    return received > 0 ? '${_mb(received)} 已下载（服务器未提供总大小）' : '正在连接下载服务器…';
  }

  Future<void> _saveDownloadState(Map<String, dynamic> model) async {
    final prefs = await SharedPreferences.getInstance();
    final id = model['id'] as String;
    await prefs.setInt(
        'local_model_received_$id', model['receivedBytes'] as int? ?? 0);
    await prefs.setInt(
        'local_model_total_$id', model['totalBytes'] as int? ?? 0);
  }

  Future<void> _clearDownloadState(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_model_received_$id');
    await prefs.remove('local_model_total_$id');
  }

  Future<void> _deleteModel(int index) async {
    final model = _models[index];
    final id = model['id'] as String;
    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/$id.gguf');
    final part = File('${target.path}.part');

    final confirmed = await TideDialogs.show<bool>(
      context: context,
      builder: (dialogContext) => Center(
        child: TideDialogs.glassContent(context: dialogContext, children: [
          Text('删除本地模型',
              style: TextStyle(
                  color: TideTheme.of(dialogContext).textStrong,
                  fontFamily: 'TideFont',
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('确定删除“${model['name']}”及其下载进度吗？',
              style: TextStyle(
                  color: TideTheme.of(dialogContext).textWeak,
                  fontFamily: 'TideFont')),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: TideDialogs.glassButton('取消',
                    color: TideTheme.of(dialogContext).surfaceVariant,
                    textColor: TideTheme.of(dialogContext).textStrong,
                    onTap: () => Navigator.pop(dialogContext, false))),
            const SizedBox(width: 10),
            Expanded(
                child: TideDialogs.glassButton('删除',
                    color: const Color(0xFFE74C3C),
                    onTap: () => Navigator.pop(dialogContext, true))),
          ]),
        ]),
      ),
    );
    if (confirmed != true) return;

    // 正在下载时先让流循环失效；网络流关闭后再清理 .part，避免取消后又写回文件。
    if (model['downloading'] == true && mounted) {
      setState(() => model['downloading'] = false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    try {
      if (await target.exists()) await target.delete();
      if (await part.exists()) await part.delete();
    } catch (_) {
      // Keep cleanup best-effort; state references must still be removed.
    }
    await _clearDownloadState(id);

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
          (key) => key.startsWith('local_chat_model_'),
        )) {
      if (prefs.getString(key) == id) {
        await prefs.remove(key);
      }
    }

    if (!mounted) return;
    setState(() {
      model['installed'] = false;
      model['downloading'] = false;
      model['receivedBytes'] = 0;
      model['totalBytes'] = 0;
      model['progress'] = 0.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('本地模型已删除')),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkInstalled();
  }

  Future<void> _checkInstalled() async {
    final dir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    for (final m in _models) {
      final id = m['id'] as String;
      final target = File('${dir.path}/$id.gguf');
      final part = File('${target.path}.part');
      final installed =
          await target.exists() && await target.length() > 1024 * 1024;
      final received = installed
          ? await target.length()
          : (await part.exists() ? await part.length() : 0);
      final savedTotal = prefs.getInt('local_model_total_$id') ?? 0;
      m['installed'] = installed;
      m['downloading'] = false;
      // Local-chat selection is scoped to each bot in the chat settings.
      // Do not expose a stale global selection state on the download page.
      m['localSelected'] = false;

      m['receivedBytes'] = received;
      m['totalBytes'] = installed ? received : savedTotal;
      m['progress'] =
          savedTotal > 0 ? (received / savedTotal).clamp(0.0, 1.0) : 0.0;
    }
    if (mounted) setState(() {});
  }

  Future<void> _downloadModel(int idx) async {
    final m = _models[idx];
    final url = (m['url'] as String).trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('暂无可用下载链接', style: TextStyle(fontFamily: 'TideFont')),
          behavior: SnackBarBehavior.floating));
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final id = m['id'] as String;
    final target = File('${dir.path}/$id.gguf');
    final part = File('${target.path}.part');
    var existing = await part.exists() ? await part.length() : 0;
    if (mounted) {
      setState(() {
        m['downloading'] = true;
        m['receivedBytes'] = existing;
      });
    }

    final client = http.Client();
    IOSink? sink;
    try {
      final routes = <String>[
        url,
        url.replaceFirst('https://huggingface.co/', 'https://hf-mirror.com/'),
        url.replaceFirst('https://huggingface.co/', 'https://hf.co/'),
      ];
      http.StreamedResponse? response;
      final errors = <String>[];
      for (final route in routes.take(3)) {
        for (var attempt = 1; attempt <= 3 && response == null; attempt++) {
          try {
            final request = http.Request('GET', Uri.parse(route));
            if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
            final candidate =
                await client.send(request).timeout(const Duration(minutes: 20));
            if (candidate.statusCode == 200 || candidate.statusCode == 206) {
              response = candidate;
            } else {
              errors.add('$route 第$attempt次 HTTP ${candidate.statusCode}');
              await candidate.stream.drain();
            }
          } catch (e) {
            errors.add('$route 第$attempt次 $e');
          }
        }
        if (response != null) break;
      }
      if (response == null) {
        throw HttpException('三条下载线路均失败（每条已重试三次）：${errors.join('；')}');
      }

      // A server that ignores Range returns 200. Restart safely instead of
      // appending a duplicate file.
      if (existing > 0 && response.statusCode == 200) {
        await part.delete();
        existing = 0;
        final request = http.Request('GET', Uri.parse(url));
        response =
            await client.send(request).timeout(const Duration(minutes: 20));
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('下载服务器返回 HTTP ${response.statusCode}');
      }

      final total = response.contentLength == null
          ? 0
          : existing + response.contentLength!;
      sink =
          part.openWrite(mode: existing > 0 ? FileMode.append : FileMode.write);
      var received = existing;
      var lastPersisted = existing;
      if (mounted) {
        setState(() {
          m['receivedBytes'] = received;
          m['totalBytes'] = total;
          m['progress'] = total > 0 ? received / total : 0.0;
        });
      }

      await for (final bytes in response.stream) {
        // 用户点“取消并删除”后立即停止消费网络流，finally 会关闭客户端。
        if (m['downloading'] != true) {
          throw const FileSystemException('下载已取消');
        }
        sink.add(bytes);
        received += bytes.length;
        if (received - lastPersisted >= 256 * 1024) {
          lastPersisted = received;
          m['receivedBytes'] = received;
          m['totalBytes'] = total;
          await _saveDownloadState(m);
          if (mounted) {
            setState(() => m['progress'] = total > 0 ? received / total : 0.0);
          }
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      m['receivedBytes'] = received;
      m['totalBytes'] = total;
      await _saveDownloadState(m);

      if (!await part.exists() || await part.length() <= 1024 * 1024) {
        throw const FileSystemException('下载文件过小，已拒绝标记为已安装');
      }
      if (total > 0 && received != total) {
        throw const FileSystemException('下载不完整，将保留进度以便下次继续');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      await _clearDownloadState(id);
      if (mounted) {
        setState(() {
          m['installed'] = true;
          m['downloading'] = false;
          m['progress'] = 1.0;
          m['receivedBytes'] = received;
          m['totalBytes'] = received;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${m['name']} 已真实下载到本机',
                style: const TextStyle(fontFamily: 'TideFont')),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      await sink?.flush();
      await sink?.close();
      final cancelled = m['downloading'] != true && e.toString().contains('取消');
      final received = await part.exists() ? await part.length() : 0;
      m['receivedBytes'] = received;
      if (!cancelled) await _saveDownloadState(m);
      if (mounted && !cancelled) {
        setState(() {
          m['downloading'] = false;
          final total = m['totalBytes'] as int? ?? 0;
          m['progress'] = total > 0 ? received / total : 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('下载暂停/失败：$e；已保留 ${_mb(received)}，可稍后继续',
                style: const TextStyle(fontFamily: 'TideFont')),
            backgroundColor: const Color(0xFFE74C3C),
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: TideTheme.of(context).bgColor,
      appBar: AppBar(
          title: const Text('本地模型',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontFamily: 'TideFont')),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: () => Navigator.pop(context))),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _models.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                  '模型文件通过真实 HTTP 流下载到应用私有目录，支持保留 .part 进度并在下次进入时续传。下载完成后仍需本地 GGUF 推理引擎才能参与离线聊天。',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: TideTheme.of(context).textWeak,
                      fontFamily: 'TideFont')),
            );
          }
          final modelIndex = i - 1;
          final m = _models[modelIndex];
          final installed = m['installed'] == true;
          final downloading = m['downloading'] == true;
          return FrostCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Text(m['name'] as String,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'TideFont')),
                              if (installed)
                                const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(Icons.check_circle,
                                        size: 18, color: Color(0xFF34C759)))
                            ]),
                            const SizedBox(height: 4),
                            Text('${m['desc']} • ${m['size']}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: TideTheme.of(context).textWeak,
                                    fontFamily: 'TideFont'))
                          ])),
                      if (installed)
                        BouncyTap(
                            onTap: () => _deleteModel(modelIndex),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color:
                                        TideTheme.of(context).surfaceVariant),
                                child: Text('删除',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: TideTheme.of(context).textStrong,
                                        fontFamily: 'TideFont'))))
                      else
                        downloading
                            ? BouncyTap(
                                onTap: () => _deleteModel(modelIndex),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        color: TideTheme.of(context)
                                            .surfaceVariant),
                                    child: Text('取消并删除',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: TideTheme.of(context)
                                                .textStrong,
                                            fontFamily: 'TideFont'))))
                            : BouncyTap(
                                onTap: () => _downloadModel(modelIndex),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        color: TideTheme.of(context).primary),
                                    child: const Text('下载',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                            fontFamily: 'TideFont')))),
                    ]),
                    if (downloading ||
                        (!installed && (m['receivedBytes'] as int? ?? 0) > 0))
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                    value: (m['totalBytes'] as int? ?? 0) > 0
                                        ? m['progress'] as double
                                        : null,
                                    backgroundColor:
                                        TideTheme.of(context).surfaceVariant,
                                    color: TideTheme.of(context).primary),
                                const SizedBox(height: 6),
                                Text(
                                    downloading
                                        ? _progressLabel(m)
                                        : '${_progressLabel(m)} · 已暂停，点击下载继续',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: TideTheme.of(context).textWeak,
                                        fontFamily: 'TideFont')),
                              ])),
                  ]));
        },
      ));
}
