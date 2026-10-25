import 'package:flutter/material.dart';

import '../data/db.dart';

/// Palette taken from the logo: deep green -> gold.
abstract final class Brand {
  static const greenDark = Color(0xFF173F2A);
  static const green = Color(0xFF2E6B3A);
  static const olive = Color(0xFF6B7A2A);
  static const gold = Color(0xFFC9A227);

  /// Header gradient; white text sits on the green part.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [greenDark, green, olive, gold],
    stops: [0, 0.45, 0.8, 1],
  );
}

/// Colors Material 3 has no slot for.
@immutable
class CashColors extends ThemeExtension<CashColors> {
  const CashColors({required this.income, required this.expense, required this.subtle});

  final Color income;
  final Color expense;
  final Color subtle;

  Color forKind(EntryKind k) => k == EntryKind.income ? income : expense;

  static const light = CashColors(income: Color(0xFF1B7A2E), expense: Color(0xFFC62828), subtle: Color(0xFF5E665C));
  static const dark = CashColors(income: Color(0xFF7BD389), expense: Color(0xFFFF8A80), subtle: Color(0xFFA9B3A6));

  @override
  CashColors copyWith({Color? income, Color? expense, Color? subtle}) => CashColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        subtle: subtle ?? this.subtle,
      );

  @override
  CashColors lerp(CashColors? other, double t) {
    if (other == null) return this;
    return CashColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: brightness,
    primary: light ? Brand.green : const Color(0xFF8FD19A),
    tertiary: light ? const Color(0xFF8A6D00) : const Color(0xFFE9C55A),
    surface: light ? const Color(0xFFF6F8F2) : const Color(0xFF111712),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final radius = BorderRadius.circular(20);
  return base.copyWith(
    extensions: [if (light) CashColors.light else CashColors.dark],
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: light ? Brand.gold : const Color(0xFFE9C55A),
      foregroundColor: const Color(0xFF2A2000),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
  );
}

extension CashTheme on BuildContext {
  CashColors get cash => Theme.of(this).extension<CashColors>()!;
}
