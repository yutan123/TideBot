import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/bot_reference_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('JPEG with EXIF rotation converts to PNG without output-size decoding',
      () async {
    final jpeg = base64Decode(
        '/9j/4AAQSkZJRgABAQAAAAAAAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAANAAcDAREAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCIrqSAP//Z');
    // APP1 Exif: little-endian TIFF, orientation 6 (90 degrees clockwise).
    final rotated = Uint8List.fromList([
      ...jpeg.take(2),
      0xff,
      0xe1,
      0,
      34,
      69,
      120,
      105,
      102,
      0,
      0,
      73,
      73,
      42,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
      18,
      1,
      3,
      0,
      1,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...jpeg.skip(2),
    ]);
    final result = await prepareBotReferenceImage(rotated);
    expect(result.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(result);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 13);
    expect(frame.image.height, 7);
    frame.image.dispose();
    codec.dispose();
  });

  Future<Uint8List> imageBytes(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('reference image preserves small image dimensions and PNG encoding',
      () async {
    final result = await prepareBotReferenceImage(await imageBytes(80, 40));
    expect(result.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(result);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 80);
    expect(frame.image.height, 40);
    frame.image.dispose();
    codec.dispose();
  });

  test('reference image limits longest dimension and keeps aspect ratio',
      () async {
    final result = await prepareBotReferenceImage(await imageBytes(3000, 1500));
    final codec = await ui.instantiateImageCodec(result);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 2048);
    expect(frame.image.height, 1024);
    frame.image.dispose();
    codec.dispose();
  });

  test('reference image rejects empty, oversized and invalid data', () async {
    await expectLater(
        prepareBotReferenceImage(Uint8List(0)), throwsFormatException);
    await expectLater(prepareBotReferenceImage(Uint8List(20 * 1024 * 1024 + 1)),
        throwsFormatException);
    await expectLater(prepareBotReferenceImage(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<Exception>()));
  });
}
