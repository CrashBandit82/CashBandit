import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/db.dart';
import 'providers.dart';
import 'services/app_lock.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'de_AT';
  await initializeDateFormatting('de_AT');
  final prefs = await SharedPreferences.getInstance();
  final lock = AppLock()..applySettings(AppSettings.load(prefs), initial: true);

  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      dbProvider.overrideWithValue(AppDatabase()),
      appLockProvider.overrideWithValue(lock),
    ],
    child: const CashBanditApp(),
  ));
}
