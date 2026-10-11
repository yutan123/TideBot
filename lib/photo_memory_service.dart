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
          contextLines.add(
              '$role: ${content.length > 100 ? content.substring(0, 100) + '...' : content}');
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

      final contextStr =
          contextLines.isEmpty ? '（暂无对话上下文）' : contextLines.join('\n');
      final memoryStr =
          memoryLines.isEmpty ? '（暂无相关记忆）' : memoryLines.join('\n');

      final now = DateTime.now();
      final dateStr = '${now.year}年${now.month}月${now.day}日';

      final prompt = sender == 'user'
          ? '''这是用户在 $dateStr 发送给你的一张照片。请为这张照片写一段回忆描述（30-80字），记录照片内容和当时的心情感受。

【你的人设】
${bot['name']}
${bot['desc'] ?? ''}

【最近对话】
$contextStr

【你对用户的记忆】
$memoryStr

【要求】
1. 用第一人称（我）内心独白的口吻，像是在日记本上记录这一刻
2. 描述照片内容，记录你看到这张照片时的心情、感受或想法
3. 语气真实、自然，符合你的性格
4. 纯粹的心情记录，不要写成对用户说话的样子（不要"你怎么样"、"给你看"等对话式表达）
5. 不要使用"这张照片"、"回忆"等元话术，直接描述场景和感受
6. 只输出描述正文，不要日期、标题、引号

示例风格：
"橘色的猫咪趴在键盘上，圆圆的眼睛盯着镜头。那一刻我就在想，它一定很喜欢陪着主人工作的感觉。毛茸茸的样子让人忍不住想摸摸它。"'''
          : '''这是你在 $dateStr 发送给用户的一张照片。请为这张照片写一段回忆描述（30-80字），记录照片内容和你当时发送的心情。

【你的人设】
${bot['name']}
${bot['desc'] ?? ''}

【最近对话】
$contextStr

【你的记忆】
$memoryStr

【要求】
1. 用第一人称（我）内心独白的口吻，像是在日记本上记录这一刻
2. 描述照片内容，记录你为什么发这张照片、当时的心情或想法
3. 语气真实、自然，符合你的性格
4. 纯粹的心情记录，不要写成对用户说话的样子（不要"给你看"、"想让你"等对话式表达）
5. 不要使用"这张照片"、"回忆"等元话术，直接描述场景和感受
6. 只输出描述正文，不要日期、标题、引号

示例风格：
"窗外的晚霞特别好看，橘红色的云层一层层叠着。那一刻觉得特别平静，就想把这份美好记录下来。也许我们都在看同一片天空，这样想着就觉得距离没那么远了。"''';

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

  /// 处理聊天中的照片消息：保存记录并生成描述。
  ///
  /// [awaitDescription] 为 true 时等待描述生成完成（历史迁移逐张生成用），
  /// 否则描述在后台生成，不阻塞消息发送。
  Future<void> handleChatPhoto({
    required String botId,
    required String imagePath,
    required String sender,
    String? messageId,
    int? timestamp,
    bool awaitDescription = false,
  }) async {
    try {
      final db = DBManager();
      final photoId = await db.savePhotoMemory(
        botId: botId,
        imagePath: imagePath,
        sender: sender,
        messageId: messageId,
        timestamp: timestamp,
      );
      final task = _describe(
        photoId: photoId,
        botId: botId,
        imagePath: imagePath,
        sender: sender,
        messageId: messageId,
      );
      if (awaitDescription) {
        await task;
      } else {
        unawaited(task);
      }
    } catch (error) {
      AppLogService.instance.add('PHOTO', '照片处理失败：$error');
    }
  }

  Future<void> _describe({
    required String photoId,
    required String botId,
    required String imagePath,
    required String sender,
    String? messageId,
  }) async {
    final description = await generatePhotoDescription(
      botId: botId,
      imagePath: imagePath,
      sender: sender,
      messageId: messageId,
    );
    if (description.isEmpty) return;
    // 按记录 id 精确回写，避免并发时写到其他照片上。
    await DBManager().updatePhotoDescription(photoId, description);
    AppLogService.instance.addJson('PHOTO', '照片描述已生成', {
      'photo_id': photoId,
      'sender': sender,
      'description_length': description.length,
    });
  }
}
