import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/model_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('model image uses decoded content regardless of file extension',
      () async {
    final folder = await Directory.systemTemp.createTemp('model-image-test');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF008877), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(16, 8);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${folder.path}/wrong-extension.jpg');
      await file.writeAsBytes(data!.buffer.asUint8List());
      final converted = await modelImageBytes(file.path);
      expect(converted.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(converted);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 16);
      expect(frame.image.height, 8);
      frame.image.dispose();
      codec.dispose();
    } finally {
      image.dispose();
      picture.dispose();
      await folder.delete(recursive: true);
    }
  });
}
