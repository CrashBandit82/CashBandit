import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/money.dart';
import '../core/stats.dart';
import '../data/db.dart';
import 'theme.dart';

/// Axis label: whole euros, "1,2 T" from 10.000 on.
String _axisEuro(double euros) {
  if (euros.abs() >= 10000) return '${(euros / 1000).toStringAsFixed(0)} T';
  return formatCents((euros * 100).round(), withSymbol: false).split(',').first;
}

/// Rounded-up axis maximum with a readable step (1/2/5 × 10^n).
(double max, double step) _niceAxis(double maxValue) {
  if (maxValue <= 0) return (100, 25);
  final raw = maxValue / 4;
  final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
  final step = [1, 2, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw);
  return ((maxValue / step).ceil() * step, step);
}

FlTitlesData _titles(BuildContext context, {required Widget Function(double) bottom, required double step, double bottomSize = 24}) {
  final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: context.cash.subtle);
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 44,
        interval: step,
        getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(_axisEuro(v), style: style)),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: bottomSize,
        getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: DefaultTextStyle.merge(style: style, child: bottom(v))),
      ),
    ),
  );
}

FlGridData _grid(BuildContext context, double step) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (_) => FlLine(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
    );

/// Expenses per day / week, stacked in category colors.
class StackedExpenseChart extends StatelessWidget {
  const StackedExpenseChart({super.key, required this.buckets, required this.categories});
  final List<Bucket> buckets;
  final Map<int, Category> categories;

  @override
  Widget build(BuildContext context) {
    final maxTotal = buckets.fold<int>(0, (m, b) => max(m, b.total)) / 100;
    final (maxY, step) = _niceAxis(maxTotal);
    final many = buckets.length > 10;
    final width = many ? 6.0 : (buckets.length > 5 ? 22.0 : 30.0);
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    // categories in their configured order, so stacks look the same in every bar
    final order = categories.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return BarChart(
      duration: const Duration(milliseconds: 350),
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _grid(context, step),
        titlesData: _titles(
          context,
          step: step,
          bottom: (v) {
            final i = v.toInt();
            if (i < 0 || i >= buckets.length) return const SizedBox();
            // month by day: label every 5th day only
            if (many && (i + 1) % 5 != 0 && i != 0) return const SizedBox();
            return Text(buckets[i].label);
          },
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
            getTooltipItem: (group, _, rod, _) {
              final b = buckets[group.x];
              return BarTooltipItem(
                '${b.label}\n${formatCents(b.total)}',
                TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
        barGroups: [
          for (final (i, b) in buckets.indexed)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: b.total / 100,
                  width: width,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(width / 3)),
                  color: empty,
                  backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY, color: empty.withValues(alpha: 0.35)),
                  rodStackItems: _stack(b, order),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<BarChartRodStackItem> _stack(Bucket b, List<Category> order) {
    final items = <BarChartRodStackItem>[];
    var y = 0.0;
    for (final c in order) {
      final cents = b.byCategory[c.id];
      if (cents == null || cents == 0) continue;
      items.add(BarChartRodStackItem(y, y + cents / 100, Color(c.color)));
      y += cents / 100;
    }
    return items;
  }
}

/// Income vs. expenses per month.
class IncomeExpenseChart extends StatelessWidget {
  const IncomeExpenseChart({super.key, required this.months});
  final List<MonthTotals> months;

  @override
  Widget build(BuildContext context) {
    final cash = context.cash;
    final maxValue = months.fold<int>(0, (m, t) => max(m, max(t.totals.income, t.totals.expense))) / 100;
    final (maxY, step) = _niceAxis(maxValue);
    final label = DateFormat('MMM');
    const width = 7.0;
    return BarChart(
      duration: const Duration(milliseconds: 350),
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _grid(context, step),
        titlesData: _titles(
          context,
          step: step,
          bottom: (v) {
            final i = v.toInt();
            if (i < 0 || i >= months.length) return const SizedBox();
            return Text(label.format(months[i].month).substring(0, 3));
          },
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
            getTooltipItem: (group, _, rod, rodIndex) {
              final m = months[group.x];
              final text = rodIndex == 0
                  ? '${DateFormat('MMMM y').format(m.month)}\nEinnahmen ${formatCents(m.totals.income)}'
                  : 'Ausgaben ${formatCents(m.totals.expense)}';
              return BarTooltipItem(text, TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 12));
            },
          ),
        ),
        barGroups: [
          for (final (i, m) in months.indexed)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(
                  toY: m.totals.income / 100,
                  width: width,
                  color: cash.income,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
                BarChartRodData(
                  toY: m.totals.expense / 100,
                  width: width,
                  color: cash.expense,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
