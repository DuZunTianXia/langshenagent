import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The phone's native side (Android's `MainActivity` and services), over
/// the channels the app's manifest declares.
abstract final class PhonePlatform {
  static const _app = MethodChannel('langshenagent/app');
  static const _haptics = MethodChannel('langshenagent/haptics');
  static const _update = MethodChannel('langshenagent/update');

  static VoidCallback? _onNetworkChanged;

  /// Registers a callback fired by the native side when the device's
  /// active network changes (e.g. Wi-Fi ↔ cellular, or reconnected).
  static void setNetworkChangedHandler(VoidCallback? handler) {
    _onNetworkChanged = handler;
    if (!native) return;
    _app.setMethodCallHandler((call) async {
      if (call.method == 'networkChanged') {
        _onNetworkChanged?.call();
      }
    });
  }

  /// Whether there is a native side to ask (not the web, not tests).
  static bool get native => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The foreground service kept while a computer is connected, so the
  /// link lives in the background. [title] names it in the shade.
  static Future<void> keepAlive({
    required String title,
    required String text,
  }) async {
    if (!native) return;
    try {
      await _app.invokeMethod('keepAlive', {
        'title': title,
        'text': text,
        'channelName': '宝码',
      });
    } on Object {
      // The service is a nicety: the link goes on without it.
    }
  }

  /// The foreground service is no longer wanted.
  /// Asks the system to exempt the app from battery optimizations (the
  /// doze that would freeze the link); true when it was exempt already.
  static Future<bool> ensureBatteryExempt() async {
    if (!native) return true;
    try {
      return await _app.invokeMethod<bool>('batteryExempt') == true;
    } on Object {
      return false;
    }
  }

  static Future<void> letGo() async {
    if (!native) return;
    try {
      await _app.invokeMethod('letGo');
    } on Object {
      // Platform calls are best-effort: absent elsewhere.
    }
  }

  /// What another app shared into LangshenAgent (`SEND`/`VIEW` intents), as
  /// `{"path", "name", "mime"}` each, taken once; empty for none.
  static Future<List<Map<String, Object?>>> take() async {
    if (!native) return const [];
    try {
      final taken = await _app.invokeMethod<List<Object?>>('take');
      return [
        for (final item in taken ?? const [])
          if (item is Map) item.cast<String, Object?>(),
      ];
    } on Object {
      return const [];
    }
  }

  /// Launches the device camera to capture a photo and returns the temporary
  /// JPEG file path, or null when cancelled or unavailable.
  static Future<String?> takePhoto() async {
    if (!native) return null;
    try {
      return await _app.invokeMethod<String>('takePhoto');
    } on Object {
      return null;
    }
  }

  /// A haptic of [kind] (`select`, `success`, `warning`, `error`,
  /// `impactLight`, …), as the app's own do.
  static Future<void> haptic(String kind) async {
    if (!native) return;
    try {
      await _haptics.invokeMethod('play', {'kind': kind});
    } on Object {
      // Platform calls are best-effort: absent elsewhere.
    }
  }

  /// Whether this build can install an update over itself.
  static Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _update.invokeMethod<bool>('canInstall') ?? false;
    } on Object {
      return false;
    }
  }

  /// The ABIs this phone runs, for picking an update's package.
  static Future<List<String>> abis() async {
    if (!Platform.isAndroid) return const [];
    try {
      return [
        ...?await _update.invokeMethod<List<Object?>>('abis'),
      ].whereType<String>().toList();
    } on Object {
      return const [];
    }
  }

  /// Opens the system's screen for installing apps from this one.
  static Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _update.invokeMethod('openInstallSettings');
    } on Object {
      // Platform calls are best-effort: absent elsewhere.
    }
  }

  /// Installs the update package at [path] (downloaded by the app).
  static Future<void> install(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _update.invokeMethod('install', {'path': path});
    } on Object {
      // Platform calls are best-effort: absent elsewhere.
    }
  }

  // --- Notifications ------------------------------------------------------------

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _notificationsReady = false;
  static void Function(String payload)? _onNotificationTap;

  /// Registers a handler called when the user taps a local notification.
  static void setNotificationTapHandler(
    void Function(String payload)? handler,
  ) {
    _onNotificationTap = handler;
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _onNotificationTap?.call(payload);
    }
  }

  /// Asks for POST_NOTIFICATIONS up front (Android 13+): by the time a
  /// session needs the user the app is already away.
  static Future<void> requestNotifications() async {
    if (!native) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notifications.initialize(
        settings: const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } on Object {
      // Platform calls are best-effort: absent elsewhere.
    }
  }

  /// Local notifications for a session needing the user while the app is
  /// away (Android has no APNs: the phone says it itself).
  static Future<void> notify({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!native) return;
    try {
      if (!_notificationsReady) {
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _notifications.initialize(
          settings: const InitializationSettings(android: android),
          onDidReceiveNotificationResponse: _handleNotificationResponse,
        );
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'langshenagent',
                '宝码',
                importance: Importance.high,
              ),
            );
        _notificationsReady = true;
      }
      await _notifications.show(
        id: (payload ?? title).hashCode & 0x7fffffff,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'langshenagent',
            '宝码',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } on Object {
      // Platform calls are best-effort: absent elsewhere.
    }
  }
}
