// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<void> startSdkLive({bool oneTurn = false}) async {
  try {
    final current = js_util.getProperty(html.window, '__ASSISTANT_API_BASE');
    if (current == null || (current is String && current.isEmpty)) {
      final origin = html.window.location.origin;
      js_util.setProperty(html.window, '__ASSISTANT_API_BASE', '$origin/api/lessons');
    }
  } catch (_) {}
  try {
    final result = js_util.callMethod(html.window, 'startSdkLive', [oneTurn]);
    if (result is Future) { await result; }
    else { try { await js_util.promiseToFuture(result); } catch (_) {} }
  } catch (_) {}
}

Future<void> stopSdkLive() async {
  try {
    final result = js_util.callMethod(html.window, 'stopSdkLive', const []);
    if (result is Future) { await result; }
    else { try { await js_util.promiseToFuture(result); } catch (_) {} }
  } catch (_) {}
}


