import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/db.dart';
import '../data/repository.dart';
import '../providers.dart';
import 'booking_form.dart';
import 'widgets.dart';

/// Chronological booking list with filters. [initial] pre-sets the filter
/// (used when opening a category from the dashboard).
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key, this.initial = const BookingQuery(), this.title});
  final BookingQuery initial;
  final String? title;

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  late BookingQuery _query = widget.initial;
  final _search = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _query.range == null ? null : DateTimeRange(start: _query.range!.from, end: _query.range!.to),
    );
    if (r != null) setState(() => _query = _query.copyWith(range: () => DayRange(dateOnly(r.start), dateOnly(r.end))));
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(leading: const Icon(Icons.clear_all), title: const Text('Alle Kategorien'), onTap: () => Navigator.pop(context, -1)),
          for (final c in categories)
            ListTile(
              leading: CategoryAvatar.of(c, size: 32),
              title: Text(c.name),
              subtitle: Text(c.kind.label),
              onTap: () => Navigator.pop(context, c.id),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _query = _query.copyWith(categoryId: () => picked == -1 ? null : picked));
  }

  void _delete(BookingRow row) {
    final repo = ref.read(repoProvider);
    repo.deleteBooking(row.booking.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Buchung gelöscht'),
        persist: false,
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => repo.restoreBooking(row.booking)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final bookings = ref.watch(bookingsProvider(_query));
    final category = categories.where((c) => c.id == _query.categoryId).firstOrNull;
    final standalone = widget.title != null;

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'In Notizen suchen', border: InputBorder.none, filled: false),
                onChanged: (v) => setState(() => _query = _query.copyWith(search: v)),
              )
            : Text(widget.title ?? 'Buchungen'),
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Suche schließen' : 'Suchen',
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _search.clear();
                _query = _query.copyWith(search: '');
              }
            }),
          ),
        ],
      ),
      floatingActionButton: standalone
          ? FloatingActionButton(heroTag: 'add2', onPressed: () => openBookingForm(context), child: const Icon(Icons.add))
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                FilterChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(_query.range == null
                      ? 'Zeitraum'
                      : '${shortDayFormat.format(_query.range!.from)} – ${shortDayFormat.format(_query.range!.to)}'),
                  selected: _query.range != null,
                  onSelected: (_) => _pickRange(),
                  onDeleted: _query.range == null ? null : () => setState(() => _query = _query.copyWith(range: () => null)),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: category == null ? const Icon(Icons.category_outlined, size: 18) : CategoryAvatar.of(category, size: 20),
                  label: Text(category?.name ?? 'Kategorie'),
                  selected: category != null,
                  onSelected: (_) => _pickCategory(categories),
                  onDeleted: category == null ? null : () => setState(() => _query = _query.copyWith(categoryId: () => null)),
                ),
                const SizedBox(width: 8),
                for (final k in EntryKind.values) ...[
                  FilterChip(
                    label: Text(k.plural),
                    selected: _query.kind == k,
                    onSelected: (on) => setState(() => _query = _query.copyWith(kind: () => on ? k : null)),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (bookings) {
              AsyncData(value: final rows) when rows.isEmpty => EmptyHint(
                  icon: Icons.receipt_long_outlined,
                  text: _query.isFiltered ? 'Keine Buchungen für diesen Filter.' : 'Noch keine Buchungen.\nTippe auf +, um zu beginnen.',
                ),
              AsyncData(value: final rows) => _GroupedList(rows: rows, onDelete: _delete),
              AsyncError(:final error) => Center(child: Text('Fehler: $error')),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.rows, required this.onDelete});
  final List<BookingRow> rows;
  final void Function(BookingRow) onDelete;

  @override
  Widget build(BuildContext context) {
    // flatten into day headers + rows
    final items = <Object>[];
    String? day;
    for (final r in rows) {
      if (r.booking.day != day) {
        day = r.booking.day;
        items.add(day);
      }
      items.add(r);
    }
    final total = rows.fold<int>(0, (s, r) => s + r.signedCents);
    final daySums = <String, int>{};
    for (final r in rows) {
      daySums.update(r.booking.day, (v) => v + r.signedCents, ifAbsent: () => r.signedCents);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              '${rows.length} Buchungen · Saldo ${formatCents(total, signed: true)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final item = items[i - 1];
        if (item is String) {
          return SectionTitle(
            dayFormat.format(parseDay(item)),
            trailing: Text(formatCents(daySums[item]!, signed: true), style: Theme.of(context).textTheme.labelMedium),
          );
        }
        final r = item as BookingRow;
        return Dismissible(
          key: ValueKey('b${r.booking.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 28),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          onDismissed: (_) => onDelete(r),
          child: BookingTile(r),
        );
      },
    );
  }
}

class BookingTile extends StatelessWidget {
  const BookingTile(this.row, {super.key});
  final BookingRow row;

  @override
  Widget build(BuildContext context) {
    final b = row.booking;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        leading: CategoryAvatar.of(row.category),
        title: Row(
          children: [
            Flexible(child: Text(row.category.name, overflow: TextOverflow.ellipsis)),
            if (b.isAuto) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'automatisch eingetragen',
                child: Icon(Icons.repeat, size: 16, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ],
        ),
        subtitle: b.note.isEmpty ? null : Text(b.note, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: AmountText(b.amountCents, row.kind),
        onTap: () => openBookingForm(context, booking: b),
      ),
    );
  }
}
