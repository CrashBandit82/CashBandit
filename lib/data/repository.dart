import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/recurrence.dart';
import 'db.dart';

class BookingRow {
  const BookingRow(this.booking, this.category);
  final Booking booking;
  final Category category;

  EntryKind get kind => category.kind;

  /// Signed amount: income positive, expense negative.
  int get signedCents => kind == EntryKind.income ? booking.amountCents : -booking.amountCents;
}

class RecurringRow {
  const RecurringRow(this.rule, this.category);
  final RecurringRule rule;
  final Category category;
}

/// Filter for booking lists. All fields optional.
class BookingQuery {
  const BookingQuery({this.range, this.categoryId, this.kind, this.search = ''});
  final DayRange? range;
  final int? categoryId;
  final EntryKind? kind;
  final String search;

  BookingQuery copyWith({
    DayRange? Function()? range,
    int? Function()? categoryId,
    EntryKind? Function()? kind,
    String? search,
  }) =>
      BookingQuery(
        range: range != null ? range() : this.range,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        kind: kind != null ? kind() : this.kind,
        search: search ?? this.search,
      );

  bool get isFiltered => range != null || categoryId != null || kind != null || search.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is BookingQuery &&
      other.range == range &&
      other.categoryId == categoryId &&
      other.kind == kind &&
      other.search == search;

  @override
  int get hashCode => Object.hash(range, categoryId, kind, search);
}

/// Values of the booking form.
class BookingDraft {
  const BookingDraft({required this.categoryId, required this.amountCents, required this.day, this.note = ''});
  final int categoryId;
  final int amountCents;
  final DateTime day;
  final String note;
}

/// Schedule of a recurring rule (from the booking or rule form).
class RepeatDraft {
  const RepeatDraft({required this.interval, this.dayOfMonth, this.endDay, this.maxCount});
  final RepeatInterval interval;
  final int? dayOfMonth;
  final DateTime? endDay;
  final int? maxCount;
}

class CashRepository {
  CashRepository(this.db);
  final AppDatabase db;

  // ---------------------------------------------------------------- categories

  Stream<List<Category>> watchCategories() =>
      (db.select(db.categories)..orderBy([(c) => OrderingTerm(expression: c.sortOrder), (c) => OrderingTerm(expression: c.id)]))
          .watch();

  Future<int> addCategory({required String name, required EntryKind kind, required int color, required String icon}) async {
    final max = db.categories.sortOrder.max();
    final row = await (db.selectOnly(db.categories)..addColumns([max])).getSingle();
    return db.into(db.categories).insert(CategoriesCompanion.insert(
          name: name,
          kind: kind,
          color: color,
          icon: icon,
          sortOrder: Value((row.read(max) ?? -1) + 1),
        ));
  }

  Future<void> updateCategory(Category c) => db.update(db.categories).replace(c);

  /// [orderedIds] in their new order; other categories keep their places.
  Future<void> reorderCategories(List<int> orderedIds) => db.transaction(() async {
        final all = await (db.select(db.categories)..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).get();
        final slots = all.where((c) => orderedIds.contains(c.id)).map((c) => c.sortOrder).toList()..sort();
        for (final (i, id) in orderedIds.indexed) {
          await (db.update(db.categories)..where((c) => c.id.equals(id)))
              .write(CategoriesCompanion(sortOrder: Value(slots[i])));
        }
      });

  /// Bookings and recurring rules that would be affected by deleting a category.
  Future<int> usageCount(int categoryId) async {
    final b = await (db.select(db.bookings)..where((t) => t.categoryId.equals(categoryId))).get();
    final r = await (db.select(db.recurringRules)..where((t) => t.categoryId.equals(categoryId))).get();
    return b.length + r.length;
  }

  /// Deletes a category. Bookings and rules move to [replacementId] first.
  Future<void> deleteCategory(int id, {int? replacementId}) => db.transaction(() async {
        if (replacementId != null) {
          await (db.update(db.bookings)..where((t) => t.categoryId.equals(id)))
              .write(BookingsCompanion(categoryId: Value(replacementId)));
          await (db.update(db.recurringRules)..where((t) => t.categoryId.equals(id)))
              .write(RecurringRulesCompanion(categoryId: Value(replacementId)));
        }
        // fails (foreign key) if anything still uses the category – no data loss
        await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
      });

  // ------------------------------------------------------------------ bookings

  Stream<List<BookingRow>> watchBookings(BookingQuery q) {
    final query = db.select(db.bookings).join([
      innerJoin(db.categories, db.categories.id.equalsExp(db.bookings.categoryId)),
    ]);
    if (q.range != null) {
      query.where(db.bookings.day.isBetweenValues(q.range!.fromKey, q.range!.toKey));
    }
    if (q.categoryId != null) query.where(db.bookings.categoryId.equals(q.categoryId!));
    if (q.kind != null) query.where(db.categories.kind.equalsValue(q.kind));
    final s = q.search.trim();
    if (s.isNotEmpty) query.where(db.bookings.note.lower().like('%${_escapeLike(s.toLowerCase())}%', escapeChar: r'\'));
    query.orderBy([OrderingTerm.desc(db.bookings.day), OrderingTerm.desc(db.bookings.id)]);
    return query.watch().map((rows) => [
          for (final r in rows) BookingRow(r.readTable(db.bookings), r.readTable(db.categories)),
        ]);
  }

  Future<Booking?> booking(int id) => (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// Saves a booking; with [repeat] a recurring rule is created that starts
  /// with this booking as its first occurrence.
  Future<int> saveBooking(BookingDraft d, {int? id, RepeatDraft? repeat}) => db.transaction(() async {
        final companion = BookingsCompanion(
          categoryId: Value(d.categoryId),
          amountCents: Value(d.amountCents),
          day: Value(dayKey(d.day)),
          note: Value(d.note.trim()),
        );
        final bookingId = id == null
            ? await db.into(db.bookings).insert(companion)
            : (await (db.update(db.bookings)..where((b) => b.id.equals(id))).write(companion), id).$2;
        if (repeat != null) {
          final ruleId = await db.into(db.recurringRules).insert(RecurringRulesCompanion.insert(
                categoryId: d.categoryId,
                amountCents: d.amountCents,
                note: Value(d.note.trim()),
                interval: repeat.interval,
                dayOfMonth: Value(repeat.interval.usesDayOfMonth ? repeat.dayOfMonth : null),
                startDay: dayKey(d.day),
                lastRunDay: Value(dayKey(d.day)),
                generatedCount: const Value(1),
                maxCount: Value(repeat.maxCount),
                endDay: Value(repeat.endDay == null ? null : dayKey(repeat.endDay!)),
              ));
          await (db.update(db.bookings)..where((b) => b.id.equals(bookingId)))
              .write(BookingsCompanion(recurringId: Value(ruleId)));
        }
        return bookingId;
      });

  Future<void> deleteBooking(int id) => (db.delete(db.bookings)..where((b) => b.id.equals(id))).go();

  /// Undo for [deleteBooking]: inserts the row again with its old id.
  Future<void> restoreBooking(Booking b) => db.into(db.bookings).insert(b, mode: InsertMode.insertOrReplace);

  // ----------------------------------------------------------------- recurring

  Stream<List<RecurringRow>> watchRecurring() {
    final query = db.select(db.recurringRules).join([
      innerJoin(db.categories, db.categories.id.equalsExp(db.recurringRules.categoryId)),
    ])
      ..orderBy([OrderingTerm.asc(db.recurringRules.paused), OrderingTerm.asc(db.recurringRules.id)]);
    return query.watch().map((rows) => [
          for (final r in rows) RecurringRow(r.readTable(db.recurringRules), r.readTable(db.categories)),
        ]);
  }

  Future<RecurringRule?> rule(int id) =>
      (db.select(db.recurringRules)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Changes a rule for the future only: the series restarts at [nextDay];
  /// bookings already created stay as they are.
  Future<void> updateRule(
    RecurringRule rule, {
    required int categoryId,
    required int amountCents,
    required String note,
    required RepeatDraft repeat,
    required DateTime nextDay,
  }) =>
      (db.update(db.recurringRules)..where((r) => r.id.equals(rule.id))).write(RecurringRulesCompanion(
        categoryId: Value(categoryId),
        amountCents: Value(amountCents),
        note: Value(note.trim()),
        interval: Value(repeat.interval),
        dayOfMonth: Value(repeat.interval.usesDayOfMonth ? repeat.dayOfMonth : null),
        startDay: Value(dayKey(nextDay)),
        nextIndex: const Value(0),
        notBeforeDay: Value(dayKey(nextDay)),
        maxCount: Value(repeat.maxCount),
        endDay: Value(repeat.endDay == null ? null : dayKey(repeat.endDay!)),
      ));

  /// Pausing stops new bookings; resuming does not catch up on the paused time.
  Future<void> setPaused(RecurringRule rule, bool paused) =>
      (db.update(db.recurringRules)..where((r) => r.id.equals(rule.id))).write(RecurringRulesCompanion(
        paused: Value(paused),
        notBeforeDay: paused ? const Value.absent() : Value(dayKey(today())),
      ));

  /// Deletes the rule; its bookings stay (link is cleared by the foreign key).
  Future<void> deleteRule(int id) => (db.delete(db.recurringRules)..where((r) => r.id.equals(id))).go();
}

String _escapeLike(String s) => s.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

/// Next date a rule will create a booking, or null if it has ended.
DateTime? nextOccurrence(RecurringRule r) {
  final start = parseDay(r.startDay);
  final last = r.lastRunDay == null ? null : parseDay(r.lastRunDay!);
  final notBefore = r.notBeforeDay == null ? null : parseDay(r.notBeforeDay!);
  final end = r.endDay == null ? null : parseDay(r.endDay!);
  if (r.maxCount != null && r.generatedCount >= r.maxCount!) return null;
  for (var i = r.nextIndex; i < r.nextIndex + 10000; i++) {
    final d = occurrence(start: start, interval: r.interval, dayOfMonth: r.dayOfMonth, index: i);
    if (last != null && !d.isAfter(last)) continue;
    if (notBefore != null && d.isBefore(notBefore)) continue;
    if (end != null && d.isAfter(end)) return null;
    return d;
  }
  return null;
}
