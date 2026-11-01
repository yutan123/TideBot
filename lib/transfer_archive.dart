import 'dart:io';
import 'package:archive/archive_io.dart';
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

Future<void> extractTransferZip(String source, String destination) async {
  final input = InputFileStream(source);
  try {
    final archive = ZipDecoder().decodeStream(input);
    try {
      for (final entry in archive.files.where((e) => e.isFile)) {
        final target = p.normalize(p.join(destination, entry.name));
        if (entry.isSymbolicLink || !p.isWithin(destination, target)) {
          throw const FormatException('备份包含不安全的文件路径');
        }
        final file = File(target);
        await file.parent.create(recursive: true);
        final output = OutputFileStream(target);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
      }
    } finally {
      await archive.clear();
    }
  } finally {
    await input.close();
  }
}
