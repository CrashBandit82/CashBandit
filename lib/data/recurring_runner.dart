import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/recurrence.dart';
import 'db.dart';

/// Creates all bookings of recurring rules that are due up to [until]
/// (default: today). Runs on app start and on every return to the app, so
/// nothing is missed when the app was closed for a while.
///
/// Every rule is advanced in the same transaction as its bookings
/// (`nextIndex`, `lastRunDay`), so a second run never creates duplicates.
/// Returns the number of bookings created.
Future<int> runDueRecurring(AppDatabase db, {DateTime? until}) {
  final limit = dateOnly(until ?? DateTime.now());
  return db.transaction(() async {
    final rules = await (db.select(db.recurringRules)..where((r) => r.paused.equals(false))).get();
    var created = 0;
    for (final r in rules) {
      final start = parseDay(r.startDay);
      final notBefore = r.notBeforeDay == null ? null : parseDay(r.notBeforeDay!);
      final end = r.endDay == null ? null : parseDay(r.endDay!);
      var last = r.lastRunDay == null ? null : parseDay(r.lastRunDay!);
      var index = r.nextIndex;
      var count = r.generatedCount;
      final newRows = <BookingsCompanion>[];
      while (true) {
        if (r.maxCount != null && count >= r.maxCount!) break;
        final d = occurrence(start: start, interval: r.interval, dayOfMonth: r.dayOfMonth, index: index);
        if (d.isAfter(limit) || (end != null && d.isAfter(end))) break;
        index++;
        if ((last != null && !d.isAfter(last)) || (notBefore != null && d.isBefore(notBefore))) continue;
        newRows.add(BookingsCompanion.insert(
          categoryId: r.categoryId,
          amountCents: r.amountCents,
          day: dayKey(d),
          note: Value(r.note),
          recurringId: Value(r.id),
          isAuto: const Value(true),
        ));
        count++;
        last = d;
      }
      if (index == r.nextIndex) continue;
      await db.batch((b) => b.insertAll(db.bookings, newRows));
      await (db.update(db.recurringRules)..where((t) => t.id.equals(r.id))).write(RecurringRulesCompanion(
        nextIndex: Value(index),
        generatedCount: Value(count),
        lastRunDay: Value(last == null ? null : dayKey(last)),
      ));
      created += newRows.length;
    }
    return created;
  });
}
