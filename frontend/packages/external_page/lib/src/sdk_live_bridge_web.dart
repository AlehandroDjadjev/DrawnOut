import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> _awaitThenable(dynamic result) async {
  if (result == null) return;
  if (result is Future) {
    await result;
    return;
  }

  // Best-effort: if it's a JS Promise/thenable, await it.
  try {
    final thenFn = (result as dynamic).then;
    if (thenFn == null) return;
    final c = Completer<void>();
    (result as dynamic).then(
      (_) => c.complete(),
      (Object? _) => c.complete(),
    );
    await c.future;
  } catch (_) {
    // Ignore
  }
}

Future<void> startSdkLive({bool oneTurn = false}) async {
  try {
    final w = html.window as dynamic;
    final result = w.startSdkLive(oneTurn);
    await _awaitThenable(result);
  } catch (_) {}
}

Future<void> stopSdkLive() async {
  try {
    final w = html.window as dynamic;
    final result = w.stopSdkLive();
    await _awaitThenable(result);
  } catch (_) {}
}


