#!/usr/bin/env python3
"""Validate notice files, hashes, offline references and local Markdown links."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import urllib.parse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = json.loads((root/'third_party/notices_manifest.json').read_text())
    bundle = json.loads((root/'assets/legal/notices.json').read_text())
    referenced = set()
    count = 0
    for item in manifest['entries']:
        for document in item['files']:
            path = root/document['path']
            if hashlib.sha256(path.read_bytes()).hexdigest() != document['sha256']:
                raise ValueError('Incorrect hash: ' + document['path'])
            referenced.add(document['path'])
            count += 1
    for digest, text in bundle['texts'].items():
        if hashlib.sha256(text.encode()).hexdigest() != digest:
            raise ValueError('Incorrect shared text hash: ' + digest)
    for item in bundle['entries']:
        for document in item['documents']:
            if 'text' not in document and document['sha256'] not in bundle['texts']:
                raise ValueError('Missing text: ' + item['name'])
    locked = set(re.findall(r'^  (\w+):$', (root/'pubspec.lock').read_text(), re.M))
    included = {item['name'] for item in manifest['entries'] if item['category'].startswith('Dart/Flutter')}
    if locked != included:
        raise ValueError('Locked package coverage mismatch')
    for filename in ['THIRD_PARTY_NOTICES.md', 'README.md', 'third_party/NOTICES_INTRO.md']:
        path = root/filename
        for target in re.findall(r'\]\(([^)]+)\)', path.read_text()):
            if target.startswith(('http:', 'https:', '#', 'mailto:')):
                continue
            destination = (path.parent/urllib.parse.unquote(target.split('#')[0])).resolve()
            if not destination.is_file():
                raise ValueError('Broken local link: ' + filename + ' -> ' + target)
    for filename in ['LICENSE', 'COPYRIGHT', 'README.md', 'lib/legal_pages.dart']:
        text = (root/filename).read_text()
        if 'Copyright (C) 2025-2026 yutan123.' not in text or 'TideBot contributors' in text:
            raise ValueError('Incorrect project ownership: ' + filename)
    print(f'PASS: {count} file hashes, {len(bundle["texts"])} shared texts, locked package coverage, offline references, local links and ownership')
    print('Categories:', dict(Counter(item['category'].split(' · ')[0] for item in manifest['entries'])))
    print('Offline asset bytes:', (root/'assets/legal/notices.json').stat().st_size)
    print('Unresolved upstream evidence:', len(manifest['review_required']))
    for issue in manifest['review_required']:
        print(issue)
    stale = []
    for directory in ['dart', 'android', 'sdk', 'shared']:
        for path in (root/'third_party/licenses'/directory).rglob('*'):
            if path.is_file() and str(path.relative_to(root)) not in referenced:
                stale.append(path)
    print('Unreferenced generated snapshots:', len(stale), sum(path.stat().st_size for path in stale), 'bytes')
    for path in stale:
        print(path.relative_to(root))


if __name__ == '__main__':
    main()
