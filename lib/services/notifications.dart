import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _plugin = FlutterLocalNotificationsPlugin();
bool _initialized = false;

Future<void> _init() async {
  if (_initialized) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
  );
  _initialized = true;
}

/// Asks for the Android 13+ notification permission (once).
Future<bool> requestNotificationPermission() async {
  await _init();
  final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? true;
}

/// "3 wiederkehrende Buchungen eingetragen" – replaces the previous one.
Future<void> showRecurringCreated(int count) async {
  if (count <= 0) return;
  try {
    await _init();
    await _plugin.show(
      id: 1,
      title: 'CashBandit',
      body: count == 1
          ? '1 wiederkehrende Buchung wurde eingetragen.'
          : '$count wiederkehrende Buchungen wurden eingetragen.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'recurring',
          'Wiederkehrende Buchungen',
          channelDescription: 'Hinweis, wenn wiederkehrende Buchungen automatisch eingetragen wurden',
          importance: Importance.defaultImportance,
          color: Color(0xFF2E6B3A),
        ),
      ),
    );
  } on Exception {
    // a notification must never break the app
  }
}
