// Platform bridge to JS window.startSdkLive/stopSdkLive (web only). No-ops elsewhere.

export 'sdk_live_bridge_stub.dart' if (dart.library.html) 'sdk_live_bridge_web.dart';


