// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void triggerWebDownload(String url, String fileName) {
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..target = '_blank';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } catch (_) {
    html.window.open(url, '_blank');
  }
}
