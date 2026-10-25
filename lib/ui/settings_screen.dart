import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../data/recurring_runner.dart';
import '../providers.dart';
import '../services/notifications.dart';
import '../services/pin.dart';
import '../services/settings.dart';
import 'categories_screen.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionTitle('Darstellung'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Hell'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => notifier.update((s) => s.copyWith(themeMode: v.first)),
            ),
          ),
          const SectionTitle('Daten'),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Kategorien'),
            subtitle: const Text('Namen, Farben, Symbole, Reihenfolge'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CategoriesScreen())),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Benachrichtigung bei wiederkehrenden Buchungen'),
            subtitle: const Text('Hinweis, wenn Buchungen automatisch eingetragen wurden'),
            value: s.notifyRecurring,
            onChanged: (v) async {
              if (v) await requestNotificationPermission();
              await notifier.update((s) => s.copyWith(notifyRecurring: v));
            },
          ),
          const SectionTitle('App-Sperre'),
          const _LockSettings(),
          const SectionTitle('Datensicherung'),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Sicherung exportieren (JSON)'),
            subtitle: const Text('Alle Daten – zum Wiederherstellen'),
            onTap: () => _exportJson(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Buchungen exportieren (CSV)'),
            subtitle: const Text('Für Tabellenkalkulationen'),
            onTap: () => _exportCsv(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Sicherung importieren'),
            subtitle: const Text('Ersetzt alle vorhandenen Daten'),
            onTap: () => _import(context, ref),
          ),
          const SectionTitle('Über'),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/branding/mascot.png', width: 40, height: 40),
            ),
            title: const Text('CashBandit'),
            subtitle: const Text('100 % offline – keine Internet-Berechtigung, keine Tracker, kein Konto.\n'
                'Freie Software unter der GPL-3.0.'),
            isThreeLine: true,
            onTap: () => showLicensePage(context: context, applicationName: 'CashBandit'),
          ),
        ],
      ),
    );
  }
}

class _LockSettings extends ConsumerWidget {
  const _LockSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final lock = ref.read(appLockProvider);
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('App-Sperre'),
          subtitle: const Text('PIN beim Öffnen; Inhalt im App-Wechsler ausgeblendet'),
          value: s.lockEnabled,
          onChanged: (on) async {
            if (on) {
              final pin = await askNewPin(context);
              if (pin == null) return;
              await lock.setPin(pin);
              await notifier.update((s) => s.copyWith(lockEnabled: true));
            } else {
              final pin = await askPin(context, 'Aktuelle PIN');
              if (pin == null) return;
              if (!await lock.checkPin(pin)) {
                if (context.mounted) showMessage(context, 'Falsche PIN');
                return;
              }
              await notifier.update((s) => s.copyWith(lockEnabled: false, biometrics: false));
              await lock.removePin();
            }
          },
        ),
        if (s.lockEnabled) ...[
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Mit Fingerabdruck entsperren'),
            subtitle: const Text('Die PIN bleibt als Ausweichmöglichkeit'),
            value: s.biometrics,
            onChanged: (on) async {
              if (on) {
                if (!await lock.canUseBiometrics()) {
                  if (context.mounted) showMessage(context, 'Auf diesem Gerät ist keine Biometrie eingerichtet.');
                  return;
                }
                if (!await lock.authenticateBiometric('Fingerabdruck für CashBandit bestätigen')) return;
              }
              await notifier.update((s) => s.copyWith(biometrics: on));
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Sperren im Hintergrund'),
            trailing: DropdownButton<int>(
              value: lockDelays.containsKey(s.lockAfterSeconds) ? s.lockAfterSeconds : 0,
              underline: const SizedBox(),
              items: [for (final e in lockDelays.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => notifier.update((s) => s.copyWith(lockAfterSeconds: v)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('PIN ändern'),
            onTap: () async {
              final old = await askPin(context, 'Aktuelle PIN');
              if (old == null) return;
              if (!await lock.checkPin(old)) {
                if (context.mounted) showMessage(context, 'Falsche PIN');
                return;
              }
              if (!context.mounted) return;
              final pin = await askNewPin(context);
              if (pin == null) return;
              await lock.setPin(pin);
              if (context.mounted) showMessage(context, 'PIN geändert');
            },
          ),
        ],
      ],
    );
  }
}

/// Asks for a new PIN twice; null if cancelled.
Future<String?> askNewPin(BuildContext context) async {
  final first = await askPin(context, 'Neue PIN (4–6 Ziffern)');
  if (first == null || !context.mounted) return null;
  final second = await askPin(context, 'PIN wiederholen');
  if (second == null) return null;
  if (first != second) {
    if (context.mounted) showMessage(context, 'Die PINs stimmen nicht überein.');
    return null;
  }
  return first;
}

Future<String?> askPin(BuildContext context, String title) => showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        final formKey = GlobalKey<FormState>();
        void submit() {
          if (formKey.currentState!.validate()) Navigator.pop(context, controller.text);
        }

        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              validator: (v) => isValidPin(v ?? '') ? null : '4 bis 6 Ziffern',
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      },
    );

String _stamp() => DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());

Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
  final json = await exportJson(ref.read(dbProvider));
  if (!context.mounted) return;
  await _saveOrShare(context, ref, 'cashbandit-sicherung_${_stamp()}.json', utf8.encode(json), 'application/json');
}

Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
  final csv = await exportCsv(ref.read(dbProvider));
  if (!context.mounted) return;
  await _saveOrShare(context, ref, 'cashbandit-buchungen_${_stamp()}.csv', utf8.encode(csv), 'text/csv');
}

Future<void> _saveOrShare(BuildContext context, WidgetRef ref, String name, List<int> data, String mime) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(name, style: Theme.of(context).textTheme.titleSmall)),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Als Datei speichern'),
            onTap: () => Navigator.pop(context, 'save'),
          ),
          ListTile(leading: const Icon(Icons.share), title: const Text('Teilen'), onTap: () => Navigator.pop(context, 'share')),
        ],
      ),
    ),
  );
  if (action == null) return;
  final lock = ref.read(appLockProvider);
  final bytes = Uint8List.fromList(data);
  try {
    if (action == 'save') {
      final uri = await lock.suspendWhile(
        () => FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: 'Speichern unter'),
      );
      if (uri != null && context.mounted) showMessage(context, 'Gespeichert');
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      try {
        await lock.suspendWhile(
          () => SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: name)),
        );
      } finally {
        // the share target has its own copy by now
        Future.delayed(const Duration(minutes: 1), () => file.delete().ignore()).ignore();
      }
    }
  } catch (e) {
    if (context.mounted) showMessage(context, 'Export fehlgeschlagen: $e');
  }
}

Future<void> _import(BuildContext context, WidgetRef ref) async {
  final lock = ref.read(appLockProvider);
  final files = await lock.suspendWhile(() => FilePicker.pickFiles(dialogTitle: 'Sicherung wählen'));
  if (files.isEmpty || !context.mounted) return;
  final BackupContent content;
  try {
    content = parseBackup(utf8.decode(await files.first.readAsBytes(), allowMalformed: false));
  } on BackupException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return;
  } on FormatException {
    if (context.mounted) showMessage(context, 'Die Datei ist keine CashBandit-Sicherung.');
    return;
  }
  if (!context.mounted) return;
  final when = content.exportedAt == null ? '' : ' vom ${DateFormat('d. MMMM y, HH:mm').format(content.exportedAt!.toLocal())}';
  final ok = await confirm(
    context,
    title: 'Alle Daten ersetzen?',
    message: 'Sicherung$when:\n'
        '${content.bookings.length} Buchungen, ${content.categories.length} Kategorien, '
        '${content.rules.length} wiederkehrende Buchungen.\n\n'
        'ALLE aktuellen Daten in der App werden dabei gelöscht und durch die Sicherung ersetzt. '
        'Tipp: vorher eine aktuelle Sicherung exportieren.',
    confirmLabel: 'Ersetzen',
  );
  if (!ok) return;
  final db = ref.read(dbProvider);
  await importBackup(db, content);
  await runDueRecurring(db);
  if (context.mounted) showMessage(context, 'Sicherung wiederhergestellt');
}
