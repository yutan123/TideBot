#!/usr/bin/env python3
"""Snapshot notices from the locked SDK/packages and cached Maven metadata.

Run with an absolute project root. This reads files only; it never invokes
Flutter, Gradle, package resolution or compilation. --check detects drift.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def classify(text):
    low = text.lower()
    if 'gnu lesser general public license' in low:
        return 'LGPL（版本见原文）'
    if 'gnu general public license' in low:
        return 'GPL（版本见原文）'
    if 'apache license' in low and '2.0' in low:
        return 'Apache-2.0'
    if 'permission is hereby granted, free of charge' in low:
        return 'MIT'
    if 'redistribution and use in source and binary forms' in low:
        return 'BSD（条款见原文）'
    if 'sil open font license' in low:
        return 'OFL-1.1'
    return '许可及版权声明见原文'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--maven-cache', type=Path, default=Path('/root/.gradle/caches/modules-2/files-2.1'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    outputs = {}
    entries = []
    missing = []

    def output(name, data):
        outputs[name] = data.encode('utf-8') if isinstance(data, str) else data
        return name

    def add_file(entry, label, data, destination):
        digest = sha(data)
        if len(data) > 65536:
            destination = f'third_party/licenses/shared/{digest}.txt'
        output(destination, data)
        entry['files'].append({'name': label, 'path': destination, 'sha256': digest})

    def entry(name, version, category, source, license_name, description):
        item = dict(name=name, version=version, category=category, source=source,
                    license=license_name, description=description, files=[])
        entries.append(item)
        return item

    lock = (root/'pubspec.lock').read_text()
    locked = {}
    for name, body in re.findall(r'^  (\w+):\n(.*?)(?=^  \w+:\n|^sdks:)', lock, re.M | re.S):
        version = re.search(r'^    version: "?([^"\n]+)', body, re.M).group(1)
        dependency = re.search(r'^    dependency: "?([^"\n]+)', body, re.M).group(1)
        locked[name] = (version, dependency)
    config = json.loads((root/'.dart_tool/package_config.json').read_text())
    packages = {}
    for package in config['packages']:
        uri = package['rootUri']
        packages[package['name']] = (Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
            if uri.startswith('file:') else (root/'.dart_tool'/uri).resolve())
    sdk = packages['flutter'].parent.parent
    own = entry('TideBot', 'AGPL-3.0-only', '项目',
                'https://github.com/yutan123/TideBot-Dev', 'AGPL-3.0-only',
                'Copyright (C) 2025-2026 yutan123. 第三方版权和许可证不随项目版权人变更。')
    for name in ['LICENSE', 'COPYRIGHT']:
        own['files'].append({'name': name, 'path': name, 'sha256': sha((root/name).read_bytes())})

    # All locked packages, including transitive and development/other-platform
    # packages, are retained. Category is explicit; presence is not a claim that
    # every package is shipped in the Android binary.
    for name, (version, dependency) in sorted(locked.items()):
        path = packages[name]
        category = 'Dart/Flutter · ' + {'direct main': '直接依赖', 'direct dev': '开发依赖', 'transitive': '传递依赖'}[dependency]
        pubspec = (path/'pubspec.yaml').read_text()
        declared_version = re.search(r'^version:\s*[\'"]?([^\s\'"]+)', pubspec, re.M)
        if name not in ['flutter', 'flutter_test', 'flutter_web_plugins', 'sky_engine']:
            assert declared_version and declared_version.group(1) == version, name + ': package_config 与 lock 不一致'
        source = 'https://api.flutter.dev/' if name in ['flutter', 'flutter_test', 'flutter_web_plugins', 'sky_engine'] else f'https://pub.dev/packages/{name}/versions/{version}'
        description = re.search(r'^description:\s*(.*)', pubspec, re.M)
        description = description.group(1).strip().strip('"\'') if description else ''
        if description in ['>', '|', '>-', '|-']:
            description = '用途见包的 pubspec.yaml 和上游文档。'
        item = entry(name, version, category, source, '', description)
        files = []
        excluded = {'example', 'example_app', 'test', '.dart_tool', 'build', 'macos', 'website-next', '.git'}
        for directory, dirs, names in os.walk(path):
            dirs[:] = sorted(d for d in dirs if d not in excluded and not (Path(directory)/d).is_symlink())
            for filename in sorted(names):
                if not re.match(r'^(licen[cs]e|copying|notice|authors)([._-]|$)', filename, re.I):
                    continue
                f = Path(directory)/filename
                if f.is_symlink() or f.suffix.lower() in ['.dart', '.py', '.yml', '.yaml']:
                    continue
                files.append((str(f.relative_to(path)), f.read_bytes()))
        files.sort()
        if not files and name in ['flutter_test', 'flutter_web_plugins']:
            files = [('LICENSE', (sdk/'LICENSE').read_bytes())]
        assert files, '缺少上游许可: ' + name
        for rel, data in files:
            add_file(item, rel, data, f'third_party/licenses/dart/{name}-{version}/{rel}')
        item['license'] = '多项许可，见完整原文' if name == 'sky_engine' else classify(next((data for rel, data in files if rel.upper() == 'LICENSE'), files[0][1]).decode('utf-8', errors='replace'))
        if len(files) > 1:
            item['license'] += '；含附加声明'
        if name == 'ffmpeg_kit_flutter_new':
            item['license'] = 'LGPL-3.0 + GPL-3.0（原生 Full GPL）'
            add_file(item, '上游 README / 原生组件清单', (path/'README.md').read_bytes(),
                     f'third_party/licenses/dart/{name}-{version}/UPSTREAM-README.md')

    assets = [
        ('Unicode CLDR 中文表情名称', '48', 'Unicode-3.0', 'https://github.com/unicode-org/cldr/tree/release-48', '简体中文名称取自 annotations/zh.xml 与 annotationsDerived/zh.xml；按 EmojiTwo 旧序列适配，补译非标准符号并将部分字母缩写改写为中文。', ['assets/emojitwo/CLDR-LICENSE.txt', 'assets/emojitwo/CLDR-NOTICE.md']),
        ('BGE small zh v1.5 / Xenova ONNX', '75c43b069aac4d136ba6bc1122f995fedcfd2781', 'MIT', 'https://huggingface.co/Xenova/bge-small-zh-v1.5', '中文记忆语义检索模型和词表。', ['android/app/src/main/assets/memory_embedding/LICENSE']),
        ('LXGW Marker Gothic / 霞鹜漫黑', '内置字体', 'OFL-1.1', 'https://github.com/lxgw/LxgwMarkerGothic', '主字体；TideFont 仅为应用字体族别名，字体内容未修改。', ['assets/fonts/LXGWMarkerGothic-OFL.txt','assets/fonts/LXGWMarkerGothic-NOTICE.txt']),
        ('EmojiTwo / EmojiOne 2.2', '311eff547b3ff4a61fdbae897dd09d41416048fc', 'CC-BY-4.0（图像）/ MIT（JSON）', 'https://github.com/EmojiTwo/emojitwo/', 'Ranks.com 的 EmojiOne 2.2 和 EmojiTwo 社区贡献。2,023 张图像及 JSON 未修改；不表示上游认可本应用。', ['assets/emojitwo/LICENSE.md','assets/emojitwo/NOTICE.md']),
        ('Droid Sans Mono', '内置字体', 'Apache-2.0', 'https://android.googlesource.com/platform/frameworks/base/', '日志英文、数字和代码；Digitized data copyright © 2007, Google Corporation.', ['assets/fonts/LogMono-LICENSE.txt']),
        ('Noto Sans CJK SC', '内置字体', 'OFL-1.1', 'https://github.com/notofonts/noto-cjk', '日志中文字体；版权归原权利人，详见原文。', ['assets/fonts/LogSansSC-OFL.txt']),
    ]
    for name, version, lic, source, description, files in assets:
        item = entry(name, version, '内置资源', source, lic, description)
        for filename in files:
            item['files'].append({'name': Path(filename).name, 'path': filename, 'sha256': sha((root/filename).read_bytes())})
    dart = entry('Dart SDK', (sdk/'bin/cache/dart-sdk/version').read_text().strip(), 'SDK',
                 'https://github.com/dart-lang/sdk', 'BSD（见原文）', 'Dart 运行时；Flutter Engine 的完整第三方许可另见 sky_engine。')
    add_file(dart, 'LICENSE', (sdk/'bin/cache/dart-sdk/LICENSE').read_bytes(), 'third_party/licenses/sdk/Dart-LICENSE.txt')

    # Read declared native coordinates from the app and locked Android plugins.
    # A static POM graph is deliberately not called a Gradle resolved classpath.
    seeds = {}
    gradle_files = [(root/'android/app/build.gradle', 'TideBot Android')]
    gradle_files += [(f, name) for name, path in packages.items() if name != 'tide_bot'
                     for f in (path/'android').glob('build.gradle*')]
    global_vars = {'kotlin_version': '2.2.20'}
    for f, parent in gradle_files:
        text = '\n'.join(line for line in f.read_text().splitlines() if not line.strip().startswith('//'))
        variables = dict(global_vars)
        for key, value in re.findall(r'(?:ext\.|(?:val|def)\s+)?(\w+)\s*=\s*[\'"]([^\'"\n]+)[\'"]', text):
            variables[key] = value
        for coord in re.findall(r'\b(?:implementation|api|coreLibraryDesugaring)\s*\(?\s*[\'"]([^\'"\s]+:[^\'"\s]+:[^\'"\s]+)[\'"]', text):
            coord = re.sub(r'\$\{?(\w+)\}?', lambda m: variables.get(m[1], m[0]), coord)
            if '$' in coord:
                missing.append('未解析原生版本：' + parent + ' / ' + coord)
                continue
            seeds.setdefault(coord, set()).add(parent)

    namespace = {'m': 'http://maven.apache.org/POM/4.0.0'}
    def pom_path(g, a, v):
        candidates = list((args.maven_cache/g/a/v).glob('*/*.pom'))
        candidates += list((root/'third_party/upstream/maven'/g/a/v).glob('*/*.pom'))
        return candidates[0] if candidates else None

    effective_cache = {}

    def effective(g, a, v, seen=()):
        key = (g, a, v)
        if key in effective_cache:
            return effective_cache[key]
        path = pom_path(g, a, v)
        if path is None or key in seen:
            return {}, {}, [], []
        tree = ET.parse(path).getroot()
        props, managed, licenses, evidence = {}, {}, [], []
        parent = tree.find('m:parent', namespace)
        if parent is not None:
            pg, pa, pv = [parent.findtext('m:' + n, '', namespace) for n in ['groupId', 'artifactId', 'version']]
            pp, pm, pl, pe = effective(pg, pa, pv, seen + (key,))
            props, managed, licenses, evidence = dict(pp), dict(pm), list(pl), list(pe)
            if pom_path(pg, pa, pv) is None:
                missing.append(':'.join(key) + '：缺少父 POM ' + ':'.join([pg, pa, pv]))
        props.update({'project.version': v, 'pom.version': v, 'project.groupId': g, 'project.artifactId': a})
        properties = tree.find('m:properties', namespace)
        if properties is not None:
            props.update({x.tag.split('}')[-1]: x.text or '' for x in properties})
        def expand(value):
            for _ in range(12):
                expanded = re.sub(r'\$\{([^}]+)\}', lambda m: props.get(m[1], m[0]), value)
                if expanded == value:
                    break
                value = expanded
            return value
        props = {k: expand(v) for k, v in props.items()}
        own_licenses = [(x.findtext('m:name', '', namespace), x.findtext('m:url', '', namespace)) for x in tree.findall('m:licenses/m:license', namespace)]
        if own_licenses:
            licenses = own_licenses
        for d in tree.findall('m:dependencyManagement/m:dependencies/m:dependency', namespace):
            dg, da, dv = [expand(d.findtext('m:' + n, '', namespace)) for n in ['groupId', 'artifactId', 'version']]
            if d.findtext('m:scope', '', namespace) == 'import':
                bp, bm, bl, be = effective(dg, da, dv, seen + (key,))
                managed.update(bm)
                evidence.extend(be)
                if pom_path(dg, da, dv) is None:
                    missing.append(':'.join(key) + '：缺少 BOM ' + ':'.join([dg, da, dv]))
            else:
                managed[(dg, da)] = dv
        result = props, managed, licenses, list(dict.fromkeys(evidence + [path]))
        effective_cache[key] = result
        return result

    visited = {}
    queue = list(sorted(seeds))
    while queue:
        coord = queue.pop(0)
        if coord in visited:
            continue
        g, a, v = coord.split(':', 2)
        found_pom = pom_path(g, a, v)
        poms = [found_pom] if found_pom else []
        item = entry(coord, v, 'Android 原生 · ' + ('直接声明' if coord in seeds else 'POM 传递声明'),
                     ('https://dl.google.com/dl/android/maven2/' if g.startswith(('androidx.', 'com.google.android.', 'com.google.mlkit', 'com.google.firebase')) else 'https://repo.maven.apache.org/maven2/') + f'{g.replace(".", "/")}/{a}/{v}/{a}-{v}.pom', '',
                     '由 ' + '、'.join(sorted(seeds.get(coord, {'上游 POM'}))) + ' 引入。版本为声明值，未进行 Gradle 构建或发布包解析。')
        visited[coord] = item
        if coord == 'com.microsoft.onnxruntime:onnxruntime-android:1.20.0':
            for filename in ['LICENSE', 'ThirdPartyNotices.txt']:
                upstream = root/'third_party/upstream/onnxruntime-1.20.0'/filename
                if upstream.is_file():
                    add_file(item, 'ONNX Runtime v1.20.0 / ' + filename,
                             upstream.read_bytes(), f'third_party/licenses/android/onnxruntime-1.20.0/{filename}')
        if not poms:
            item['license'] = '上游许可，见来源；当前缺少原生制品元数据'
            missing.append(coord + '：本地无该版本 POM/制品，需核对上游随附声明')
            continue
        pom = poms[0]
        add_file(item, '上游 Maven POM', pom.read_bytes(), f'third_party/licenses/android/{g}/{a}/{v}/{a}-{v}.pom')
        tree = ET.parse(pom).getroot()
        props, managed, licenses, inherited = effective(g, a, v)
        for evidence in inherited:
            if evidence != pom:
                rel = evidence.relative_to(root) if evidence.is_relative_to(root) else Path(*evidence.parts[-5:])
                add_file(item, '继承元数据 / ' + evidence.name, evidence.read_bytes(), 'third_party/licenses/android/metadata/' + str(rel))
        item['license'] = ' / '.join(n for n, u in licenses) or '许可见上游父 POM / 随附文件'
        item['license_urls'] = [u for n, u in licenses if u]
        if coord == 'javax.inject:javax.inject:1':
            header = root/'third_party/upstream/javax.inject-1/Inject.java'
            if header.is_file():
                item['license'] = 'Apache-2.0（JSR-330 源码头声明）'
                licenses = [('Apache License, Version 2.0', 'https://www.apache.org/licenses/LICENSE-2.0.txt')]
                item['license_urls'] = [licenses[0][1]]
                add_file(item, 'JSR-330 原始版权和许可头 / Inject.java', header.read_bytes(), 'third_party/licenses/android/javax.inject-1/Inject.java')
        if not licenses:
            missing.append(coord + '：POM 未提供或继承许可证，需要核对随附声明')
        if any('apache' in name.lower() and '2' in name for name, url in licenses):
            apache = root/'third_party/upstream/Apache-2.0.txt'
            if apache.is_file():
                add_file(item, 'Apache-2.0 全文', apache.read_bytes(), 'third_party/licenses/Apache-2.0.txt')
        if coord == 'com.antonkarpenko:ffmpeg-kit-full-gpl:2.2.3':
            for upstream in sorted((root/'third_party/upstream/ffmpeg-kit-full-gpl-2.2.3').rglob('*')):
                if upstream.is_file():
                    rel = upstream.relative_to(root/'third_party/upstream/ffmpeg-kit-full-gpl-2.2.3')
                    add_file(item, '上游 / ' + str(rel), upstream.read_bytes(), 'third_party/licenses/android/ffmpeg-kit-full-gpl-2.2.3/' + str(rel))
            add_file(item, 'GPL-3.0 全文', (root/'third_party/licenses/GPL-3.0.txt').read_bytes(), 'third_party/licenses/GPL-3.0.txt')
            missing.append('FFmpegKit Full GPL 2.2.3：AAR 未附独立 NOTICE；已提取 ARM64 配置和启用库清单，但各内嵌库及其传递依赖的精确版本、附加版权、libc++/NDK 随附声明及对应构建源码仍需上游提供')

        for archive in sorted((args.maven_cache/g/a/v).glob('*/*')):
            if archive.suffix not in ['.jar', '.aar']:
                continue
            with zipfile.ZipFile(archive) as z:
                for name in sorted(z.namelist()):
                    if name.endswith('/') or not re.search(r'(?:^|/)(?:(?:LICENSES?|NOTICE|COPYING)(?:[.\-_]|$)|third_party_licenses\.(?:txt|json)$)', name, re.I):
                        continue
                    data = z.read(name)
                    try:
                        data.decode('utf-8')
                    except UnicodeDecodeError:
                        continue
                    add_file(item, archive.name + '/' + name, data,
                             f'third_party/licenses/android/{g}/{a}/{v}/{archive.name}/{name}')
        for d in tree.findall('m:dependencies/m:dependency', namespace):
            if d.findtext('m:scope', '', namespace) in ['test', 'provided'] or d.findtext('m:optional', '', namespace) == 'true':
                continue
            dg = d.findtext('m:groupId', '', namespace)
            da = d.findtext('m:artifactId', '', namespace)
            dv = d.findtext('m:version', '', namespace) or managed.get((dg, da), '')
            dv = re.sub(r'\$\{([^}]+)\}', lambda m: props.get(m[1], m[0]), dv)
            if dv.startswith('[') and dv.endswith(']') and ',' not in dv:
                dv = dv[1:-1]
            if not dv or '$' in dv or any(c in dv for c in '[],()'):
                missing.append(coord + ' → ' + dg + ':' + da + ':' + dv + '：版本需依赖管理解析')
                continue
            queue.append(':'.join([dg, da, dv]))

    ffmpeg = json.loads((root/'third_party/ffmpeg_components.json').read_text())
    configuration = (root/ffmpeg['evidence']).read_bytes()
    for name, flag, purpose, license_name, source in ffmpeg['components']:
        assert '--enable-' + flag in configuration.decode(), '未证实的 FFmpeg 启用项: ' + flag
        item = entry(name + '（FFmpegKit）', '内嵌版本未披露', 'FFmpeg 原生启用项', source,
                     license_name, purpose + '。' + ffmpeg['scope'])
        add_file(item, '原生制品配置字符串证据', configuration, ffmpeg['evidence'])

    # Persist precise upstream evidence, including known limitations. No guessed
    # copyright holders are substituted for missing upstream evidence.
    manifest = dict(schema=1, lock_sha256=sha((root/'pubspec.lock').read_bytes()),
                    dart_packages=len(locked), entries=entries, review_required=sorted(set(missing)))
    output('third_party/notices_manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    # Include the pre-existing resource explanations and source references.
    intro = (root/'third_party/NOTICES_INTRO.md').read_text().replace('](../', '](')
    lines = [intro.rstrip(), '', '## Flutter / Dart 锁定依赖', '',
             f'共 {len(locked)} 个锁定包，逐项保留许可全文及附加声明。开发依赖和其他平台实现为源码依赖，不表示均打入 Android 应用。', '',
             '| 名称 | 版本 | 依赖类别 | 用途（上游说明） | 许可及原文 |', '| --- | --- | --- | --- | --- |']
    for item in entries:
        if item['category'].startswith('Dart/Flutter'):
            links = '、'.join(f'[{f["name"]}]({urllib.parse.quote(f["path"], safe="/")})' for f in item['files'])
            lines.append(f'| [{item["name"]}]({item["source"]}) | {item["version"]} | {item["category"].split(" · ")[-1]} | {item["description"].replace(chr(124), chr(47))} | {item["license"]}：{links} |')
    lines += ['', '## Android 原生依赖声明', '',
              '下表从项目及锁定 Flutter 插件的 Android 依赖声明递归读取本地 Maven POM。可能包含同一组件的不同请求版本；这不是发布 APK 的解析版本清单。ML Kit 和 Google Play services 为第三方 SDK，不能一概标成 Apache 开源组件。', '',
              '| Maven 坐标 | 许可 / 条款 | 元数据及随附声明 |', '| --- | --- | --- |']
    for item in visited.values():
        links = '、'.join(f'[{f["name"]}]({urllib.parse.quote(f["path"], safe="/")})' for f in item['files'])
        lines.append(f'| [{item["name"]}]({item["source"]}) | {item["license"]} | {links or "见上游来源"} |')
    lines += ['', '## FFmpegKit 内嵌库与启用项', '', ffmpeg['scope'], '',
              '| 名称 | 用途 | 上游许可范围 |', '| --- | --- | --- |']
    for name, flag, purpose, license_name, source in ffmpeg['components']:
        lines.append(f'| [{name}]({source}) | {purpose}（`--enable-{flag}`） | {license_name} |')
    lines += ['', '原生配置另启用 Android MediaCodec/JNI 等系统接口；使用系统 API 不等于再分发该系统实现。FFmpeg 本身的版本字符串为 n8.1.2，原文许可随 Full GPL 条目保留。', '']
    lines += ['', '## 核对范围与仍需取得的上游材料', '',
              'Flutter/Dart 许可原文按锁定包保存；Flutter Engine 的综合许可见 sky_engine/LICENSE（含其上游组件的原始版权及许可）。Rive Android CMake 使用 ios/ 下的源码，这些目录的原始许可也已保留。', '',
              '以下列出仍无法从现有上游材料核定的项目。不能将它们视为已完成二进制许可证审计；发布时还应随实际原生制品保留全部 NOTICE，并提供 GPL/LGPL 所要求的对应源码及构建材料。', '']
    lines += ['- ' + issue for issue in sorted(set(missing))]
    lines += ['', '## 更新与校验', '',
              '依赖变更后运行 `python3 third_party/update_notices.py --root <项目绝对路径>`；加 `--check` 校验快照。此工具只读取 SDK、锁定包和本地 Maven 材料，不执行编译。逐文件 SHA-256 及来源见 [notices_manifest.json](third_party/notices_manifest.json)。', '']
    markdown = '\n'.join(lines)
    output('THIRD_PARTY_NOTICES.md', markdown)
    if args.check:
        bad = [name for name, data in outputs.items() if not (root/name).is_file() or (root/name).read_bytes() != data]
        if bad:
            raise SystemExit('OUTDATED: ' + ', '.join(bad))
        print(f'PASS: {len(locked)} Dart packages, {len(visited)} native declarations, {len(outputs)} exact snapshots; {len(set(missing))} native review items explicitly recorded')
    else:
        for name, data in outputs.items():
            p = root/name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        print(f'Generated {len(outputs)} files: {len(locked)} Dart packages / {len(visited)} native declarations; {len(set(missing))} native review items')


if __name__ == '__main__':
    main()
