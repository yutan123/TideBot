class OtaReleasePicker {
  static String versionOf(Map<String, dynamic> release) {
    final raw =
        (release['tag_name'] ?? release['name'] ?? '').toString().trim();
    return raw.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
  }

  static List<String> apkUrls(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return const [];
    final preferred = <String>[];
    final fallback = <String>[];
    for (final raw in assets.whereType<Map>()) {
      final name = raw['name']?.toString() ?? '';
      final url = raw['browser_download_url']?.toString() ?? '';
      if (!url.startsWith('https://') || !name.toLowerCase().endsWith('.apk')) {
        continue;
      }
      if (name.toLowerCase() == 'tidebot.apk') {
        preferred.add(url);
      } else {
        fallback.add(url);
      }
    }
    return [...preferred, ...fallback];
  }

  static int compareVersions(String a, String b) {
    final aa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < (aa.length > bb.length ? aa.length : bb.length); i++) {
      final x = i < aa.length ? aa[i] : 0;
      final y = i < bb.length ? bb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Map<String, dynamic>? pickLatest(Iterable<dynamic> releases) {
    Map<String, dynamic>? best;
    var bestVersion = '';
    for (final raw in releases) {
      if (raw is! Map) continue;
      final release = Map<String, dynamic>.from(raw);
      if (release['draft'] == true) continue;
      if (release['prerelease'] == true) continue;
      if (apkUrls(release).isEmpty) continue;
      final version = versionOf(release);
      if (version.isEmpty) continue;
      if (best == null || compareVersions(version, bestVersion) > 0) {
        best = release;
        bestVersion = version;
      }
    }
    return best;
  }
}
