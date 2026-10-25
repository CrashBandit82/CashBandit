/// Calendar days are stored as ISO text ("2026-10-25"): no time zone, sorts
/// correctly as text, survives backups unchanged.
library;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// ISO 8601 week number.
int isoWeek(DateTime d) {
  final thursday = addDays(d, 4 - d.weekday);
  return (_utcDays(thursday, DateTime(thursday.year, 1, 1)) ~/ 7) + 1;
}

/// Whole days from [b] to [a]; UTC so a DST change in between can't drop a day.
int _utcDays(DateTime a, DateTime b) =>
    DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

/// Inclusive day range.
class DayRange {
  const DayRange(this.from, this.to);
  final DateTime from;
  final DateTime to;

  String get fromKey => dayKey(from);
  String get toKey => dayKey(to);

  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  int get dayCount => _utcDays(to, from) + 1;

  @override
  bool operator ==(Object other) => other is DayRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

enum PeriodMode { week, month }

/// The week or month containing [anchor].
DayRange periodRange(PeriodMode mode, DateTime anchor) => switch (mode) {
      PeriodMode.week => DayRange(startOfWeek(anchor), addDays(startOfWeek(anchor), 6)),
      PeriodMode.month => DayRange(
          DateTime(anchor.year, anchor.month, 1),
          DateTime(anchor.year, anchor.month, daysInMonth(anchor.year, anchor.month)),
        ),
    };

/// Anchor of the previous (-1) or next (+1) period.
DateTime shiftPeriod(PeriodMode mode, DateTime anchor, int delta) => switch (mode) {
      PeriodMode.week => addDays(startOfWeek(anchor), 7 * delta),
      PeriodMode.month => DateTime(anchor.year, anchor.month + delta, 1),
    };
