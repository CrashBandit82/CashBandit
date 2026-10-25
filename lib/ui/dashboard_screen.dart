import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/stats.dart';
import '../data/db.dart';
import '../data/repository.dart';
import '../providers.dart';
import 'bookings_screen.dart';
import 'charts.dart';
import 'theme.dart';
import 'widgets.dart';

const _historyMonths = 12;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  PeriodMode _mode = PeriodMode.month;
  DateTime _anchor = today();
  bool _monthByWeek = true;

  DayRange get _range => periodRange(_mode, _anchor);

  String get _periodLabel {
    final r = _range;
    if (_mode == PeriodMode.month) return monthFormat.format(r.from);
    final f = DateFormat('d. MMM');
    return 'KW ${isoWeek(r.from)} · ${f.format(r.from)} – ${f.format(r.to)}';
  }

  void _shift(int delta) => setState(() => _anchor = shiftPeriod(_mode, _anchor, delta));

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final rows = ref.watch(bookingsProvider(BookingQuery(range: range))).value;
    final history = ref.watch(bookingsProvider(BookingQuery(range: monthsRange(range.to, _historyMonths)))).value;
    final categories = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};
    final isCurrent = range.contains(today());

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              mode: _mode,
              label: _periodLabel,
              totals: rows == null ? null : Totals.of(rows),
              onMode: (m) => setState(() => _mode = m),
              onPrev: () => _shift(-1),
              onNext: () => _shift(1),
              onToday: isCurrent ? null : () => setState(() => _anchor = today()),
            ),
          ),
          if (rows != null) ...[
            SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text('Ausgaben nach Kategorie', style: Theme.of(context).textTheme.titleMedium)),
                            if (_mode == PeriodMode.month)
                              SegmentedButton<bool>(
                                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(value: true, label: Text('Wochen')),
                                  ButtonSegment(value: false, label: Text('Tage')),
                                ],
                                selected: {_monthByWeek},
                                onSelectionChanged: (s) => setState(() => _monthByWeek = s.first),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 220,
                        child: StackedExpenseChart(
                          categories: categories,
                          buckets: fillExpenses(
                            _mode == PeriodMode.week
                                ? dayBuckets(range, weekdayLabels: true)
                                : (_monthByWeek ? weekBuckets(range) : dayBuckets(range, weekdayLabels: false)),
                            rows,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ..._breakdown(context, rows, EntryKind.expense, range),
            ..._breakdown(context, rows, EntryKind.income, range),
          ],
          if (history != null)
            SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('Einnahmen und Ausgaben – $_historyMonths Monate',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(children: [
                          _Legend(color: context.cash.income, text: 'Einnahmen'),
                          const SizedBox(width: 16),
                          _Legend(color: context.cash.expense, text: 'Ausgaben'),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: IncomeExpenseChart(months: monthlyTotals(history, range.to, _historyMonths)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  List<Widget> _breakdown(BuildContext context, List<BookingRow> rows, EntryKind kind, DayRange range) {
    final list = breakdown(rows, kind);
    if (list.isEmpty && kind == EntryKind.income) return const [];
    return [
      SliverToBoxAdapter(child: SectionTitle(kind.plural)),
      if (list.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Text('Keine Ausgaben in diesem Zeitraum.')),
        ),
      SliverList.builder(
        itemCount: list.length,
        itemBuilder: (context, i) => _ShareTile(
          share: list[i],
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => BookingsScreen(
              title: '${list[i].category.name} · $_periodLabel',
              initial: BookingQuery(range: range, categoryId: list[i].category.id),
            ),
          )),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.mode,
    required this.label,
    required this.totals,
    required this.onMode,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final PeriodMode mode;
  final String label;
  final Totals? totals;
  final ValueChanged<PeriodMode> onMode;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const white = Colors.white;
    final t = totals;
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 8, 16, 20),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/branding/mascot.png', width: 36, height: 36),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('CashBandit', style: text.titleLarge?.copyWith(color: white))),
              SegmentedButton<PeriodMode>(
                style: SegmentedButton.styleFrom(
                  foregroundColor: white,
                  selectedForegroundColor: Brand.greenDark,
                  selectedBackgroundColor: white,
                  side: const BorderSide(color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PeriodMode.week, label: Text('Woche')),
                  ButtonSegment(value: PeriodMode.month, label: Text('Monat')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => onMode(s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(onPressed: onPrev, tooltip: 'Zurück', icon: const Icon(Icons.chevron_left, color: white)),
              Expanded(
                child: GestureDetector(
                  onTap: onToday,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(label, key: ValueKey(label), textAlign: TextAlign.center, style: text.titleMedium?.copyWith(color: white)),
                  ),
                ),
              ),
              IconButton(onPressed: onNext, tooltip: 'Weiter', icon: const Icon(Icons.chevron_right, color: white)),
            ],
          ),
          if (onToday != null)
            TextButton(
              onPressed: onToday,
              style: TextButton.styleFrom(foregroundColor: white, visualDensity: VisualDensity.compact),
              child: const Text('Zurück zu heute'),
            ),
          const SizedBox(height: 4),
          Text('Saldo', style: text.labelLarge?.copyWith(color: Colors.white70)),
          _AnimatedAmount(
            cents: t?.balance ?? 0,
            style: text.displaySmall!.copyWith(color: white, fontWeight: FontWeight.w800),
            signed: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Pill(icon: Icons.south_west, label: 'Einnahmen', cents: t?.income ?? 0)),
              const SizedBox(width: 12),
              Expanded(child: _Pill(icon: Icons.north_east, label: 'Ausgaben', cents: t?.expense ?? 0)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.cents});
  final IconData icon;
  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _AnimatedAmount(
                      cents: cents,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Counts smoothly to a new amount.
class _AnimatedAmount extends StatelessWidget {
  const _AnimatedAmount({required this.cents, required this.style, this.signed = false});
  final int cents;
  final TextStyle style;
  final bool signed;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: cents.toDouble()),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(
          formatCents(v.round(), signed: signed),
          style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      );
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({required this.share, required this.onTap});
  final CategoryShare share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(share.category.color);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            children: [
              CategoryAvatar.of(share.category, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(share.category.name, style: Theme.of(context).textTheme.titleSmall)),
                        Text(formatCents(share.cents), style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: share.share),
                              duration: const Duration(milliseconds: 450),
                              builder: (context, v, _) => LinearProgressIndicator(
                                value: v,
                                minHeight: 6,
                                color: color,
                                backgroundColor: color.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${NumberFormat('0.0', 'de_AT').format(share.share * 100)} %',
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelMedium),
      ]);
}
