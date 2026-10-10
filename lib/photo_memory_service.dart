import 'dart:async';
import 'ai.dart';
import 'db.dart';
import 'app_log_service.dart';

/// 照片回忆描述生成服务
class PhotoMemoryService {
  PhotoMemoryService._();
  static final instance = PhotoMemoryService._();

  /// 为照片生成回忆描述
  /// 
  /// 提供：照片本身、最近几轮对话上下文、机器人人设、最近3条世界书记忆
  /// 生成：日期 + 描述 + 发送理由（机器人发的照片）
  Future<String> generatePhotoDescription({
    required String botId,
    required String imagePath,
    required String sender,
    String? messageId,
  }) async {
    try {
      final db = DBManager();
      final bot = (await db.queryBots())
          .cast<Map<String, dynamic>?>()
          .firstWhere((b) => b?['id'] == botId, orElse: () => null);
      if (bot == null) return '';

      // 获取最近几轮对话上下文（最多10轮，约20条消息）
      final recentHistory = await db.queryMessages(botId, limit: 20);
final contextLines = <String>[];
      for (final msg in recentHistory.reversed.take(20)) {
        final role = msg['role'] == 'user' ? '用户' : bot['name'];
        final content = msg['content']?.toString() ?? '';
        if (content.isNotEmpty) {
          contextLines.add('$role: ${content.length > 100 ? content.substring(0, 100) + '...' : content}');
        }
      }

      // 获取最近3条世界书记忆
      final memories = await db.queryMemories(botId, limit: 50);
      final recentMemories = memories
          .where((m) => 
              m['category'] != '角色眼中的你' && 
              m['category'] != '角色的自我认知' && 
              m['category'] != '关系' &&
              m['category'] != '角色档案')
          .take(3)
          .toList();

      final memoryLines = <String>[];
      for (final m in recentMemories) {
        final title = m['title']?.toString() ?? '';
        final content = m['content']?.toString() ?? '';
        if (title.isNotEmpty || content.isNotEmpty) {
          memoryLines.add('- ${title.isNotEmpty ? title : content}');
        }
      }

      final contextStr = contextLines.isEmpty 
          ? '（暂无对话上下文）' 
          : contextLines.join('\n');
      final memoryStr = memoryLines.isEmpty 
          ? '（暂无相关记忆）' 
          : memoryLines.join('\n');

      final now = DateTime.now();
      final dateStr = '${now.year}年${now.month}月${now.day}日';

      final prompt = sender == 'user'
          ? '''这是用户在 $dateStr 发送给你的一张照片。请结合对话上下文和你对用户的了解，为这张照片写一段温暖的回忆描述（30-80字）。

【你的人设】
${bot['name']}
${bot['desc'] ?? ''}

【最近对话】
$contextStr

【你对用户的记忆】
$memoryStr

【要求】
1. 用第一人称（我）口吻，像是你在回忆这张照片
2. 描述照片内容，并结合对话上下文或记忆，说明这张照片对你的意义
3. 语气自然、温暖，符合你的说话方式
4. 不要使用"这张照片"、"回忆"等元话术，直接描述
5. 只输出描述正文，不要日期、标题、引号

示例风格：
"那天你给我看了你养的猫，橘色的毛茸茸的，眼睛特别圆。你说它总是在你写代码的时候跳上键盘，我当时就在想，它一定很喜欢你。"'''
          : '''这是你在 $dateStr 发送给用户的一张照片。请结合对话上下文和你的人设，为这张照片写一段回忆描述（30-80字），并说明你为什么发这张照片。

【你的人设】
${bot['name']}
${bot['desc'] ?? ''}

【最近对话】
$contextStr

【你的记忆】
$memoryStr

【要求】
1. 用第一人称（我）口吻，像是你在回忆这张照片
2. 描述照片内容，并说明你为什么发这张照片给用户（分享心情、想让TA看到、觉得有趣等）
3. 语气自然、温暖，符合你的说话方式
4. 不要使用"这张照片"、"回忆"等元话术，直接描述
5. 只输出描述正文，不要日期、标题、引号

示例风格：
"那天看到窗外的晚霞特别好看，橘红色的云层一层层叠着，我就拍下来发给你了。想着你可能也在看同一片天空，就觉得我们其实也没那么远。"''';

      final result = await AIManager().sendMessage(
        botId: botId,
        text: prompt,
        priority: false,
        persistResponse: false,
        includeChatHistory: false,
        enableAutoSummary: false,
        allowTools: false,
        forceSingleReply: true,
        imageAttachments: [imagePath],
      );

      final description = result['reply']?.toString().trim() ?? '';
      if (description.isEmpty) {
        AppLogService.instance.add('PHOTO', '照片描述生成为空');
        return '';
      }

      return description;
    } catch (error) {
      AppLogService.instance.add('PHOTO', '照片描述生成失败：$error');
      return '';
    }
  }

  /// 处理聊天中的照片消息：保存记录并生成描述
  Future<void> handleChatPhoto({
    required String botId,
    required String imagePath,
    required String sender,
    String? messageId,
    int? timestamp,
  }) async {
    try {
      final db = DBManager();
      
      // 先保存照片记录（描述为空）
      await db.savePhotoMemory(
        botId: botId,
        imagePath: imagePath,
        sender: sender,
        messageId: messageId,
        timestamp: timestamp,
      );

      // 异步生成描述
      unawaited(() async {
        final description = await generatePhotoDescription(
          botId: botId,
          imagePath: imagePath,
          sender: sender,
          messageId: messageId,
        );

        if (description.isNotEmpty) {
          final photos = await db.queryPhotoMemories(botId, limit: 1);
          if (photos.isNotEmpty) {
            final photoId = photos.first['id']?.toString() ?? '';
            await db.updatePhotoDescription(photoId, description);
            AppLogService.instance.addJson('PHOTO', '照片描述已生成', {
              'photo_id': photoId,
              'sender': sender,
              'description_length': description.length,
            });
          }
        }
      }());
    } catch (error) {
      AppLogService.instance.add('PHOTO', '照片处理失败：$error');
    }
  }
}
