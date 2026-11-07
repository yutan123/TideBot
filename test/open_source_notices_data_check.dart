import 'dart:convert';
import 'dart:io';

import 'package:tide_bot/open_source_notices_data.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final parsed = decodeOpenSourceNotices(jsonEncode({
    'schema': 1,
    'texts': {'shared': 'Original copyright\nLicense text'},
    'entries': [
      {
        'documents': [
          {'name': 'Overview', 'text': 'Inline text'},
          {'name': 'Component A', 'sha256': 'shared'},
          {'name': 'Component B', 'sha256': 'shared'},
        ],
      },
    ],
  }));
  final documents = parsed.single['documents'] as List;
  require(documents[0]['text'] == 'Inline text', 'Inline text lost');
  require(documents[1]['text'] == 'Original copyright\nLicense text',
      'Shared text did not resolve');
  require(documents[2]['name'] == 'Component B', 'Component label lost');
  for (final invalid in [
    {'schema': 2, 'entries': []},
    {
      'schema': 1,
      'entries': [
        {
          'documents': [
            {'sha256': 'missing'},
          ],
        },
      ],
    },
  ]) {
    var rejected = false;
    try {
      decodeOpenSourceNotices(jsonEncode(invalid));
    } on FormatException {
      rejected = true;
    }
    require(rejected, 'Invalid notice data was accepted');
  }
  final root = Platform.script.resolve('../');
  final entries = decodeOpenSourceNotices(
      File.fromUri(root.resolve('assets/legal/notices.json'))
          .readAsStringSync());
  final manifest = jsonDecode(
      File.fromUri(root.resolve('third_party/notices_manifest.json'))
          .readAsStringSync()) as Map<String, dynamic>;
  require(entries.length == (manifest['entries'] as List).length + 1,
      'Offline asset and manifest entries differ');
  require(
      entries
              .where((entry) =>
                  (entry['category'] as String).startsWith('Dart/Flutter'))
              .length ==
          manifest['dart_packages'],
      'Locked package coverage differs');
  for (final entry in entries) {
    for (final document in entry['documents'] as List) {
      require(document['text'] is String,
          'Unresolved document in ${entry['name']}');
    }
  }
  print('PASS: inline/shared texts, invalid references, schema, and '
      '${entries.length} real bundled entries');
}
