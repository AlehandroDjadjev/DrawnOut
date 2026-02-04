// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:js' as js;
import 'package:js/js.dart' show allowInterop;

Future<T?> _promiseToFuture<T>(dynamic promise) {
  if (promise is Future<T>) return promise;
  if (promise is! js.JsObject) return Future<T?>.value(promise as T?);

  final c = Completer<T?>();
  try {
    promise.callMethod('then', [
      allowInterop((dynamic value) {
        if (!c.isCompleted) c.complete(value as T?);
      })
    ]);
    promise.callMethod('catch', [
      allowInterop((dynamic _) {
        if (!c.isCompleted) c.complete(null);
      })
    ]);
  } catch (_) {
    if (!c.isCompleted) c.complete(null);
  }
  return c.future;
}

Future<void> startSdkLive({bool oneTurn = false}) async {
  try {
    final current = js.context['__ASSISTANT_API_BASE'];
    if (current == null || (current is String && current.isEmpty)) {
      final origin = html.window.location.origin;
      js.context['__ASSISTANT_API_BASE'] = '$origin/api/lessons';
    }
  } catch (_) {}
  try {
    final result = js.context.callMethod('startSdkLive', [oneTurn]);
    await _promiseToFuture<void>(result);
  } catch (_) {}
}

Future<void> stopSdkLive() async {
  try {
    final result = js.context.callMethod('stopSdkLive', const []);
    await _promiseToFuture<void>(result);
  } catch (_) {}
}


