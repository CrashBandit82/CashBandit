import 'package:cashbandit/core/dates.dart';
import 'package:cashbandit/core/recurrence.dart';
import 'package:cashbandit/core/stats.dart';
import 'package:cashbandit/data/backup.dart';
import 'package:cashbandit/data/db.dart';
import 'package:cashbandit/data/default_categories.dart';
import 'package:cashbandit/data/recurring_runner.dart';
import 'package:cashbandit/data/repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CashRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CashRepository(db);
  });
  tearDown(() => db.close());

  Future<Category> cat(String name) async =>
      (await db.select(db.categories).get()).firstWhere((c) => c.name == name);

  Future<List<Booking>> allBookings() =>
      (db.select(db.bookings)..orderBy([(b) => OrderingTerm(expression: b.day), (b) => OrderingTerm(expression: b.id)])).get();

  test('first start creates the default categories with distinct colors', () async {
    final all = await db.select(db.categories).get();
    expect(all.map((c) => c.name), defaultCategories.map((d) => d.$1));
    expect(all.where((c) => c.kind == EntryKind.income).map((c) => c.name), ['Lohn', 'sonstige Einnahmen']);
    expect(all.map((c) => c.color).toSet().length, all.length);
  });

  group('recurring', () {
    test('catches up all missed bookings once, no duplicates', () async {
      final miete = await cat('Miete');
      await repo.saveBooking(
        BookingDraft(categoryId: miete.id, amountCents: 85000, day: DateTime(2026, 1, 31), note: 'Wohnung'),
        repeat: const RepeatDraft(interval: RepeatInterval.monthly, dayOfMonth: 31),
      );
      expect(await runDueRecurring(db, until: DateTime(2026, 5, 15)), 3);
      expect(await runDueRecurring(db, until: DateTime(2026, 5, 15)), 0);
      final days = (await allBookings()).map((b) => b.day).toList();
      expect(days, ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
      final auto = (await allBookings()).where((b) => b.isAuto).toList();
      expect(auto.length, 3);
      expect(auto.every((b) => b.note == 'Wohnung' && b.amountCents == 85000), isTrue);
      expect(await runDueRecurring(db, until: DateTime(2026, 5, 31)), 1);
    });

    test('respects max count and end date', () async {
      final lohn = await cat('Lohn');
      await repo.saveBooking(
        BookingDraft(categoryId: lohn.id, amountCents: 300000, day: DateTime(2026, 1, 1)),
        repeat: const RepeatDraft(interval: RepeatInterval.monthly, maxCount: 3),
      );
      await repo.saveBooking(
        BookingDraft(categoryId: lohn.id, amountCents: 1000, day: DateTime(2026, 1, 5)),
        repeat: RepeatDraft(interval: RepeatInterval.weekly, endDay: DateTime(2026, 1, 20)),
      );
      await runDueRecurring(db, until: DateTime(2027, 1, 1));
      final b = await allBookings();
      expect(b.where((x) => x.amountCents == 300000).length, 3);
      expect(b.where((x) => x.amountCents == 1000).map((x) => x.day), ['2026-01-05', '2026-01-12', '2026-01-19']);
    });

    test('day of month after the first booking starts in the same month', () async {
      final c = await cat('Versicherungen');
      await repo.saveBooking(
        BookingDraft(categoryId: c.id, amountCents: 5000, day: DateTime(2026, 3, 10)),
        repeat: const RepeatDraft(interval: RepeatInterval.monthly, dayOfMonth: 15),
      );
      await runDueRecurring(db, until: DateTime(2026, 4, 20));
      expect((await allBookings()).map((b) => b.day), ['2026-03-10', '2026-03-15', '2026-04-15']);
    });

    test('pause skips the paused time, edits only affect the future', () async {
      final c = await cat('Diverses');
      await repo.saveBooking(
        BookingDraft(categoryId: c.id, amountCents: 1000, day: DateTime(2026, 1, 1)),
        repeat: const RepeatDraft(interval: RepeatInterval.monthly),
      );
      await runDueRecurring(db, until: DateTime(2026, 2, 1));
      var rule = (await db.select(db.recurringRules).get()).single;
      await repo.setPaused(rule, true);
      expect(await runDueRecurring(db, until: DateTime(2026, 6, 1)), 0);

      rule = (await db.select(db.recurringRules).get()).single;
      await repo.updateRule(
        rule,
        categoryId: c.id,
        amountCents: 2000,
        note: 'neu',
        repeat: const RepeatDraft(interval: RepeatInterval.monthly, dayOfMonth: 10),
        nextDay: DateTime(2026, 6, 10),
      );
      // still paused
      expect(await runDueRecurring(db, until: DateTime(2026, 7, 1)), 0);
      rule = (await db.select(db.recurringRules).get()).single;
      await (db.update(db.recurringRules)).write(const RecurringRulesCompanion(paused: Value(false)));
      expect(await runDueRecurring(db, until: DateTime(2026, 7, 15)), 2);
      final b = await allBookings();
      expect(b.map((x) => '${x.day}:${x.amountCents}'), [
        '2026-01-01:1000',
        '2026-02-01:1000',
        '2026-06-10:2000',
        '2026-07-10:2000',
      ]);
      expect(nextOccurrence((await db.select(db.recurringRules).get()).single), DateTime(2026, 8, 10));
    });

    test('deleting a rule keeps its bookings', () async {
      final c = await cat('Diverses');
      await repo.saveBooking(
        BookingDraft(categoryId: c.id, amountCents: 1000, day: DateTime(2026, 1, 1)),
        repeat: const RepeatDraft(interval: RepeatInterval.weekly),
      );
      await runDueRecurring(db, until: DateTime(2026, 1, 15));
      final rule = (await db.select(db.recurringRules).get()).single;
      await repo.deleteRule(rule.id);
      final b = await allBookings();
      expect(b.length, 3);
      expect(b.every((x) => x.recurringId == null), isTrue);
    });
  });

  group('categories', () {
    test('delete moves bookings and rules to the replacement', () async {
      final a = await cat('Hygiene');
      final b = await cat('Gesundheit');
      await repo.saveBooking(BookingDraft(categoryId: a.id, amountCents: 500, day: DateTime(2026, 1, 1)));
      await repo.saveBooking(
        BookingDraft(categoryId: a.id, amountCents: 700, day: DateTime(2026, 1, 1)),
        repeat: const RepeatDraft(interval: RepeatInterval.monthly),
      );
      expect(await repo.usageCount(a.id), 3);
      await repo.deleteCategory(a.id, replacementId: b.id);
      expect((await allBookings()).every((x) => x.categoryId == b.id), isTrue);
      expect((await db.select(db.recurringRules).getSingle()).categoryId, b.id);
    });

    test('delete without replacement fails while bookings exist', () async {
      final a = await cat('Hygiene');
      await repo.saveBooking(BookingDraft(categoryId: a.id, amountCents: 500, day: DateTime(2026, 1, 1)));
      await expectLater(repo.deleteCategory(a.id), throwsA(anything));
      expect((await allBookings()).length, 1);
    });

    test('reorder within one kind keeps other positions', () async {
      final all = await repo.watchCategories().first;
      final income = all.where((c) => c.kind == EntryKind.income).map((c) => c.id).toList();
      await repo.reorderCategories(income.reversed.toList());
      final after = await repo.watchCategories().first;
      expect(after.where((c) => c.kind == EntryKind.income).map((c) => c.id), income.reversed);
      expect(after.first.name, 'Lebensmittel');
    });
  });

  group('queries and stats', () {
    test('filter by range, kind, category and note search', () async {
      final food = await cat('Lebensmittel');
      final lohn = await cat('Lohn');
      await repo.saveBooking(BookingDraft(categoryId: food.id, amountCents: 1250, day: DateTime(2026, 10, 1), note: 'Spar 100%'));
      await repo.saveBooking(BookingDraft(categoryId: food.id, amountCents: 800, day: DateTime(2026, 10, 20), note: 'Billa'));
      await repo.saveBooking(BookingDraft(categoryId: lohn.id, amountCents: 300000, day: DateTime(2026, 10, 15)));
      await repo.saveBooking(BookingDraft(categoryId: food.id, amountCents: 999, day: DateTime(2026, 9, 30)));

      final oct = periodRange(PeriodMode.month, DateTime(2026, 10, 1));
      final rows = await repo.watchBookings(BookingQuery(range: oct)).first;
      expect(rows.length, 3);
      final t = Totals.of(rows);
      expect((t.income, t.expense, t.balance), (300000, 2050, 297950));
      expect((await repo.watchBookings(const BookingQuery(search: 'billa')).first).single.booking.amountCents, 800);
      expect((await repo.watchBookings(const BookingQuery(search: '100%')).first).single.booking.amountCents, 1250);
      expect((await repo.watchBookings(const BookingQuery(search: '%')).first).length, 1);
      expect((await repo.watchBookings(const BookingQuery(kind: EntryKind.income)).first).length, 1);
      expect((await repo.watchBookings(BookingQuery(categoryId: food.id)).first).length, 3);

      final share = breakdown(rows, EntryKind.expense).single;
      expect(share.cents, 2050);
      expect(share.share, 1.0);

      final weeks = fillExpenses(weekBuckets(oct), rows);
      expect(weeks.first.label, 'KW 40');
      expect(weeks.fold<int>(0, (s, b) => s + b.total), 2050);
      expect(weeks.first.range.from, DateTime(2026, 10, 1));
      expect(weeks.last.range.to, DateTime(2026, 10, 31));

      final history = await repo.watchBookings(BookingQuery(range: monthsRange(oct.to, 12))).first;
      final months = monthlyTotals(history, oct.to, 12);
      expect(months.length, 12);
      expect(months.last.totals.expense, 2050);
      expect(months[10].totals.expense, 999);
      expect(months.first.month, DateTime(2025, 11, 1));
    });

    test('undo restores a deleted booking', () async {
      final food = await cat('Lebensmittel');
      final id = await repo.saveBooking(BookingDraft(categoryId: food.id, amountCents: 100, day: DateTime(2026, 1, 1)));
      final b = (await repo.booking(id))!;
      await repo.deleteBooking(id);
      expect(await allBookings(), isEmpty);
      await repo.restoreBooking(b);
      expect((await allBookings()).single, b);
    });
  });

  group('backup', () {
    test('JSON round trip restores everything', () async {
      final food = await cat('Lebensmittel');
      await repo.addCategory(name: 'Haustier', kind: EntryKind.expense, color: 0xFF123456, icon: 'pet');
      await repo.saveBooking(BookingDraft(categoryId: food.id, amountCents: 1250, day: DateTime(2026, 10, 1), note: 'a;"b"'));
      await repo.saveBooking(
        BookingDraft(categoryId: food.id, amountCents: 999, day: DateTime(2026, 9, 1)),
        repeat: const RepeatDraft(interval: RepeatInterval.monthly, maxCount: 5),
      );
      await runDueRecurring(db, until: DateTime(2026, 10, 15));
      final json = await exportJson(db);

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await CashRepository(other).addCategory(name: 'weg damit', kind: EntryKind.income, color: 0, icon: 'misc');
      await importBackup(other, parseBackup(json));

      expect(await other.select(other.categories).get(), await db.select(db.categories).get());
      expect(await other.select(other.bookings).get(), await db.select(db.bookings).get());
      expect(await other.select(other.recurringRules).get(), await db.select(db.recurringRules).get());
      // nothing due twice after the import
      expect(await runDueRecurring(other, until: DateTime(2026, 10, 15)), 0);
    });

    test('rejects foreign or broken files', () {
      expect(() => parseBackup('nope'), throwsA(isA<BackupException>()));
      expect(() => parseBackup('{"format":"other"}'), throwsA(isA<BackupException>()));
      expect(() => parseBackup('{"format":"cashbandit-backup","version":99}'), throwsA(isA<BackupException>()));
      expect(
        () => parseBackup('{"format":"cashbandit-backup","version":1,"categories":[],"recurring":[],'
            '"bookings":[{"id":1,"categoryId":7,"amountCents":5,"day":"2026-01-01","note":"","recurringId":null,"isAuto":false}]}'),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => parseBackup('{"format":"cashbandit-backup","version":1,"categories":[],"recurring":[],'
            '"bookings":[{"id":1,"categoryId":7,"amountCents":5,"day":"2026-02-30","note":"","recurringId":null,"isAuto":false}]}'),
        throwsA(isA<BackupException>()),
      );
    });

    test('CSV uses semicolons, signed decimal comma and quoting', () async {
      final food = await cat('Lebensmittel');
      final lohn = await cat('Lohn');
      await repo.saveBooking(BookingDraft(categoryId: food.id, amountCents: 123456, day: DateTime(2026, 10, 1), note: 'a;"b"'));
      await repo.saveBooking(BookingDraft(categoryId: lohn.id, amountCents: 5, day: DateTime(2026, 10, 2)));
      final lines = (await exportCsv(db)).split('\r\n');
      expect(lines[0], '\uFEFFDatum;Typ;Kategorie;Betrag;Notiz;Wiederkehrend');
      expect(lines[1], '01.10.2026;Ausgabe;Lebensmittel;-1234,56;"a;""b""";nein');
      expect(lines[2], '02.10.2026;Einnahme;Lohn;0,05;;nein');
    });
  });
}
