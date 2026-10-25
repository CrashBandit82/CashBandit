import 'package:drift/drift.dart';

import 'db.dart';

typedef _Default = (String name, EntryKind kind, int color, String icon);

const defaultCategories = <_Default>[
  ('Lebensmittel', EntryKind.expense, 0xFFF57C00, 'cart'),
  ('Hygiene', EntryKind.expense, 0xFF00ACC1, 'soap'),
  ('Gesundheit', EntryKind.expense, 0xFFE53935, 'health'),
  ('Kleidung', EntryKind.expense, 0xFF8E24AA, 'clothes'),
  ('Miete', EntryKind.expense, 0xFF3949AB, 'home'),
  ('Tanken', EntryKind.expense, 0xFF6D4C41, 'fuel'),
  ('Versicherungen', EntryKind.expense, 0xFF546E7A, 'shield'),
  ('Diverses', EntryKind.expense, 0xFF757575, 'misc'),
  ('Urlaube', EntryKind.expense, 0xFF1E88E5, 'beach'),
  ('Geschenke', EntryKind.expense, 0xFFD81B60, 'gift'),
  ('Lohn', EntryKind.income, 0xFF2E7D32, 'work'),
  ('sonstige Einnahmen', EntryKind.income, 0xFF9E9D24, 'savings'),
];

Future<void> insertDefaultCategories(AppDatabase db) async {
  await db.batch((b) {
    for (final (i, (name, kind, color, icon)) in defaultCategories.indexed) {
      b.insert(
        db.categories,
        CategoriesCompanion.insert(name: name, kind: kind, color: color, icon: icon, sortOrder: Value(i)),
      );
    }
  });
}
