import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/icons.dart';
import '../core/money.dart';
import '../data/db.dart';
import 'theme.dart';

final dayFormat = DateFormat('EEEE, d. MMMM y');
final shortDayFormat = DateFormat('d. MMM y');
final monthFormat = DateFormat('MMMM y');

/// Round avatar in the category color with its icon.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.color, required this.icon, this.size = 40});

  CategoryAvatar.of(Category c, {super.key, this.size = 40})
      : color = Color(c.color),
        icon = c.icon;

  final Color color;
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(categoryIcon(icon), color: onColor, size: size * 0.55),
    );
  }
}

/// Amount in income / expense color with sign.
class AmountText extends StatelessWidget {
  const AmountText(this.cents, this.kind, {super.key, this.style});
  final int cents;
  final EntryKind kind;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    return Text(
      formatCents(kind == EntryKind.income ? cents : -cents, signed: true),
      style: base?.copyWith(color: context.cash.forKind(kind), fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Löschen',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Empty state with icon and text.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = context.cash.subtle;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

/// Section title inside lists.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}
