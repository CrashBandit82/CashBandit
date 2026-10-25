/// Amounts are integer cents everywhere; these helpers are the only place
/// that converts between cents and text (de_AT style: 1.234,56 €).
library;

/// 123456 -> "1.234,56 €" (sign only for negative values).
String formatCents(int cents, {bool withSymbol = true, bool signed = false}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final euros = (abs ~/ 100).toString();
  final rest = (abs % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < euros.length; i++) {
    if (i > 0 && (euros.length - i) % 3 == 0) grouped.write('.');
    grouped.write(euros[i]);
  }
  final sign = negative ? '−' : (signed && cents > 0 ? '+' : '');
  return '$sign$grouped,$rest${withSymbol ? ' €' : ''}';
}

/// Plain number for CSV / input fields: 123456 -> "1234,56".
String plainCents(int cents) {
  final abs = cents.abs();
  return '${cents < 0 ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
}

/// Largest accepted amount: 999.999.999,99 €.
const maxCents = 99999999999;

/// Parses user input into cents, or null if it is not a valid positive amount.
///
/// Accepts "1.234,56", "1234,56", "12,5", "12" and also "12.50" (a dot
/// followed by one or two digits is a decimal point when there is no comma).
int? parseCents(String input) {
  var s = input.replaceAll(RegExp(r'[\s€ ]'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    if (','.allMatches(s).length > 1) return null;
    s = s.replaceAll('.', '').replaceFirst(',', '.');
  } else if (RegExp(r'\.\d{1,2}$').hasMatch(s) && '.'.allMatches(s).length == 1) {
    // "12.5" / "12.50" -> decimal point
  } else {
    s = s.replaceAll('.', '');
  }
  final m = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(s);
  if (m == null) return null;
  final euros = int.tryParse(m.group(1)!);
  if (euros == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = euros * 100 + int.parse(frac);
  if (cents <= 0 || cents > maxCents) return null;
  return cents;
}
