import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/recurrence.dart';
import 'default_categories.dart';

part 'db.g.dart';

enum EntryKind {
  expense('Ausgabe', 'Ausgaben'),
  income('Einnahme', 'Einnahmen');

  const EntryKind(this.label, this.plural);
  final String label;
  final String plural;
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<EntryKind>()();

  /// ARGB
  IntColumn get color => integer()();

  /// Key into `categoryIcons` (lib/core/icons.dart).
  TextColumn get icon => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Income or expense entry. Its type is the type of its category.
class Bookings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get amountCents => integer()();

  /// Calendar day "YYYY-MM-DD".
  TextColumn get day => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get recurringId =>
      integer().nullable().references(RecurringRules, #id, onDelete: KeyAction.setNull)();

  /// Created by a recurring rule (shown with a repeat icon).
  BoolColumn get isAuto => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Template for recurring bookings, see RecurringRunner.
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get amountCents => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get interval => textEnum<RepeatInterval>()();

  /// Month-based intervals only; null = day of [startDay].
  IntColumn get dayOfMonth => integer().nullable()();

  /// Series origin; occurrence n is computed from it (core/recurrence.dart).
  TextColumn get startDay => text()();

  /// Next occurrence index to look at.
  IntColumn get nextIndex => integer().withDefault(const Constant(0))();

  /// Date of the last booking of this series – occurrences on or before it
  /// are never created again (no duplicates).
  TextColumn get lastRunDay => text().nullable()();

  /// Occurrences before this day are skipped (set when a paused rule resumes).
  TextColumn get notBeforeDay => text().nullable()();
  IntColumn get generatedCount => integer().withDefault(const Constant(0))();
  IntColumn get maxCount => integer().nullable()();
  TextColumn get endDay => text().nullable()();
  BoolColumn get paused => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [Categories, Bookings, RecurringRules])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'cashbandit'));

  /// Bump on every schema change and add a step in [migration].
  /// Schema snapshots: drift_schemas/ (`dart run drift_dev make-migrations`).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await insertDefaultCategories(this);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
