import 'dart:io';
import 'app_log_service.dart';
import 'db.dart';
import 'photo_memory_service.dart';

bool _migrationRunning = false;

/// 把 chat_history 中已有的图片消息迁移到照片回忆相册。
///
/// 逐张处理：每张照片的描述生成完成后再处理下一张，避免一次性
/// 发出大量模型请求。图片文件不存在或已迁移的直接跳过。
Future<void> migrateHistoricalPhotos() async {
  if (_migrationRunning) return;
  _migrationRunning = true;
  try {
    // 等首页渲染完成后再开始，不和冷启动抢资源。
    await Future<void>.delayed(const Duration(seconds: 8));
    final database = await DBManager().database;
    final images = await database.rawQuery('''
      SELECT h.id, h.bot_id, h.role, h.file_path, h.timestamp
      FROM chat_history h
      WHERE h.type = 'image'
        AND h.file_path IS NOT NULL AND h.file_path != ''
        AND h.role IN ('user', 'assistant')
        AND NOT EXISTS (
          SELECT 1 FROM photo_memories p WHERE p.message_id = h.id
        )
      ORDER BY h.timestamp DESC
    ''');

    var recorded = 0;
    var skipped = 0;
    for (final img in images) {
      final botId = img['bot_id']?.toString();
      final filePath = img['file_path']?.toString();
      final role = img['role']?.toString();
      if (botId == null || filePath == null || role == null) {
        skipped++;
        continue;
      }
      if (!await File(filePath).exists()) {
        skipped++;
        continue;
      }
      await PhotoMemoryService.instance.handleChatPhoto(
        botId: botId,
        imagePath: filePath,
        sender: role == 'user' ? 'user' : 'bot',
        messageId: img['id']?.toString(),
        timestamp: (img['timestamp'] as num?)?.toInt(),
        awaitDescription: true,
      );
      recorded++;
    }
    AppLogService.instance.addJson('PHOTO', '历史图片迁移完成', {
      'recorded': recorded,
      'skipped': skipped,
    });
  } catch (error) {
    AppLogService.instance.add('PHOTO', '历史图片迁移失败：$error');
  } finally {
    _migrationRunning = false;
  }
}
