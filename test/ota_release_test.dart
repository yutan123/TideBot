import 'package:flutter_test/flutter_test.dart';
import 'package:tide_bot/ota_release.dart';

void main() {
  Map<String, dynamic> release({
    required String tag,
    bool draft = false,
    bool prerelease = false,
    List<Map<String, String>> assets = const [
      {
        'name': 'TideBot.apk',
        'browser_download_url': 'https://example.com/TideBot.apk',
      },
    ],
  }) {
    return {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'assets': assets,
    };
  }

  group('OtaReleasePicker', () {
    test('strips v prefixes and build metadata', () {
      expect(
        OtaReleasePicker.versionOf({'tag_name': 'v1.0.2+3'}),
        '1.0.2',
      );
    });

    test('prefers TideBot.apk over other apk assets', () {
      final urls = OtaReleasePicker.apkUrls({
        'assets': [
          {
            'name': 'other.apk',
            'browser_download_url': 'https://example.com/other.apk',
          },
          {
            'name': 'TideBot.apk',
            'browser_download_url': 'https://example.com/TideBot.apk',
          },
        ],
      });
      expect(urls.first, 'https://example.com/TideBot.apk');
    });

    test('skips drafts, prereleases and releases without apk', () {
      final picked = OtaReleasePicker.pickLatest([
        release(tag: 'v1.2.0', draft: true),
        release(tag: 'v1.1.0', prerelease: true),
        release(tag: 'v1.0.9', assets: const []),
        release(tag: 'v1.0.3'),
        release(tag: 'v1.0.1'),
      ]);
      expect(picked?['tag_name'], 'v1.0.3');
    });

    test('returns null when no published apk exists', () {
      expect(
        OtaReleasePicker.pickLatest([
          release(tag: 'v2.0.0', draft: true),
          release(tag: 'v2.0.0-beta', prerelease: true),
        ]),
        isNull,
      );
    });
  });
}
