// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('startSdkLive')
external JSPromise? _jsStartSdkLive([bool oneTurn]);

@JS('stopSdkLive')
external JSPromise? _jsStopSdkLive();

Future<void> startSdkLive({bool oneTurn = false}) async {
  try {
    final current = globalContext['__ASSISTANT_API_BASE'];
    final dartVal = current?.dartify()?.toString() ?? '';
    if (dartVal.isEmpty) {
      final origin = html.window.location.origin;
      globalContext['__ASSISTANT_API_BASE'] = '$origin/api/lessons'.toJS;
    }
  } catch (_) {}
  try {
    final promise = _jsStartSdkLive(oneTurn);
    if (promise != null) await promise.toDart;
  } catch (_) {}
}

Future<void> stopSdkLive() async {
  try {
    final promise = _jsStopSdkLive();
    if (promise != null) await promise.toDart;
  } catch (_) {}
}
