import 'dates.dart';

enum RepeatInterval {
  weekly('wöchentlich', 0),
  monthly('monatlich', 1),
  quarterly('vierteljährlich', 3),
  halfYearly('halbjährlich', 6),
  yearly('jährlich', 12);

  const RepeatInterval(this.label, this.months);
  final String label;

  /// Step in months; 0 = weekly.
  final int months;

  bool get usesDayOfMonth => months > 0;
}

/// Date of occurrence [index] of a series starting at [start].
///
/// Month-based series use [dayOfMonth] (default: the start day); in shorter
/// months the last day of the month is used (31 -> 30 / 28 / 29). Each date
/// is computed from the start, so a short month never shifts later ones.
DateTime occurrence({
  required DateTime start,
  required RepeatInterval interval,
  int? dayOfMonth,
  required int index,
}) {
  if (interval == RepeatInterval.weekly) return addDays(start, 7 * index);
  final total = start.month - 1 + index * interval.months;
  final year = start.year + total ~/ 12;
  final month = total % 12 + 1;
  final day = dayOfMonth ?? start.day;
  final last = daysInMonth(year, month);
  return DateTime(year, month, day > last ? last : day);
}
