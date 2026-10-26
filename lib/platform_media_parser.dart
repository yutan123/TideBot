import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'link_page_utils.dart';

/// Platforms use several page-state envelopes across desktop and share pages.
Iterable<Map<String, dynamic>> platformPageStates(String html) sync* {
  for (final marker in [
    '_ROUTER_DATA',
    'window.__INITIAL_STATE__',
    'window.__INITIAL_DATA__',
  ]) {
    final state = extractPageState(html, marker);
    if (state != null) yield state;
  }
  final document = html_parser.parse(html);
  for (final id in ['RENDER_DATA', '__NEXT_DATA__']) {
    final text = document.getElementById(id)?.text.trim();
    if (text == null || text.isEmpty) continue;
    try {
      final decoded =
          jsonDecode(text.startsWith('%') ? Uri.decodeComponent(text) : text);
      if (decoded is Map) yield Map<String, dynamic>.from(decoded);
    } catch (_) {
      // An incomplete or non-JSON state must not hide other page formats.
    }
  }
}

Map<String, dynamic>? findNoteData(dynamic node, String? id) {
  if (node is Map) {
    final details = node['noteDetailMap'];
    if (details is Map) {
      final selected =
          details[id] ?? (details.length == 1 ? details.values.first : null);
      final note = selected is Map ? selected['note'] : null;
      if (note is Map) return Map<String, dynamic>.from(note);
    }
    if ((node['imageList'] is List || node['video'] is Map) &&
        (node.containsKey('noteId') ||
            node.containsKey('title') && node.containsKey('type'))) {
      final actualId = node['noteId'] ?? node['id'];
      if (id == null || actualId == null || actualId == id) {
        return Map<String, dynamic>.from(node);
      }
    }
    for (final value in node.values) {
      final note = findNoteData(value, id);
      if (note != null) return note;
    }
  } else if (node is List) {
    for (final value in node) {
      final note = findNoteData(value, id);
      if (note != null) return note;
    }
  }
  return null;
}

String? mediaUrl(dynamic value) {
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.startsWith('//') ? 'https:$raw' : raw;
    final uri = Uri.tryParse(normalized);
    return uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? normalized
        : null;
  }
  if (value is List) {
    for (final item in value) {
      final url = mediaUrl(item);
      if (url != null) return url;
    }
  } else if (value is Map) {
    for (final key in [
      'masterUrl',
      'master_url',
      'url_list',
      'urlList',
      'urlDefault',
      'url_default',
      'url',
      'src',
      'backupUrls',
      'backup_urls',
      'cover',
      'origin_cover',
      'originCover',
      'dynamic_cover',
      'dynamicCover',
    ]) {
      final url = mediaUrl(value[key]);
      if (url != null) return url;
    }
  }
  return null;
}

String? douyinVideoUrl(Map item) {
  final video = item['video'];
  if (video is! Map) return null;
  for (final key in [
    'play_addr',
    'playAddr',
    'play_addr_h264',
    'playAddrH264',
    'download_addr',
    'downloadAddr'
  ]) {
    final url = mediaUrl(video[key]);
    if (url != null) return url;
  }
  final rates = video['bit_rate'] ?? video['bitRate'];
  if (rates is List) {
    for (final rate in rates) {
      if (rate is! Map) continue;
      final url = mediaUrl(rate['play_addr'] ?? rate['playAddr']);
      if (url != null) return url;
    }
  }
  return null;
}

String? noteVideoUrl(Map note) {
  final video = note['video'];
  if (video is! Map) return null;
  final media = video['media'];
  final stream = media is Map ? media['stream'] : null;
  if (stream is Map) {
    for (final codec in ['h264', 'h265', 'av1']) {
      final url = mediaUrl(stream[codec]);
      if (url != null) return url;
    }
  }
  return mediaUrl(video['url'] ?? video['playUrl'] ?? video['play_url']);
}

List<String> noteImageUrls(Map note) {
  final images = note['imageList'] ?? note['images'];
  if (images is! List) return const [];
  return images
      .map((image) {
        final direct = mediaUrl(image);
        if (direct != null) return direct;
        return image is Map ? mediaUrl(image['infoList']) : null;
      })
      .whereType<String>()
      .toSet()
      .toList();
}

String? pageVideoUrl(String html) {
  final document = html_parser.parse(html);
  for (final selector in [
    'meta[property="og:video:secure_url"]',
    'meta[property="og:video:url"]',
    'meta[property="og:video"]',
    'video[src]',
    'video source[src]',
  ]) {
    final element = document.querySelector(selector);
    final url =
        mediaUrl(element?.attributes['content'] ?? element?.attributes['src']);
    final uri = url == null ? null : Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final pageHost = [
      'douyin.com',
      'iesdouyin.com',
      'xiaohongshu.com',
      'bilibili.com',
      'b23.tv',
      'xhslink.com',
      'xhslink.cn'
    ].any((domain) => host == domain || host.endsWith('.$domain'));
    if (url != null && !pageHost) {
      return url;
    }
  }
  return null;
}
