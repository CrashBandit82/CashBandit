import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/db.dart';
import '../data/recurring_runner.dart';
import '../data/repository.dart';
import '../providers.dart';
import 'booking_form.dart';
import 'widgets.dart';

String scheduleText(RecurringRule r) {
  final day = r.dayOfMonth ?? parseDay(r.startDay).day;
  return r.interval.usesDayOfMonth ? '${r.interval.label} am $day.' : r.interval.label;
}

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Wiederkehrende Buchungen')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-recurring',
        onPressed: () => openBookingForm(context, recurring: true),
        icon: const Icon(Icons.add),
        label: const Text('Neue Serie'),
      ),
      body: switch (rules) {
        AsyncData(value: final list) when list.isEmpty => const EmptyHint(
            icon: Icons.repeat,
            text: 'Noch keine wiederkehrenden Buchungen.\nBeim Anlegen einer Buchung „Wiederkehrend“ einschalten.',
          ),
        AsyncData(value: final list) => ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 96),
            children: [for (final r in list) _RuleCard(r)],
          ),
        AsyncError(:final error) => Center(child: Text('Fehler: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _RuleCard extends ConsumerWidget {
  const _RuleCard(this.row);
  final RecurringRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row.rule;
    final next = nextOccurrence(r);
    final status = r.paused
        ? 'pausiert'
        : next == null
            ? 'beendet'
            : 'nächste: ${shortDayFormat.format(next)}';
    final repo = ref.read(repoProvider);
    return Opacity(
      opacity: r.paused || next == null ? 0.6 : 1,
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          leading: CategoryAvatar.of(row.category),
          title: Text(r.note.isEmpty ? row.category.name : r.note, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${scheduleText(r)} · $status\n${r.generatedCount} Buchungen erzeugt'),
          isThreeLine: true,
          onTap: () => openRuleForm(context, ref, r.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AmountText(r.amountCents, row.category.kind),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await openRuleForm(context, ref, r.id);
                    case 'pause':
                      await repo.setPaused(r, !r.paused);
                      if (r.paused) await runDueRecurring(ref.read(dbProvider));
                    case 'delete':
                      final ok = await confirm(
                        context,
                        title: 'Vorlage löschen?',
                        message: 'Es werden keine neuen Buchungen mehr erzeugt. Bereits eingetragene Buchungen bleiben erhalten.',
                      );
                      if (ok) await repo.deleteRule(r.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  PopupMenuItem(value: 'pause', child: Text(r.paused ? 'Fortsetzen' : 'Pausieren')),
                  const PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openRuleForm(BuildContext context, WidgetRef ref, int ruleId) async {
  final rule = await ref.read(repoProvider).rule(ruleId);
  if (rule == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => RuleForm(rule: rule)));
}

/// Edits a recurring rule. Changes apply to future bookings only.
class RuleForm extends ConsumerStatefulWidget {
  const RuleForm({super.key, required this.rule});
  final RecurringRule rule;

  @override
  ConsumerState<RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends ConsumerState<RuleForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: plainCents(widget.rule.amountCents));
  late final _note = TextEditingController(text: widget.rule.note);
  late int _categoryId = widget.rule.categoryId;
  late DateTime _next = nextOccurrence(widget.rule) ?? addDays(today(), 1);
  late RepeatValue _repeat = RepeatValue.ofRule(widget.rule, _next);

  DateTime? get _lastRun => widget.rule.lastRunDay == null ? null : parseDay(widget.rule.lastRunDay!);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickNext() async {
    final first = _lastRun == null ? DateTime(2000) : addDays(_lastRun!, 1);
    final d = await showDatePicker(
      context: context,
      initialDate: _next.isBefore(first) ? first : _next,
      firstDate: first,
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (_repeat.dayOfMonth == _next.day) _repeat = _repeat.copyWith(dayOfMonth: d.day);
      _next = d;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(repoProvider).updateRule(
          widget.rule,
          categoryId: _categoryId,
          amountCents: parseCents(_amount.text)!,
          note: _note.text,
          repeat: _repeat.toDraft(),
          nextDay: _next,
        );
    await runDueRecurring(ref.read(dbProvider));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Vorlage löschen?',
      message: 'Es werden keine neuen Buchungen mehr erzeugt. Bereits eingetragene Buchungen bleiben erhalten.',
    );
    if (!ok) return;
    await ref.read(repoProvider).deleteRule(widget.rule.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vorlage bearbeiten'),
        actions: [IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Änderungen gelten nur für zukünftige Buchungen.'),
                subtitle: Text('Bereits erzeugte Buchungen bleiben unverändert.'),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Betrag', suffixText: '€'),
              validator: (v) => parseCents(v ?? '') == null ? 'Bitte einen gültigen Betrag eingeben' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
              decoration: const InputDecoration(labelText: 'Kategorie'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(children: [
                      CategoryAvatar.of(c, size: 24),
                      const SizedBox(width: 12),
                      Text('${c.name} (${c.kind.label})'),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Notiz (optional)')),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Nächste Buchung am'),
                subtitle: Text(dayFormat.format(_next)),
                onTap: _pickNext,
              ),
            ),
            const SizedBox(height: 12),
            RepeatFields(
              value: _repeat,
              onChanged: (v) => setState(() => _repeat = v),
              countHint: 'inklusive der ${widget.rule.generatedCount} bereits erzeugten',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'save-rule',
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const Text('Speichern'),
      ),
    );
  }
}
