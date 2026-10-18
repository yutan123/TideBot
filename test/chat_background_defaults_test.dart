import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tide_bot/chat_background_defaults.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'copies independently, preserves custom and cleared choices on later saves',
      () async {
    SharedPreferences.setMockInitialValues(
        {'chat_bg_custom': '/custom.jpg', 'chat_bg_cleared': ''});
    final prefs = await SharedPreferences.getInstance();
    final temp = await Directory.systemTemp.createTemp('chat_background_test');
    addTearDown(() => temp.delete(recursive: true));
    final source =
        await File('${temp.path}/global.jpg').writeAsBytes([1, 2, 3]);
    final directory = Directory('${temp.path}/chat_backgrounds');
    Future<void> seed() => copyGlobalToUnsetChatBackgrounds(
        sourcePath: source.path,
        botIds: ['new', 'custom', 'cleared', ''],
        directory: directory,
        prefs: prefs);
    await seed();
    final copied = prefs.getString('chat_bg_new')!;
    expect(copied, isNot(source.path));
    expect(await File(copied).readAsBytes(), [1, 2, 3]);
    expect(prefs.getString('chat_bg_custom'), '/custom.jpg');
    expect(prefs.getString('chat_bg_cleared'), '');
    await source.writeAsBytes([4]);
    await seed();
    expect(prefs.getString('chat_bg_new'), copied);
    await source.delete();
    expect(await File(copied).readAsBytes(), [1, 2, 3]);
    expect(await directory.list().length, 1);
  });
}
