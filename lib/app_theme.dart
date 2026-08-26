// lib/app_theme.dart
//
// NaijaLearn — Centralized Design System
//
// ONE file that defines every color, text style, radius, and spacing
// value the whole app uses. Because nearly every screen already reads
// from `Theme.of(context).colorScheme` / `Theme.of(context).textTheme`
// instead of hardcoding colors, swapping this file in changes the LOOK
// of the entire app instantly — no per-screen edits needed.
//
// WHAT TO DO WITH THIS FILE:
//   1. Drop it in as lib/app_theme.dart
//   2. In main.dart, replace NaijaLearnApp's inline ColorScheme.fromSeed
//      blocks with AppTheme.light(seed) / AppTheme.dark(seed) — see the
//      exact snippet in the comment at the bottom of this file.
//   3. That's it. Every screen using scheme.primary, scheme.surface,
//      scheme.surfaceContainerHighest, etc. re-themes automatically.
//
// WHAT THIS DOESN'T FIX AUTOMATICALLY:
//   Any screen with a HARDCODED color like `Colors.amber` or
//   `Colors.green` instead of a semantic color from this file won't
//   change. Those are the main offenders for visual inconsistency —
//   see AppColors below for the semantic replacements to swap in over
//   time (Colors.amber → AppColors.xp, Colors.green → AppColors.success,
//   Colors.red → AppColors.error, etc.). You don't have to do this all
//   at once — the app already looks meaningfully more polished from
//   step 2 alone.

import 'package:flutter/material.dart';

/// =========================================================================
/// BRAND COLORS — the single source of truth for every color in the app.
/// =========================================================================
class AppColors {
  AppColors._();

  // --- Brand seeds ---------------------------------------------------
  /// Primary brand color — a deeper, richer emerald than the old flat
  /// Nigerian green. Still unmistakably "green" for brand recognition,
  /// but reads as premium instead of generic.
  static const Color seedPrimary = Color(0xFF059669); // emerald-600

  /// Ocean Theme Pack seed (Coin Shop purchase) — kept, deepened to
  /// match the new primary's saturation/value so the swap feels
  /// intentional rather than like a different, cheaper app.
  static const Color seedOcean = Color(0xFF0284C7); // sky-600

  // --- Semantic colors — use these instead of raw Colors.xxx --------
  /// Success / correct-answer / completed states.
  static const Color success = Color(0xFF16A34A); // green-600
  static const Color successContainer = Color(0xFFDCFCE7);

  /// Errors, wrong answers, destructive actions.
  static const Color error = Color(0xFFDC2626); // red-600
  static const Color errorContainer = Color(0xFFFEE2E2);

  /// Warnings, "at risk" states (streak saver, low time).
  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color warningContainer = Color(0xFFFEF3C7);

  /// Informational accents, links, secondary CTAs.
  static const Color info = Color(0xFF2563EB); // blue-600
  static const Color infoContainer = Color(0xFFDBEAFE);

  /// XP, coins, rewards, gold-tier badges — the "gamification gold"
  /// used consistently everywhere instead of ad-hoc Colors.amber.
  static const Color xp = Color(0xFFD97706); // amber-600 (deeper, richer than amber-500)
  static const Color gold = Color(0xFFEAB308); // for 1st place / league gold specifically

  /// Rank/tier accent colors — reused by Career Mode, Leagues, Squad Perks.
  static const Color tierBronze = Color(0xFFB45309);
  static const Color tierSilver = Color(0xFF64748B);
  static const Color tierGold = Color(0xFFCA8A04);
  static const Color tierPlatinum = Color(0xFF0891B2);
  static const Color tierDiamond = Color(0xFF7C3AED);
  static const Color tierLegend = Color(0xFFDB2777);
}

/// =========================================================================
/// SPACING SCALE — use these instead of ad-hoc SizedBox(height: 13) etc.
/// so vertical/horizontal rhythm is consistent across every screen.
/// =========================================================================
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// =========================================================================
/// RADIUS SCALE — replaces the mix of BorderRadius.circular(12/14/16/18/20)
/// scattered through the app with a consistent, named set.
/// =========================================================================
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 22;
  static const double pill = 999;

  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static BorderRadius get xlRadius => BorderRadius.circular(xl);
}

/// =========================================================================
/// THEME BUILDER — produces the actual ThemeData for light/dark mode.
/// Accepts a seedColor so the existing Ocean Theme Pack swap in
/// NaijaLearnApp keeps working unchanged.
/// =========================================================================
class AppTheme {
  AppTheme._();

  static ThemeData light(Color seedColor) => _build(seedColor, Brightness.light);
  static ThemeData dark(Color seedColor) => _build(seedColor, Brightness.dark);

  static ThemeData _build(Color seedColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final baseColorScheme = ColorScheme.fromSeed(
  seedColor: seedColor,
  brightness: brightness,
);

// ColorScheme.fromSeed's default dark surfaces are too close together —
// that's what flattens every card into the same gray block. Manually
// step the surface ladder so cards visibly lift off the background.
final colorScheme = isDark
    ? baseColorScheme.copyWith(
        surface: const Color(0xFF0B0F0E),
        surfaceContainerLowest: const Color(0xFF080B0A),
        surfaceContainerLow: const Color(0xFF141A18),
        surfaceContainer: const Color(0xFF1C2422),
        surfaceContainerHigh: const Color(0xFF26302D),
        surfaceContainerHighest: const Color(0xFF313D3A),
      )
    : baseColorScheme;

final backgroundColor = isDark ? const Color(0xFF0B0F0E) : const Color(0xFFF7F9F8);
    final textTheme = _textTheme(isDark);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      fontFamily: 'Roboto',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,

      // --- AppBar: flat, no harsh elevation shadow, matches background
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),

      // --- Buttons: consistent radius + padding everywhere ---
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          side: BorderSide(color: colorScheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // --- Cards / containers: consistent elevation + radius ---
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
        margin: EdgeInsets.zero,
      ),

      // --- Inputs: consistent border radius + fill ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // --- Chips: pill-shaped, consistent with rest of app ---
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        side: BorderSide.none,
      ),

      // --- Bottom navigation: matches surface, no default indicator noise ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 2,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // --- Dialogs: match card radius ---
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
        backgroundColor: colorScheme.surface,
      ),

      // --- Progress indicators: rounded, uses primary by default ---
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),

      // --- Snackbars: floating, rounded, consistent with cards ---
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        backgroundColor: isDark ? colorScheme.surfaceContainerHighest : colorScheme.inverseSurface,
      ),

      // --- Dividers: subtle, not harsh default gray ---
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.5),
        thickness: 1,
      ),
    );
  }

  static TextTheme _textTheme(bool isDark) {
    final base = isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.4),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

// =============================================================================
// HOW TO WIRE THIS INTO main.dart
// =============================================================================
//
// In NaijaLearnApp.build(), replace this:
//
//   theme: ThemeData(
//     useMaterial3: true,
//     colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light),
//     scaffoldBackgroundColor: const Color(0xFFF7F9F8),
//     fontFamily: 'Roboto',
//   ),
//   darkTheme: ThemeData(
//     useMaterial3: true,
//     colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
//     scaffoldBackgroundColor: const Color(0xFF101312),
//     fontFamily: 'Roboto',
//   ),
//
// with this:
//
//   theme: AppTheme.light(seedColor),
//   darkTheme: AppTheme.dark(seedColor),
//
// And add this import at the top of main.dart:
//
//   import 'app_theme.dart';
//
// Also update the two seed constants in NaijaLearnApp to use the new
// brand colors instead of the old flat ones:
//
//   static const Color _seed = AppColors.seedPrimary;
//   static const Color _oceanSeed = AppColors.seedOcean;
//
// That's the entire integration. Every screen that calls
// Theme.of(context).colorScheme.primary / .surfaceContainerHighest /
// .primaryContainer / etc. re-themes immediately with no other changes.
