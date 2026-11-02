import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive_io.dart' hide ZLibDecoder;
import 'package:path/path.dart' as p;

Future<void> writeTransferZip(
  String destination,
  Map<String, String> files,
) async {
  final encoder = ZipFileEncoder();
  encoder.create(destination, level: 0);
  try {
    for (final entry in files.entries) {
      // Store entries in bounded chunks; media is already compressed.
      final input = InputFileStream(entry.value);
      try {
        encoder.addArchiveFile(
          ArchiveFile.stream(entry.key, input)
            ..compression = CompressionType.none,
        );
      } finally {
        await input.close();
      }
    }
  } finally {
    await encoder.close();
  }
}

// Read metadata without ZipDecoder's eager symbolic-link decompression.
ZipDirectory _directory(InputFileStream input) {
  final directory = ZipDirectory()..read(input);
  for (final header in directory.fileHeaders) {
    final file = header.file!;
    if ((header.externalFileAttributes >> 16 & 0xf000) == 0xa000 ||
        file.flags & 1 != 0) {
      throw const FormatException('不支持链接或加密的备份文件');
    }
    if (header.compressionMethod != 0 && header.compressionMethod != 8) {
      throw const FormatException('不支持此备份的压缩方式');
    }
  }
  return directory;
}

int transferZipSize(String source) {
  final input = InputFileStream(source);
  try {
    return _directory(input).fileHeaders.fold<int>(
      0,
      (total, header) => total + header.file!.uncompressedSize,
    );
  } finally {
    input.closeSync();
  }
}

Stream<List<int>> _compressedChunks(InputStream input) async* {
  while (!input.isEOS) {
    // Deflate can expand one input byte by about 1,032 times. A small
    // compressed chunk also bounds each native decoder output allocation.
    yield input.readBytes(math.min(4 * 1024, input.length)).toUint8List();
  }
}

Future<void> extractTransferZip(String source, String destination) async {
  final input = InputFileStream(source);
  try {
    final directory = _directory(input);
    final names = <String>{};
    for (final header in directory.fileHeaders) {
      final name = header.file!.filename.replaceAll('\\', '/');
      final target = p.normalize(p.join(destination, name));
      if (p.isAbsolute(name) ||
          !p.isWithin(destination, target) ||
          !names.add(target)) {
        throw const FormatException('备份包含不安全或重复的文件路径');
      }
    }
    for (final header in directory.fileHeaders) {
      final entry = header.file!;
      final name = entry.filename.replaceAll('\\', '/');
      if (name.endsWith('/')) continue;
      final file = File(p.normalize(p.join(destination, name)));
      await file.parent.create(recursive: true);
      final output = file.openWrite();
      var size = 0;
      var checksum = 0;
      try {
        Stream<List<int>> chunks = _compressedChunks(
          entry.getStream(decompress: false),
        );
        if (entry.compressionMethod == CompressionType.deflate) {
          chunks = chunks.transform(ZLibDecoder(raw: true));
        }
        // Backpressure covers both decompression and disk writes.
        await output.addStream(
          chunks.map((chunk) {
            size += chunk.length;
            if (size > entry.uncompressedSize) {
              throw const FormatException('备份解压大小与记录不符');
            }
            checksum = getCrc32(chunk, checksum);
            return chunk;
          }),
        );
        if (size != entry.uncompressedSize || checksum != header.crc32) {
          throw const FormatException('备份文件损坏或不完整');
        }
      } finally {
        await output.close();
      }
    }
  } finally {
    await input.close();
  }
}
