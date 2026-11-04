"""Check the actual bundled font faces without building Flutter or Android.

Run: python3 -m unittest discover -s test -p log_font_assets_test.py
"""
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_font(relative_path):
    data = (ROOT / relative_path).read_bytes()
    count = struct.unpack_from('>H', data, 4)[0]
    tables = {}
    for i in range(count):
        tag, _, offset, size = struct.unpack_from('>4sIII', data, 12 + i * 16)
        tables[tag] = data[offset:offset + size]
    return tables


def family_names(tables):
    table = tables[b'name']
    _, count, strings = struct.unpack_from('>HHH', table)
    names = set()
    for i in range(count):
        platform, _, _, name_id, size, offset = struct.unpack_from(
            '>HHHHHH', table, 6 + i * 12)
        if name_id == 1:
            raw = table[strings + offset:strings + offset + size]
            names.add(raw.decode('utf-16-be' if platform in (0, 3) else 'mac_roman'))
    return names


class LogFontAssetsTest(unittest.TestCase):
    def test_baseline_faces_are_regular_fonts(self):
        # w400 in Dart does not fix an Android-loaded variable font whose
        # default wght is 100. Check font bytes, not just the style declaration.
        for filename, family in [
            ('LogMono.ttf', 'Droid Sans Mono'),
            ('LogSansSC.otf', 'Noto Sans CJK SC'),
        ]:
            with self.subTest(font=filename):
                tables = read_font('assets/fonts/' + filename)
                if b'fvar' in tables:
                    axes = tables[b'fvar']
                    offset = struct.unpack_from('>H', axes, 4)[0]
                    count, size = struct.unpack_from('>HH', axes, 8)
                    defaults = {}
                    for i in range(count):
                        tag, _, default, _ = struct.unpack_from(
                            '>4siii', axes, offset + i * size)
                        defaults[tag] = default / 65536
                    self.assertEqual(defaults[b'wght'], 400)
                self.assertEqual(struct.unpack_from('>H', tables[b'OS/2'], 4)[0], 400)
                self.assertIn(family, family_names(tables))
                self.assertIn(b'cmap', tables)

    def test_main_font_asset_matches_flutter_and_android(self):
        # The file name identifies the upstream font; TideFont remains the
        # shared Flutter/native API name used throughout the application.
        asset = 'assets/fonts/LXGWMarkerGothic-Regular.ttf'
        pubspec = (ROOT / 'pubspec.yaml').read_text()
        native = (ROOT / 'android/app/src/main/kotlin/com/yutan123/tidebot/NativeSelectableText.kt').read_text()
        self.assertEqual(pubspec.count('asset: ' + asset), 2)
        self.assertIn('family: TideFont', pubspec)
        self.assertIn('"TideFont" -> runCatching', native)
        self.assertIn('.getLookupKeyForAsset("' + asset + '")', native)
        self.assertNotIn('assets/fonts/TideFont-Regular.ttf', pubspec + native)
        self.assertFalse((ROOT / 'assets/fonts/TideFont-Regular.ttf').exists())
        tables = read_font(asset)
        self.assertIn('LXGW Marker Gothic', family_names(tables))
        self.assertEqual(struct.unpack_from('>H', tables[b'OS/2'], 4)[0], 400)
        self.assertIn(b'cmap', tables)

    def test_flutter_and_android_use_the_same_cjk_asset(self):
        pubspec = (ROOT / 'pubspec.yaml').read_text()
        native = (ROOT / 'android/app/src/main/kotlin/com/yutan123/tidebot/NativeSelectableText.kt').read_text()
        self.assertIn('asset: assets/fonts/LogSansSC.otf', pubspec)
        self.assertIn('"LogSansSC.otf"', native)
        self.assertNotIn('LogSansSC.ttf', pubspec)


if __name__ == '__main__':
    unittest.main()
