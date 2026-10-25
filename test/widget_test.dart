import 'package:cashbandit/app.dart';
import 'package:cashbandit/data/db.dart';
import 'package:cashbandit/providers.dart';
import 'package:cashbandit/services/app_lock.dart';
import 'package:cashbandit/services/settings.dart';
import 'package:cashbandit/ui/lock_screen.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('add an expense and see it on the dashboard and in the list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    Intl.defaultLocale = 'de_AT';
    await initializeDateFormatting('de_AT');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());

    // drift streams need real async time; pumpAndSettle would wait forever
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        dbProvider.overrideWithValue(db),
        appLockProvider.overrideWithValue(AppLock()),
      ],
      child: const CashBanditApp(),
    ));
    await settle();

    expect(find.text('CashBandit'), findsWidgets);
    expect(find.text('Saldo'), findsOneWidget);

    await tester.tap(find.byTooltip('Neue Buchung'));
    await settle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Betrag'), '1.234,56');
    await tester.tap(find.text('Lebensmittel'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Notiz (optional)'), 'Wocheneinkauf');
    await tester.tap(find.text('Speichern'));
    await settle();

    expect(find.text('Neue Buchung'), findsNothing);
    // header (saldo + pill) and category breakdown
    expect(find.text('−1.234,56 €'), findsOneWidget);
    expect(find.text('1.234,56 €'), findsWidgets);
    expect(find.text('100,0 %'), findsOneWidget);

    await tester.tap(find.text('Buchungen').last);
    await settle();
    expect(find.text('Wocheneinkauf'), findsOneWidget);

    await tester.tap(find.text('Regelmäßig').last);
    await settle();
    expect(find.textContaining('Noch keine wiederkehrenden'), findsOneWidget);

    await tester.tap(find.text('Einstellungen').last);
    await settle();
    expect(find.text('Sicherung exportieren (JSON)'), findsOneWidget);

    await tester.runAsync(db.close);
  });

  testWidgets('lock screen covers the app while locked', (tester) async {
    final lock = AppLock()..applySettings(const AppSettings(lockEnabled: true), initial: true);
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, child: const Text('Kontostand'))));
    expect(find.text('CashBandit ist gesperrt'), findsOneWidget);
    expect(find.text('Kontostand'), findsNothing); // offstage, not painted
    expect(find.text('Kontostand', skipOffstage: false), findsOneWidget); // state kept
  });
}
