import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class _Keys {
  static const theme = 'theme_mode';
  static const notifications = 'notify_recurring';
  static const lock = 'lock_enabled';
  static const biometrics = 'lock_biometrics';
  static const lockAfter = 'lock_after_seconds';
}

/// Lock delays offered in the settings (seconds in background).
const lockDelays = <int, String>{0: 'sofort', 60: 'nach 1 Minute', 300: 'nach 5 Minuten'};

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.notifyRecurring = true,
    this.lockEnabled = false,
    this.biometrics = false,
    this.lockAfterSeconds = 0,
  });

  final ThemeMode themeMode;
  final bool notifyRecurring;
  final bool lockEnabled;
  final bool biometrics;
  final int lockAfterSeconds;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? notifyRecurring,
    bool? lockEnabled,
    bool? biometrics,
    int? lockAfterSeconds,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        notifyRecurring: notifyRecurring ?? this.notifyRecurring,
        lockEnabled: lockEnabled ?? this.lockEnabled,
        biometrics: biometrics ?? this.biometrics,
        lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
      );

  static AppSettings load(SharedPreferences p) => AppSettings(
        themeMode: ThemeMode.values.asNameMap()[p.getString(_Keys.theme)] ?? ThemeMode.system,
        notifyRecurring: p.getBool(_Keys.notifications) ?? true,
        lockEnabled: p.getBool(_Keys.lock) ?? false,
        biometrics: p.getBool(_Keys.biometrics) ?? false,
        lockAfterSeconds: p.getInt(_Keys.lockAfter) ?? 0,
      );

  Future<void> save(SharedPreferences p) async {
    await p.setString(_Keys.theme, themeMode.name);
    await p.setBool(_Keys.notifications, notifyRecurring);
    await p.setBool(_Keys.lock, lockEnabled);
    await p.setBool(_Keys.biometrics, biometrics);
    await p.setInt(_Keys.lockAfter, lockAfterSeconds);
  }
}

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('overridden in main'));

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.read(prefsProvider));

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await state.save(ref.read(prefsProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
