/// Detect the payload format rather than trusting the file extension.
String imageUploadMime(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff)
    return 'image/jpeg';
  if (bytes.length >= 4 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71)
    return 'image/png';
  if (bytes.length >= 6 &&
      String.fromCharCodes(bytes.take(6)).startsWith('GIF8'))
    return 'image/gif';
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP')
    return 'image/webp';
  if (bytes.length >= 2 && bytes[0] == 66 && bytes[1] == 77) return 'image/bmp';
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.skip(4).take(4)) == 'ftyp') {
    final brands = String.fromCharCodes(bytes.skip(8).take(40));
    if (brands.contains('avif') || brands.contains('avis')) return 'image/avif';
    if (brands.contains('heic') ||
        brands.contains('heix') ||
        brands.contains('hevc') ||
        brands.contains('hevx'))
      return 'image/heic';
    return 'image/heif';
  }
  throw const FormatException('无法识别图片格式，请选择 JPG、PNG、WebP 或 HEIC 图片');
}

String imageUploadExtension(String mime) =>
    mime == 'image/jpeg' ? 'jpg' : mime.split('/').last;
