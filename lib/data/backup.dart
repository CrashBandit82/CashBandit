import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/recurrence.dart';
import 'db.dart';

const backupFormat = 'cashbandit-backup';
const backupVersion = 1;

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _hex(int argb) => '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

int _parseHex(String s) {
  final v = int.tryParse(s.replaceFirst('#', ''), radix: 16);
  if (v == null) throw BackupException('Ungültige Farbe: $s');
  return s.length <= 7 ? 0xFF000000 | v : v;
}

/// Whole database as JSON (categories, bookings, recurring rules).
Future<String> exportJson(AppDatabase db, {DateTime? now}) async {
  final categories = await (db.select(db.categories)..orderBy([(c) => OrderingTerm(expression: c.id)])).get();
  final bookings = await (db.select(db.bookings)..orderBy([(b) => OrderingTerm(expression: b.id)])).get();
  final rules = await (db.select(db.recurringRules)..orderBy([(r) => OrderingTerm(expression: r.id)])).get();
  final data = {
    'format': backupFormat,
    'version': backupVersion,
    'schemaVersion': db.schemaVersion,
    'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'categories': [
      for (final c in categories)
        {
          'id': c.id,
          'name': c.name,
          'kind': c.kind.name,
          'color': _hex(c.color),
          'icon': c.icon,
          'sortOrder': c.sortOrder,
        },
    ],
    'bookings': [
      for (final b in bookings)
        {
          'id': b.id,
          'categoryId': b.categoryId,
          'amountCents': b.amountCents,
          'day': b.day,
          'note': b.note,
          'recurringId': b.recurringId,
          'isAuto': b.isAuto,
          'createdAt': b.createdAt.toUtc().toIso8601String(),
        },
    ],
    'recurring': [
      for (final r in rules)
        {
          'id': r.id,
          'categoryId': r.categoryId,
          'amountCents': r.amountCents,
          'note': r.note,
          'interval': r.interval.name,
          'dayOfMonth': r.dayOfMonth,
          'startDay': r.startDay,
          'nextIndex': r.nextIndex,
          'lastRunDay': r.lastRunDay,
          'notBeforeDay': r.notBeforeDay,
          'generatedCount': r.generatedCount,
          'maxCount': r.maxCount,
          'endDay': r.endDay,
          'paused': r.paused,
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Parsed and validated backup, ready to import.
class BackupContent {
  BackupContent(this.categories, this.bookings, this.rules, this.exportedAt);
  final List<Category> categories;
  final List<Booking> bookings;
  final List<RecurringRule> rules;
  final DateTime? exportedAt;
}

T _field<T>(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is T) return v;
  throw BackupException('Feld "$key" fehlt oder ist ungültig.');
}

String? _day(Map<String, dynamic> m, String key, {bool required = false}) {
  final v = m[key];
  if (v == null && !required) return null;
  if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
    final d = parseDay(v);
    if (dayKey(d) == v) return v;
  }
  throw BackupException('Ungültiges Datum in "$key": $v');
}

E _enum<E extends Enum>(List<E> values, Object? name) =>
    values.firstWhere((e) => e.name == name, orElse: () => throw BackupException('Unbekannter Wert: $name'));

int _amount(Map<String, dynamic> m) {
  final v = _field<int>(m, 'amountCents');
  if (v <= 0 || v > maxCents) throw BackupException('Ungültiger Betrag: $v');
  return v;
}

/// Parses a backup file. Throws [BackupException] with a German message.
BackupContent parseBackup(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw BackupException('Die Datei ist kein gültiges JSON.');
  }
  if (root is! Map<String, dynamic> || root['format'] != backupFormat) {
    throw BackupException('Die Datei ist keine CashBandit-Sicherung.');
  }
  final Map<String, dynamic> map = root;
  final version = map['version'];
  if (version is! int || version > backupVersion) {
    throw BackupException('Diese Sicherung stammt aus einer neueren App-Version. Bitte zuerst die App aktualisieren.');
  }
  List<Map<String, dynamic>> list(String key) {
    final v = map[key];
    if (v is! List) throw BackupException('Abschnitt "$key" fehlt.');
    return v.map((e) => e is Map<String, dynamic> ? e : throw BackupException('Ungültiger Eintrag in "$key".')).toList();
  }

  final categories = [
    for (final m in list('categories'))
      Category(
        id: _field<int>(m, 'id'),
        name: _field<String>(m, 'name'),
        kind: _enum(EntryKind.values, m['kind']),
        color: _parseHex(_field<String>(m, 'color')),
        icon: _field<String>(m, 'icon'),
        sortOrder: _field<int>(m, 'sortOrder'),
      ),
  ];
  final categoryIds = categories.map((c) => c.id).toSet();
  if (categoryIds.length != categories.length) throw BackupException('Doppelte Kategorie-IDs.');

  final rules = [
    for (final m in list('recurring'))
      RecurringRule(
        id: _field<int>(m, 'id'),
        categoryId: _field<int>(m, 'categoryId'),
        amountCents: _amount(m),
        note: _field<String>(m, 'note'),
        interval: _enum(RepeatInterval.values, m['interval']),
        dayOfMonth: m['dayOfMonth'] as int?,
        startDay: _day(m, 'startDay', required: true)!,
        nextIndex: _field<int>(m, 'nextIndex'),
        lastRunDay: _day(m, 'lastRunDay'),
        notBeforeDay: _day(m, 'notBeforeDay'),
        generatedCount: _field<int>(m, 'generatedCount'),
        maxCount: m['maxCount'] as int?,
        endDay: _day(m, 'endDay'),
        paused: _field<bool>(m, 'paused'),
      ),
  ];
  final ruleIds = rules.map((r) => r.id).toSet();

  final bookings = [
    for (final m in list('bookings'))
      Booking(
        id: _field<int>(m, 'id'),
        categoryId: _field<int>(m, 'categoryId'),
        amountCents: _amount(m),
        day: _day(m, 'day', required: true)!,
        note: _field<String>(m, 'note'),
        recurringId: m['recurringId'] as int?,
        isAuto: _field<bool>(m, 'isAuto'),
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      ),
  ];

  for (final b in bookings) {
    if (!categoryIds.contains(b.categoryId)) throw BackupException('Buchung ${b.id} verweist auf eine fehlende Kategorie.');
    if (b.recurringId != null && !ruleIds.contains(b.recurringId)) {
      throw BackupException('Buchung ${b.id} verweist auf eine fehlende Vorlage.');
    }
  }
  for (final r in rules) {
    if (!categoryIds.contains(r.categoryId)) throw BackupException('Vorlage ${r.id} verweist auf eine fehlende Kategorie.');
  }
  return BackupContent(categories, bookings, rules, DateTime.tryParse(map['exportedAt'] as String? ?? ''));
}

/// Replaces all data with [content] in one transaction (all or nothing).
Future<void> importBackup(AppDatabase db, BackupContent content) => db.transaction(() async {
      await db.delete(db.bookings).go();
      await db.delete(db.recurringRules).go();
      await db.delete(db.categories).go();
      await db.batch((b) {
        b.insertAll(db.categories, content.categories);
        b.insertAll(db.recurringRules, content.rules);
        b.insertAll(db.bookings, content.bookings);
      });
    });

String _csvField(String s) => RegExp(r'[;"\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// Bookings as CSV for spreadsheets (semicolon, decimal comma, UTF-8 BOM).
Future<String> exportCsv(AppDatabase db) async {
  final rows = await (db.select(db.bookings).join([
    innerJoin(db.categories, db.categories.id.equalsExp(db.bookings.categoryId)),
  ])
        ..orderBy([OrderingTerm.asc(db.bookings.day), OrderingTerm.asc(db.bookings.id)]))
      .get();
  final out = StringBuffer('\uFEFFDatum;Typ;Kategorie;Betrag;Notiz;Wiederkehrend\r\n');
  for (final r in rows) {
    final b = r.readTable(db.bookings);
    final c = r.readTable(db.categories);
    final d = parseDay(b.day);
    final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final signed = c.kind == EntryKind.income ? b.amountCents : -b.amountCents;
    out.write([
      date,
      c.kind.label,
      _csvField(c.name),
      plainCents(signed),
      _csvField(b.note),
      b.isAuto ? 'ja' : 'nein',
    ].join(';'));
    out.write('\r\n');
  }
  return out.toString();
}
