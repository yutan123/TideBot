#!/usr/bin/env python3
"""Fetch missing upstream POM evidence without running a build.

Run update_notices.py first, then this script, and regenerate notices. Existing
snapshots are retained; downloads are validated as Maven XML before saving.
"""
import argparse
import concurrent.futures
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = json.loads((root/'third_party/notices_manifest.json').read_text())
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    coords = set()
    for item in manifest['entries']:
        if item['category'].startswith('Android'):
            coords.add(item['name'])
    for issue in manifest['review_required']:
        match = re.search(r'缺少\s*(?:父 POM|BOM) ([^\s]+)', issue)
        if match:
            coords.add(match[1])
    cache = Path('/root/.gradle/caches/modules-2/files-2.1')
    upstream = root/'third_party/upstream/maven'
    tasks = []
    for coord in sorted(coords):
        g, a, v = coord.split(':', 2)
        if not v or '$' in v:
            continue
        if list((cache/g/a/v).glob('*/*.pom')) or list((upstream/g/a/v).glob('*/*.pom')):
            continue
        base = 'https://dl.google.com/dl/android/maven2/' if g.startswith(('androidx.', 'com.google.android.', 'com.google.mlkit', 'com.google.firebase')) else 'https://repo.maven.apache.org/maven2/'
        url = base + f'{g.replace(".", "/")}/{a}/{v}/{a}-{v}.pom'
        tasks.append((url, upstream/g/a/v/'download'/f'{a}-{v}.pom'))

    def fetch(task):
        url, path = task
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                data = response.read()
            if ET.fromstring(data).tag != '{' + ns['m'] + '}project':
                raise ValueError('Not a Maven project')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            return None
        except Exception as error:
            return f'{url}: {error}'

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        errors = [error for error in pool.map(fetch, tasks) if error]
    print(f'Downloaded {len(tasks)-len(errors)}/{len(tasks)} upstream POMs')
    for error in errors:
        print(error)


if __name__ == '__main__':
    main()
