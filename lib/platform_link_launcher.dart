import 'package:url_launcher/url_launcher.dart';
import 'link_preview_models.dart';
import 'link_preview_service.dart';

/// Resolve short links in-process, then try the content's app route first.
Future<bool> launchPlatformLink(
  LinkPreviewData data, {
  Future<LinkPreviewData> Function(String)? resolvePreview,
  Future<bool> Function(Uri)? openUrl,
}) async {
  final open = openUrl ??
      (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
  var target = data;
  if (target.appUri == null) {
    try {
      target = await (resolvePreview ??
          LinkPreviewService.instance.fetchPreview)(data.url);
    } catch (_) {
      // A temporary preview error must not prevent opening the original URL.
    }
  }
  final appUri = target.appUri;
  if (appUri != null) {
    try {
      if (await open(appUri)) return true;
    } catch (_) {}
  }
  final uri = Uri.tryParse(target.url);
  if (uri != null) {
    try {
      return await open(uri);
    } catch (_) {}
  }
  return false;
}
