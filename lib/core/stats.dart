import '../data/db.dart';
import '../data/repository.dart';
import 'dates.dart';

class Totals {
  const Totals(this.income, this.expense);
  final int income;
  final int expense;
  int get balance => income - expense;

  static Totals of(Iterable<BookingRow> rows) {
    var i = 0, e = 0;
    for (final r in rows) {
      if (r.kind == EntryKind.income) {
        i += r.booking.amountCents;
      } else {
        e += r.booking.amountCents;
      }
    }
    return Totals(i, e);
  }
}

/// One bar of the stacked expense chart.
class Bucket {
  Bucket(this.range, this.label);
  final DayRange range;
  final String label;

  /// Expense cents per category id.
  final Map<int, int> byCategory = {};
  int get total => byCategory.values.fold(0, (a, b) => a + b);
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// One bucket per day of [range] (week: Mo–So, month: 1–31).
List<Bucket> dayBuckets(DayRange range, {required bool weekdayLabels}) => [
      for (var d = range.from; !d.isAfter(range.to); d = addDays(d, 1))
        Bucket(DayRange(d, d), weekdayLabels ? _weekdays[d.weekday - 1] : '${d.day}'),
    ];

/// Calendar weeks (Mo–So) of a month, clipped to the month.
List<Bucket> weekBuckets(DayRange month) {
  final out = <Bucket>[];
  var start = month.from;
  while (!start.isAfter(month.to)) {
    var end = addDays(startOfWeek(start), 6);
    if (end.isAfter(month.to)) end = month.to;
    out.add(Bucket(DayRange(start, end), 'KW ${isoWeek(start)}'));
    start = addDays(end, 1);
  }
  return out;
}

/// Sums expenses of [rows] into [buckets] (stacked by category).
List<Bucket> fillExpenses(List<Bucket> buckets, Iterable<BookingRow> rows) {
  for (final r in rows) {
    if (r.kind != EntryKind.expense) continue;
    final d = parseDay(r.booking.day);
    for (final b in buckets) {
      if (b.range.contains(d)) {
        b.byCategory.update(r.category.id, (v) => v + r.booking.amountCents, ifAbsent: () => r.booking.amountCents);
        break;
      }
    }
  }
  return buckets;
}

class CategoryShare {
  const CategoryShare(this.category, this.cents, this.share);
  final Category category;
  final int cents;

  /// 0..1 of the total of its kind.
  final double share;
}

/// Sum per category of one kind, largest first.
List<CategoryShare> breakdown(Iterable<BookingRow> rows, EntryKind kind) {
  final sums = <int, int>{};
  final cats = <int, Category>{};
  for (final r in rows) {
    if (r.kind != kind) continue;
    sums.update(r.category.id, (v) => v + r.booking.amountCents, ifAbsent: () => r.booking.amountCents);
    cats[r.category.id] = r.category;
  }
  final total = sums.values.fold(0, (a, b) => a + b);
  final list = [for (final e in sums.entries) CategoryShare(cats[e.key]!, e.value, total == 0 ? 0 : e.value / total)];
  list.sort((a, b) => b.cents.compareTo(a.cents));
  return list;
}

class MonthTotals {
  const MonthTotals(this.month, this.totals);
  final DateTime month;
  final Totals totals;
}

/// The [count] months ending with the month of [last].
DayRange monthsRange(DateTime last, int count) => DayRange(
      DateTime(last.year, last.month - count + 1, 1),
      DateTime(last.year, last.month, daysInMonth(last.year, last.month)),
    );

List<MonthTotals> monthlyTotals(Iterable<BookingRow> rows, DateTime last, int count) {
  final income = List.filled(count, 0);
  final expense = List.filled(count, 0);
  for (final r in rows) {
    final d = parseDay(r.booking.day);
    final i = (d.year - last.year) * 12 + d.month - last.month + count - 1;
    if (i < 0 || i >= count) continue;
    if (r.kind == EntryKind.income) {
      income[i] += r.booking.amountCents;
    } else {
      expense[i] += r.booking.amountCents;
    }
  }
  return [
    for (var i = 0; i < count; i++) MonthTotals(DateTime(last.year, last.month - count + 1 + i, 1), Totals(income[i], expense[i])),
  ];
}
