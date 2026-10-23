import 'package:sqflite/sqflite.dart';

/// This check runs independently of the general repair-version marker. Restored
/// databases can have a current marker while still missing the call table.
Future<void> ensureVoiceCallSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS voice_call_records (
      id TEXT PRIMARY KEY,
      bot_id TEXT NOT NULL,
      initiator TEXT NOT NULL DEFAULT 'user',
      status TEXT NOT NULL DEFAULT 'ended',
      duration INTEGER NOT NULL DEFAULT 0,
      summary TEXT DEFAULT '',
      transcript TEXT DEFAULT '',
      timestamp INTEGER NOT NULL DEFAULT 0,
      start_time INTEGER NOT NULL DEFAULT 0,
      end_time INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (bot_id) REFERENCES bots (id) ON DELETE CASCADE
    )
  ''');
  final info = await db.rawQuery('PRAGMA table_info(voice_call_records)');
  final existing = info.map((row) => row['name']).toSet();
  for (final entry in const {
    'bot_id': "TEXT NOT NULL DEFAULT ''",
    'initiator': "TEXT NOT NULL DEFAULT 'user'",
    'status': "TEXT NOT NULL DEFAULT 'ended'",
    'duration': 'INTEGER NOT NULL DEFAULT 0',
    'summary': "TEXT DEFAULT ''",
    'transcript': "TEXT DEFAULT ''",
    'timestamp': 'INTEGER NOT NULL DEFAULT 0',
    'start_time': 'INTEGER NOT NULL DEFAULT 0',
    'end_time': 'INTEGER NOT NULL DEFAULT 0',
    'created_at': 'INTEGER NOT NULL DEFAULT 0',
  }.entries) {
    if (!existing.contains(entry.key)) {
      // Propagate failures so callers cannot publish an unsaved call card or
      // mark an unsuccessful repair as complete.
      await db.execute(
        'ALTER TABLE voice_call_records ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
  }
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_voice_call_records_bot
    ON voice_call_records(bot_id, timestamp DESC)
  ''');
}
