import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../providers.dart';
import 'category_form.dart';
import 'widgets.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Kategorien'),
            bottom: const TabBar(tabs: [Tab(text: 'Ausgaben'), Tab(text: 'Einnahmen')]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'add-category',
            onPressed: () => openCategoryForm(
              context,
              kind: DefaultTabController.of(context).index == 0 ? EntryKind.expense : EntryKind.income,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Kategorie'),
          ),
          body: TabBarView(
            children: [
              for (final kind in EntryKind.values) _CategoryList(categories.where((c) => c.kind == kind).toList()),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList(this.items);
  final List<Category> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const EmptyHint(icon: Icons.category_outlined, text: 'Keine Kategorien');
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: items.length,
      onReorderItem: (from, to) {
        final ids = items.map((c) => c.id).toList();
        ids.insert(to, ids.removeAt(from));
        ref.read(repoProvider).reorderCategories(ids);
      },
      itemBuilder: (context, i) {
        final c = items[i];
        return Card(
          key: ValueKey(c.id),
          child: ListTile(
            leading: CategoryAvatar.of(c),
            title: Text(c.name),
            onTap: () => openCategoryForm(context, category: c),
            trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
          ),
        );
      },
    );
  }
}
