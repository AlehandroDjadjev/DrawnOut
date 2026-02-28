import 'dart:io' show Platform;

/// On native platforms, check if running on Android.
bool get isAndroid => Platform.isAndroid;
