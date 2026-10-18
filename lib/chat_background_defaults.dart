import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Seed only untouched chat settings. An empty value records an explicit clear.
Future<void> copyGlobalToUnsetChatBackgrounds({
  required String sourcePath,
  required Iterable<String> botIds,
  required Directory directory,
  required SharedPreferences prefs,
}) async {
  final targets = botIds
      .where((id) => id.isNotEmpty && !prefs.containsKey('chat_bg_$id'))
      .toSet();
  if (targets.isEmpty || sourcePath.isEmpty) return;
  await directory.create(recursive: true);
  final copy = await File(sourcePath).copy(
      '${directory.path}/global_copy_${DateTime.now().microsecondsSinceEpoch}');
  for (final id in targets) {
    // A user selection made while copying must win.
    if (!prefs.containsKey('chat_bg_$id')) {
      await prefs.setString('chat_bg_$id', copy.path);
    }
  }
}
