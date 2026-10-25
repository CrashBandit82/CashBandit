import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/icons.dart';
import '../data/db.dart';
import '../providers.dart';
import 'widgets.dart';

/// Returns the id of the created / edited category, or null.
Future<int?> openCategoryForm(BuildContext context, {Category? category, EntryKind kind = EntryKind.expense}) =>
    Navigator.of(context).push(MaterialPageRoute<int>(
      fullscreenDialog: true,
      builder: (_) => CategoryForm(category: category, kind: kind),
    ));

const _palette = <int>[
  0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF5E35B1, 0xFF3949AB, 0xFF1E88E5, //
  0xFF039BE5, 0xFF00ACC1, 0xFF00897B, 0xFF2E7D32, 0xFF7CB342, 0xFF9E9D24,
  0xFFFDD835, 0xFFFFB300, 0xFFF57C00, 0xFFF4511E, 0xFF6D4C41, 0xFF757575,
  0xFF546E7A, 0xFF263238,
];

class CategoryForm extends ConsumerStatefulWidget {
  const CategoryForm({super.key, this.category, required this.kind});
  final Category? category;
  final EntryKind kind;

  @override
  ConsumerState<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late EntryKind _kind = widget.category?.kind ?? widget.kind;
  late Color _color = Color(widget.category?.color ?? _palette[5]);
  late String _icon = widget.category?.icon ?? 'misc';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(repoProvider);
    final c = widget.category;
    final name = _name.text.trim();
    if (c == null) {
      final id = await repo.addCategory(name: name, kind: _kind, color: _color.toARGB32(), icon: _icon);
      if (mounted) Navigator.pop(context, id);
      return;
    }
    if (_kind != c.kind) {
      final used = await repo.usageCount(c.id);
      if (used > 0 && mounted) {
        final ok = await confirm(
          context,
          title: 'Typ ändern?',
          message: '$used Buchungen/Vorlagen dieser Kategorie werden damit zu ${_kind.plural}.',
          confirmLabel: 'Ändern',
          destructive: false,
        );
        if (!ok) return;
      }
    }
    await repo.updateCategory(c.copyWith(name: name, kind: _kind, color: _color.toARGB32(), icon: _icon));
    if (mounted) Navigator.pop(context, c.id);
  }

  Future<void> _delete() async {
    final c = widget.category!;
    final repo = ref.read(repoProvider);
    final used = await repo.usageCount(c.id);
    if (!mounted) return;
    if (used == 0) {
      final ok = await confirm(context, title: '„${c.name}“ löschen?', message: 'Die Kategorie wird gelöscht.');
      if (!ok) return;
      await repo.deleteCategory(c.id);
      if (mounted) Navigator.pop(context);
      return;
    }
    final others = (ref.read(categoriesProvider).value ?? const <Category>[])
        .where((o) => o.id != c.id && o.kind == c.kind)
        .toList();
    if (others.isEmpty) {
      showMessage(context, 'Zuerst eine weitere Kategorie für ${c.kind.plural} anlegen – die Buchungen brauchen ein neues Ziel.');
      return;
    }
    final target = await showDialog<Category>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('„${c.name}“ löschen'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('$used Buchungen/Vorlagen hängen an dieser Kategorie. Wohin sollen sie verschoben werden?'),
          ),
          for (final o in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Row(children: [CategoryAvatar.of(o, size: 28), const SizedBox(width: 12), Text(o.name)]),
            ),
        ],
      ),
    );
    if (target == null) return;
    await repo.deleteCategory(c.id, replacementId: target.id);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _customColor() async {
    final hsv = HSVColor.fromColor(_color);
    final picked = await showDialog<Color>(context: context, builder: (_) => _HsvDialog(initial: hsv));
    if (picked != null) setState(() => _color = picked);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.category != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Kategorie bearbeiten' : 'Neue Kategorie'),
        actions: [
          if (editing) IconButton(tooltip: 'Löschen', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: CategoryAvatar(key: ValueKey('$_icon${_color.toARGB32()}'), color: _color, icon: _icon, size: 72),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte einen Namen eingeben' : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<EntryKind>(
              segments: const [
                ButtonSegment(value: EntryKind.expense, label: Text('Ausgabe')),
                ButtonSegment(value: EntryKind.income, label: Text('Einnahme')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SectionTitle('Farbe'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final argb in _palette)
                  _ColorDot(
                    color: Color(argb),
                    selected: _color.toARGB32() == argb,
                    onTap: () => setState(() => _color = Color(argb)),
                  ),
                Tooltip(
                  message: 'Eigene Farbe',
                  child: InkResponse(
                    onTap: _customColor,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [
                          Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red, //
                        ]),
                      ),
                      child: const Icon(Icons.colorize, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SectionTitle('Symbol'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in categoryIcons.entries)
                  IconButton.filledTonal(
                    isSelected: e.key == _icon,
                    style: e.key == _icon
                        ? IconButton.styleFrom(backgroundColor: _color, foregroundColor: _onColor(_color))
                        : null,
                    onPressed: () => setState(() => _icon = e.key),
                    icon: Icon(e.value),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SaveBar(onPressed: _save),
    );
  }
}

Color _onColor(Color c) => ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black87;

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
          ),
          child: selected ? Icon(Icons.check, color: _onColor(color), size: 20) : null,
        ),
      );
}

/// Free color choice with hue / saturation / brightness sliders.
class _HsvDialog extends StatefulWidget {
  const _HsvDialog({required this.initial});
  final HSVColor initial;

  @override
  State<_HsvDialog> createState() => _HsvDialogState();
}

class _HsvDialogState extends State<_HsvDialog> {
  late HSVColor _hsv = widget.initial;

  Widget _slider(String label, double value, double max, ValueChanged<double> onChanged) => Row(
        children: [
          SizedBox(width: 84, child: Text(label)),
          Expanded(child: Slider(value: value, max: max, onChanged: (v) => setState(() => onChanged(v)))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Eigene Farbe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(color: _hsv.toColor(), borderRadius: BorderRadius.circular(16)),
          ),
          const SizedBox(height: 12),
          _slider('Farbton', _hsv.hue, 360, (v) => _hsv = _hsv.withHue(v.clamp(0, 359.9))),
          _slider('Sättigung', _hsv.saturation, 1, (v) => _hsv = _hsv.withSaturation(v)),
          _slider('Helligkeit', _hsv.value, 1, (v) => _hsv = _hsv.withValue(v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, _hsv.toColor()), child: const Text('Übernehmen')),
      ],
    );
  }
}
