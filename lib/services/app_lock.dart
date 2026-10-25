import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'pin.dart';
import 'settings.dart';

const _pinKey = 'pin_hash';
const _window = MethodChannel('at.macrobandit.cashbandit/window');

/// Hides the app content in the task switcher and blocks screenshots
/// (FLAG_SECURE, see MainActivity.kt).
Future<void> setSecureWindow(bool secure) async {
  try {
    await _window.invokeMethod<void>('setSecure', secure);
  } on MissingPluginException {
    // tests / non-Android
  }
}

/// App lock state: locked on start and after the configured time in the
/// background. Unlock with biometrics or the PIN.
class AppLock extends ChangeNotifier {
  AppLock({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ?? const FlutterSecureStorage(),
        _auth = auth ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  AppSettings _settings = const AppSettings();
  bool _locked = false;
  DateTime? _backgroundSince;
  int _suspended = 0;
  int _failed = 0;
  DateTime? _blockedUntil;

  bool get locked => _locked;
  bool get biometricsEnabled => _settings.biometrics;

  /// Wrong PIN entries lock the PIN pad for a while.
  Duration get blockedFor {
    final until = _blockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Called with the settings at start and whenever they change.
  void applySettings(AppSettings s, {bool initial = false}) {
    _settings = s;
    if (initial && s.lockEnabled) _locked = true;
    if (!s.lockEnabled && _locked) {
      _locked = false;
      notifyListeners();
    }
    setSecureWindow(s.lockEnabled);
  }

  /// Runs [action] (file dialog, share sheet, biometric prompt) without
  /// locking when the app briefly goes to the background for it.
  Future<T> suspendWhile<T>(Future<T> Function() action) async {
    _suspended++;
    try {
      return await action();
    } finally {
      _suspended--;
      _backgroundSince = null;
    }
  }

  void onBackground() {
    if (_suspended > 0 || _locked) return;
    _backgroundSince ??= DateTime.now();
  }

  void onForeground() {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (!_settings.lockEnabled || _locked || _suspended > 0 || since == null) return;
    if (DateTime.now().difference(since).inSeconds >= _settings.lockAfterSeconds) {
      _locked = true;
      notifyListeners();
    }
  }

  void _unlock() {
    _locked = false;
    _failed = 0;
    _blockedUntil = null;
    notifyListeners();
  }

  Future<bool> hasPin() async => (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) async {
    assert(isValidPin(pin));
    final hash = await Isolate.run(() => hashPin(pin));
    await _storage.write(key: _pinKey, value: hash);
  }

  Future<void> removePin() => _storage.delete(key: _pinKey);

  /// Checks [pin] without changing the lock state.
  Future<bool> checkPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    if (stored == null) return false;
    return Isolate.run(() => verifyPin(pin, stored));
  }

  /// Returns true if the app was unlocked.
  Future<bool> unlockWithPin(String pin) async {
    if (blockedFor > Duration.zero) return false;
    if (await checkPin(pin)) {
      _unlock();
      return true;
    }
    _failed++;
    if (_failed >= 5) _blockedUntil = DateTime.now().add(Duration(seconds: 30 * (_failed - 4)));
    notifyListeners();
    return false;
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// Shows the system biometric prompt; true on success.
  Future<bool> authenticateBiometric(String reason) async {
    try {
      return await suspendWhile(() => _auth.authenticate(localizedReason: reason, biometricOnly: true));
    } on Exception catch (e) {
      debugPrint('biometric auth failed: $e');
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!_settings.biometrics || !_locked) return false;
    final ok = await authenticateBiometric('CashBandit entsperren');
    if (ok) _unlock();
    return ok;
  }
}
