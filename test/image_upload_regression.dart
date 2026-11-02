import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:tide_bot/bot_image_request.dart';
import 'package:tide_bot/image_upload_codec.dart';
import 'package:tide_bot/image_upload_format.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final sizes = <(int, int), (int, int)>{
    (3840, 2160): (1920, 1080),
    (2160, 3840): (1080, 1920),
    (4000, 3000): (1440, 1080),
    (3000, 4000): (1080, 1440),
    (3000, 3000): (1080, 1080),
    (3000, 1500): (1920, 960),
    (80, 40): (80, 40),
    (10000, 1): (1920, 1),
  };
  for (final entry in sizes.entries) {
    check(
      imageUploadSize(entry.key.$1, entry.key.$2) == entry.value,
      'Incorrect 1080p bounds for ${entry.key}',
    );
  }

  // Offset byte views must encode the selected pixels, not the parent buffer.
  final storage = Uint8List(4 + 16 * 8 * 4);
  final rgba = Uint8List.sublistView(storage, 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba.setRange(i, i + 4, [51, 102, 153, 255]);
  }
  final jpeg = encodeUploadJpeg((rgba, 16, 8));
  check(imageUploadMime(jpeg) == 'image/jpeg', 'Output must be real JPEG');
  final decoded = img.decodeJpg(jpeg)!;
  check(decoded.width == 16 && decoded.height == 8, 'JPEG dimensions changed');
  final pixel = decoded.getPixel(4, 4);
  check(
    (pixel.r - 51).abs() < 8 &&
        (pixel.g - 102).abs() < 8 &&
        (pixel.b - 153).abs() < 8,
    'JPEG colors changed unexpectedly',
  );

  final png = img.encodePng(decoded);
  final formats = <String, List<int>>{
    'image/jpeg': jpeg,
    'image/png': png,
    'image/gif': ascii.encode('GIF89a'),
    'image/webp': [
      ...ascii.encode('RIFF'),
      0,
      0,
      0,
      0,
      ...ascii.encode('WEBP'),
    ],
    'image/heic': [0, 0, 0, 24, ...ascii.encode('ftypheic')],
    'image/avif': [0, 0, 0, 24, ...ascii.encode('ftypavif')],
  };
  for (final entry in formats.entries) {
    check(
      imageUploadMime(entry.value) == entry.key,
      'Incorrect MIME ${entry.key}',
    );
    final request =
        buildBotImageRequest(
              baseUrl: 'https://example.com/v1',
              model: 'image',
              apiKey: 'key',
              prompt: '原样提示词',
              reference: entry.value,
              applyPortraitInstructions: false,
            )
            as http.MultipartRequest;
    check(request.url.path == '/v1/images/edits', 'Wrong edit URL');
    check(request.fields['prompt'] == '原样提示词', 'Edit prompt was modified');
    check(
      request.files.single.contentType.toString() == entry.key,
      'Wrong multipart MIME',
    );
    check(
      request.files.single.filename ==
          'reference.${imageUploadExtension(entry.key)}',
      'Wrong multipart extension',
    );
    final uploaded = await request.files.single.finalize().toBytes();
    check(
      base64Encode(uploaded) == base64Encode(entry.value),
      'Original payload changed',
    );
  }
  final generation =
      buildBotImageRequest(
            baseUrl: 'https://example.com/v1',
            model: 'image',
            apiKey: 'key',
            prompt: '画画',
          )
          as http.Request;
  check(
    generation.url.path == '/v1/images/generations',
    'Generation URL changed',
  );
  check(
    jsonDecode(generation.body)['prompt'] == '画画',
    'Generation prompt changed',
  );
  var rejected = false;
  try {
    imageUploadMime([1, 2, 3]);
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'Invalid upload type must fail clearly');
  print(
    'PASS: 1080p sizing (8 cases), JPEG encoding/color/offset, MIME and multipart original bytes (6 formats), generation and invalid input',
  );
}
