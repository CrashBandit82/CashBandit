import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/recurring_runner.dart';
import 'providers.dart';
import 'services/notifications.dart';
import 'services/settings.dart';
import 'ui/home_shell.dart';
import 'ui/lock_screen.dart';
import 'ui/theme.dart';

class CashBanditApp extends ConsumerStatefulWidget {
  const CashBanditApp({super.key});

  @override
  ConsumerState<CashBanditApp> createState() => _CashBanditAppState();
}

class _CashBanditAppState extends ConsumerState<CashBanditApp> with WidgetsBindingObserver {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runRecurring()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider);
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        lock.onBackground();
      case AppLifecycleState.resumed:
        lock.onForeground();
        unawaited(_runRecurring());
      default:
        break;
    }
  }

  /// Fills in due recurring bookings (start and every return to the app).
  Future<void> _runRecurring() async {
    if (_running) return;
    _running = true;
    try {
      final created = await runDueRecurring(ref.read(dbProvider));
      if (created > 0 && ref.read(settingsProvider).notifyRecurring) {
        await requestNotificationPermission();
        await showRecurringCreated(created);
      }
    } catch (e) {
      debugPrint('recurring run failed: $e');
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, s) => ref.read(appLockProvider).applySettings(s));
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'CashBandit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: const Locale('de', 'AT'),
      supportedLocales: const [Locale('de', 'AT'), Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
      builder: (context, child) => LockGate(lock: ref.watch(appLockProvider), child: child!),
    );
  }
}
