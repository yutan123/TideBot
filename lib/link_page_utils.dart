import 'dart:convert';
import 'package:http/http.dart' as http;

/// 短链必须使用 GET 逐跳解析；自动重定向后的 response.request 不保证是最终地址。
Future<({Uri uri, http.Response response})> fetchLinkPage(
  http.Client client,
  Uri uri,
  Map<String, String> headers,
) async {
  final visited = <Uri>{};
  final cookiesByHost = <String, Map<String, String>>{};
  var retriedNonce = false;
  for (var hop = 0; hop < 8; hop++) {
    if (!visited.add(uri) || !['http', 'https'].contains(uri.scheme)) {
      throw const FormatException('无效的链接重定向');
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll(headers);
    final cookies = cookiesByHost[uri.host];
    if (cookies != null && cookies.isNotEmpty) {
      request.headers['Cookie'] = cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    }
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 10));
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      final jar = cookiesByHost.putIfAbsent(uri.host, () => {});
      for (final cookie in setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
        final pair = cookie.split(';').first.trim();
        final equals = pair.indexOf('=');
        if (equals > 0)
          jar[pair.substring(0, equals)] = pair.substring(equals + 1);
      }
    }
    final location = response.headers['location'];
    if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
        location != null) {
      uri = uri.resolve(location);
      continue;
    }
    // Some Douyin share responses first set a nonce cookie on a 200 page.
    // Replay once with that cookie instead of treating the shell as the video.
    if (!retriedNonce &&
        response.statusCode == 200 &&
        (uri.host == 'douyin.com' ||
            uri.host.endsWith('.douyin.com') ||
            uri.host == 'iesdouyin.com' ||
            uri.host.endsWith('.iesdouyin.com')) &&
        setCookie?.contains('_ac_nonce=') == true) {
      retriedNonce = true;
      visited.remove(uri);
      continue;
    }
    return (uri: uri, response: response);
  }
  throw const FormatException('链接重定向次数过多');
}

/// 页面脚本中的 JSON：跳过字符串里的大括号，兼容赋值空格和可选分号。
Map<String, dynamic>? extractPageState(String html, String marker) {
  final assignment =
      RegExp('${RegExp.escape(marker)}\\s*=\\s*').firstMatch(html);
  if (assignment == null) return null;
  final start = html.indexOf('{', assignment.end);
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < html.length; i++) {
    final ch = html[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
    } else if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}' && --depth == 0) {
      try {
        // undefined 是小红书状态数据中的 JS 字面量，不能替换字符串正文。
        final raw = html.substring(start, i + 1).replaceAllMapped(
              RegExp(r'"(?:\\.|[^"\\])*"|\bundefined\b'),
              (m) => m[0] == 'undefined' ? 'null' : m[0]!,
            );
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

Map<String, dynamic>? findVideoItem(dynamic node) {
  if (node is Map) {
    if ((node['video'] is Map || node['images'] is List) &&
        (node.containsKey('aweme_id') ||
            node.containsKey('awemeId') ||
            node.containsKey('desc'))) {
      return Map<String, dynamic>.from(node);
    }
    for (final value in node.values) {
      final found = findVideoItem(value);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = findVideoItem(value);
      if (found != null) return found;
    }
  }
  return null;
}
