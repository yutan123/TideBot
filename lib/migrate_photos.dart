import 'dart:io';
import 'db.dart';
import 'photo_memory_service.dart';

/// 迁移历史图片到照片回忆相册
/// 
/// 将 chat_history 表中已有的图片消息（type='image'）导入到 photo_memories 表
/// 并为每张照片异步生成 AI 描述
Future<void> migrateHistoricalPhotos() async {
  final db = DBManager();
  
  print('[迁移] 开始迁移历史图片...');
  
  // 查询所有图片消息
  final database = await db.database;
  final images = await database.rawQuery('''
    SELECT id, bot_id, role, file_path, timestamp
    FROM chat_history
    WHERE type = 'image' 
      AND file_path IS NOT NULL 
      AND file_path != ''
      AND (role = 'user' OR role = 'assistant')
    ORDER BY timestamp DESC
  ''');
  
  print('[迁移] 找到 ${images.length} 条图片消息');
  
  int recordedCount = 0;
  int skipCount = 0;
  
  for (final img in images) {
    final botId = img['bot_id']?.toString();
    final filePath = img['file_path']?.toString();
    final role = img['role']?.toString();
    final messageId = img['id']?.toString();
    final timestamp = (img['timestamp'] as num?)?.toInt();
    
    if (botId == null || filePath == null || role == null) {
      skipCount++;
      continue;
    }
    
    // 检查文件是否存在，不存在直接跳过
    if (!await File(filePath).exists()) {
      skipCount++;
      continue;
    }
    
    // 检查是否已记录
    final existing = await database.query(
      'photo_memories',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      skipCount++;
      continue;
    }
    
    try {
      final sender = role == 'user' ? 'user' : 'bot';
      // 异步处理，不等待描述生成完成
      PhotoMemoryService.instance.handleChatPhoto(
        botId: botId,
        imagePath: filePath,
        sender: sender,
        messageId: messageId,
        timestamp: timestamp,
      );
      recordedCount++;
    } catch (error) {
      print('[迁移] 记录失败: $filePath, 错误: $error');
      skipCount++;
    }
  }
  
  print('[迁移] 已记录 $recordedCount 张照片，跳过 $skipCount 张，AI 描述生成中...');
}
