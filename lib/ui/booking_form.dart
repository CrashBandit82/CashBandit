import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/recurrence.dart';
import '../data/db.dart';
import '../data/recurring_runner.dart';
import '../data/repository.dart';
import '../providers.dart';
import 'category_form.dart';
import 'recurring_screen.dart';
import 'widgets.dart';

Future<void> openBookingForm(BuildContext context, {Booking? booking, bool recurring = false}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => BookingForm(booking: booking, startRecurring: recurring),
    ));

class BookingForm extends ConsumerStatefulWidget {
  const BookingForm({super.key, this.booking, this.startRecurring = false});
  final Booking? booking;
  final bool startRecurring;

  @override
  ConsumerState<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<BookingForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.booking == null ? '' : plainCents(widget.booking!.amountCents),
  );
  late final _note = TextEditingController(text: widget.booking?.note ?? '');
  late DateTime _day = widget.booking == null ? today() : parseDay(widget.booking!.day);
  EntryKind _kind = EntryKind.expense;
  int? _categoryId;
  bool _kindFromCategory = false;
  late bool _repeat = widget.startRecurring;
  late RepeatValue _repeatValue = RepeatValue.initial(_day);
  bool _saving = false;

  bool get _editing => widget.booking != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.booking?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (_repeatValue.dayOfMonth == _day.day) _repeatValue = _repeatValue.copyWith(dayOfMonth: d.day);
      _day = d;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      showMessage(context, 'Bitte eine Kategorie wählen.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    await repo.saveBooking(
      BookingDraft(categoryId: _categoryId!, amountCents: parseCents(_amount.text)!, day: _day, note: _note.text),
      id: widget.booking?.id,
      repeat: _repeat ? _repeatValue.toDraft() : null,
    );
    // a series that starts in the past gets its missed bookings right away
    if (_repeat) await runDueRecurring(ref.read(dbProvider));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Buchung löschen?', message: 'Die Buchung wird endgültig gelöscht.');
    if (!ok) return;
    await ref.read(repoProvider).deleteBooking(widget.booking!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addCategory() async {
    final id = await openCategoryForm(context, kind: _kind);
    if (id != null) setState(() => _categoryId = id);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    if (!_kindFromCategory && _categoryId != null) {
      final c = categories.where((c) => c.id == _categoryId).firstOrNull;
      if (c != null) {
        _kind = c.kind;
        _kindFromCategory = true;
      }
    }
    final visible = categories.where((c) => c.kind == _kind).toList();
    final linkedRule = widget.booking?.recurringId;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Buchung bearbeiten' : 'Neue Buchung'),
        actions: [
          if (_editing) IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SegmentedButton<EntryKind>(
              segments: const [
                ButtonSegment(value: EntryKind.expense, label: Text('Ausgabe'), icon: Icon(Icons.remove_circle_outline)),
                ButtonSegment(value: EntryKind.income, label: Text('Einnahme'), icon: Icon(Icons.add_circle_outline)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                if (!categories.any((c) => c.id == _categoryId && c.kind == _kind)) _categoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: !_editing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Betrag', suffixText: '€', hintText: '0,00'),
              validator: (v) => parseCents(v ?? '') == null ? 'Bitte einen gültigen Betrag eingeben' : null,
            ),
            const SizedBox(height: 16),
            Text('Kategorie', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in visible)
                  ChoiceChip(
                    avatar: CategoryAvatar.of(c, size: 24),
                    label: Text(c.name),
                    selected: c.id == _categoryId,
                    selectedColor: Color(c.color).withValues(alpha: 0.25),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
                ActionChip(avatar: const Icon(Icons.add), label: const Text('Neu'), onPressed: _addCategory),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Datum'),
                subtitle: Text(dayFormat.format(_day)),
                onTap: _pickDay,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notiz (optional)'),
            ),
            const SizedBox(height: 16),
            if (linkedRule != null)
              Card(
                margin: EdgeInsets.zero,
                color: scheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.repeat),
                  title: const Text('Teil einer wiederkehrenden Buchung'),
                  subtitle: const Text('Änderungen hier betreffen nur diese Buchung.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openRuleForm(context, ref, linkedRule),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.repeat),
                      title: const Text('Wiederkehrend'),
                      subtitle: Text(_repeat ? 'Diese Buchung ist die erste der Serie' : 'Automatisch wiederholen'),
                      value: _repeat,
                      onChanged: (v) => setState(() => _repeat = v),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _repeat
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: RepeatFields(value: _repeatValue, onChanged: (v) => setState(() => _repeatValue = v)),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(onPressed: _saving ? null : _save),
    );
  }
}

enum RepeatEnd { never, date, count }

/// Editable schedule of a recurring booking.
class RepeatValue {
  const RepeatValue({required this.interval, required this.dayOfMonth, this.end = RepeatEnd.never, this.endDay, this.count = 12});

  factory RepeatValue.initial(DateTime start) =>
      RepeatValue(interval: RepeatInterval.monthly, dayOfMonth: start.day, endDay: DateTime(start.year + 1, start.month, start.day));

  factory RepeatValue.ofRule(RecurringRule r, DateTime next) => RepeatValue(
        interval: r.interval,
        dayOfMonth: r.dayOfMonth ?? next.day,
        end: r.endDay != null ? RepeatEnd.date : (r.maxCount != null ? RepeatEnd.count : RepeatEnd.never),
        endDay: r.endDay == null ? DateTime(next.year + 1, next.month, next.day) : parseDay(r.endDay!),
        count: r.maxCount ?? 12,
      );

  final RepeatInterval interval;
  final int dayOfMonth;
  final RepeatEnd end;
  final DateTime? endDay;

  /// Total number of bookings in the series (including those already made).
  final int count;

  RepeatValue copyWith({RepeatInterval? interval, int? dayOfMonth, RepeatEnd? end, DateTime? endDay, int? count}) => RepeatValue(
        interval: interval ?? this.interval,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        end: end ?? this.end,
        endDay: endDay ?? this.endDay,
        count: count ?? this.count,
      );

  RepeatDraft toDraft() => RepeatDraft(
        interval: interval,
        dayOfMonth: dayOfMonth,
        endDay: end == RepeatEnd.date ? endDay : null,
        maxCount: end == RepeatEnd.count ? count : null,
      );
}

class RepeatFields extends StatelessWidget {
  const RepeatFields({super.key, required this.value, required this.onChanged, this.countHint});
  final RepeatValue value;
  final ValueChanged<RepeatValue> onChanged;
  final String? countHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<RepeatInterval>(
          initialValue: value.interval,
          decoration: const InputDecoration(labelText: 'Intervall'),
          items: [for (final i in RepeatInterval.values) DropdownMenuItem(value: i, child: Text(i.label))],
          onChanged: (i) => onChanged(value.copyWith(interval: i)),
        ),
        if (value.interval.usesDayOfMonth) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: value.dayOfMonth,
            decoration: const InputDecoration(
              labelText: 'Tag im Monat',
              helperText: 'In kürzeren Monaten wird der letzte Tag genommen.',
            ),
            items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d.'))],
            onChanged: (d) => onChanged(value.copyWith(dayOfMonth: d)),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<RepeatEnd>(
          initialValue: value.end,
          decoration: const InputDecoration(labelText: 'Ende'),
          items: const [
            DropdownMenuItem(value: RepeatEnd.never, child: Text('unbegrenzt')),
            DropdownMenuItem(value: RepeatEnd.date, child: Text('bis Datum')),
            DropdownMenuItem(value: RepeatEnd.count, child: Text('Anzahl Wiederholungen')),
          ],
          onChanged: (e) => onChanged(value.copyWith(end: e)),
        ),
        if (value.end == RepeatEnd.date) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_busy),
            label: Text('Letzte Buchung spätestens am ${shortDayFormat.format(value.endDay!)}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: value.endDay!,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) onChanged(value.copyWith(endDay: d));
            },
          ),
        ],
        if (value.end == RepeatEnd.count) ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: '${value.count}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Anzahl Buchungen insgesamt',
              helperText: countHint ?? 'inklusive dieser ersten Buchung',
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 1 || n > 9999 ? 'Zahl von 1 bis 9999' : null;
            },
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= 1 && n <= 9999) onChanged(value.copyWith(count: n));
            },
          ),
        ],
      ],
    );
  }
}
