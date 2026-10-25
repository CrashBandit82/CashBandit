import 'package:cashbandit/core/dates.dart';
import 'package:cashbandit/core/money.dart';
import 'package:cashbandit/core/recurrence.dart';
import 'package:cashbandit/services/pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('formats de_AT style with dot grouping', () {
      expect(formatCents(123456), '1.234,56 €');
      expect(formatCents(5), '0,05 €');
      expect(formatCents(100000000), '1.000.000,00 €');
      expect(formatCents(-2550), '−25,50 €');
      expect(formatCents(2550, signed: true), '+25,50 €');
      expect(formatCents(99, withSymbol: false), '0,99');
    });

    test('parses typical inputs', () {
      expect(parseCents('1.234,56'), 123456);
      expect(parseCents('1234,56'), 123456);
      expect(parseCents('12,5'), 1250);
      expect(parseCents('12'), 1200);
      expect(parseCents(' 12,50 € '), 1250);
      expect(parseCents('12.50'), 1250);
      expect(parseCents('12.5'), 1250);
      expect(parseCents('1.234'), 123400);
      expect(parseCents('1.234.567'), 123456700);
    });

    test('rejects invalid amounts', () {
      for (final s in ['', '0', '0,00', 'abc', '1,2,3', '12,345', '-5', '1e5', '9999999999,00']) {
        expect(parseCents(s), isNull, reason: s);
      }
    });

    test('plain export format', () {
      expect(plainCents(123456), '1234,56');
      expect(plainCents(-5), '-0,05');
    });
  });

  group('dates', () {
    test('day keys round-trip', () {
      expect(dayKey(DateTime(2026, 3, 7)), '2026-03-07');
      expect(parseDay('2026-03-07'), DateTime(2026, 3, 7));
    });

    test('periods', () {
      final w = periodRange(PeriodMode.week, DateTime(2026, 10, 25)); // Sunday
      expect(w.from, DateTime(2026, 10, 19));
      expect(w.to, DateTime(2026, 10, 25));
      final m = periodRange(PeriodMode.month, DateTime(2028, 2, 10));
      expect(m.to, DateTime(2028, 2, 29));
      expect(shiftPeriod(PeriodMode.month, DateTime(2026, 1, 31), -1), DateTime(2025, 12, 1));
      expect(isoWeek(DateTime(2026, 1, 1)), 1);
      expect(isoWeek(DateTime(2027, 1, 1)), 53);
    });
  });

  group('recurrence', () {
    DateTime occ(DateTime start, RepeatInterval i, int n, {int? day}) =>
        occurrence(start: start, interval: i, dayOfMonth: day, index: n);

    test('monthly on the 31st uses the last day of shorter months', () {
      final start = DateTime(2026, 1, 31);
      expect([for (var n = 0; n < 5; n++) occ(start, RepeatInterval.monthly, n)], [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
      ]);
      expect(occ(DateTime(2028, 1, 31), RepeatInterval.monthly, 1), DateTime(2028, 2, 29));
    });

    test('day of month overrides the start day', () {
      expect(occ(DateTime(2026, 10, 25), RepeatInterval.monthly, 1, day: 1), DateTime(2026, 11, 1));
    });

    test('weekly, quarterly, half-yearly, yearly', () {
      final start = DateTime(2026, 11, 30);
      expect(occ(start, RepeatInterval.weekly, 1), DateTime(2026, 12, 7));
      expect(occ(start, RepeatInterval.quarterly, 1), DateTime(2027, 2, 28));
      expect(occ(start, RepeatInterval.halfYearly, 1), DateTime(2027, 5, 30));
      expect(occ(DateTime(2028, 2, 29), RepeatInterval.yearly, 1), DateTime(2029, 2, 28));
      expect(occ(DateTime(2028, 2, 29), RepeatInterval.yearly, 4), DateTime(2032, 2, 29));
    });

    test('weekly series across the DST change keeps whole days', () {
      expect(occ(DateTime(2026, 3, 23), RepeatInterval.weekly, 1), DateTime(2026, 3, 30));
    });
  });

  group('pin', () {
    test('hash verifies only the right PIN', () {
      final h = hashPin('4711');
      expect(h.startsWith('pbkdf2\$'), isTrue);
      expect(h.contains('4711'), isFalse);
      expect(verifyPin('4711', h), isTrue);
      expect(verifyPin('4712', h), isFalse);
      expect(verifyPin('4711', 'garbage'), isFalse);
    });

    test('salt makes hashes differ', () => expect(hashPin('1234'), isNot(hashPin('1234'))));

    test('pin rules', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
    });
  });
}
