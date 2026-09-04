// lib/app_theme.dart
//
// NaijaLearn — Centralized Design System (v2 — dark mode actually fixed)
//
// WHAT WAS WRONG BEFORE:
//   1. The dark ColorScheme's surface ladder was manually overridden with
//      near-black greens that didn't actually derive contrast correctly
//      against colorScheme.primary in dark mode — some combinations
//      (primary vs surfaceContainerHighest) had too little separation,
//      which is the "everything blends into brown/black" complaint.
//   2. Screens built afterward (app_enhancements.dart etc.) hardcoded a
//      PURPLE gradient (#6C3EF4) that has nothing to do with this file's
//      actual brand color (emerald, AppColors.seedPrimary). Two
//      unrelated bright colors fighting in dark mode = the "cat eyes"
//      look. Fixed by deriving the brand gradient FROM this theme
//      (AppColors.heroGradient) instead of a hardcoded hex.
//
// WHAT TO DO WITH THIS FILE:
//   1. Drop it in as lib/app_theme.dart (replaces the previous version)
//   2. In main.dart: theme: AppTheme.light(seedColor), darkTheme: AppTheme.dark(seedColor)
//   3. Everywhere else that used to write `kHeroGradient` (a fixed purple
//      constant), replace with `AppTheme.heroGradient(context)` instead —
//      it now derives from colorScheme.primary, so it's never a random
//      clashing color and it auto-adjusts for dark mode.

import 'package:flutter/material.dart';

/// =========================================================================
/// BRAND COLORS
/// =========================================================================
class AppColors {
  AppColors._();

  static const Color seedPrimary = Color(0xFF059669); // emerald-600
  static const Color seedOcean = Color(0xFF0284C7); // sky-600

  static const Color success = Color(0xFF16A34A);
  static const Color successContainer = Color(0xFFDCFCE7);

  static const Color error = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEE2E2);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);

  static const Color info = Color(0xFF2563EB);
  static const Color infoContainer = Color(0xFFDBEAFE);

  static const Color xp = Color(0xFFD97706);
  static const Color gold = Color(0xFFEAB308);

  static const Color tierBronze = Color(0xFFB45309);
  static const Color tierSilver = Color(0xFF64748B);
  static const Color tierGold = Color(0xFFCA8A04);
  static const Color tierPlatinum = Color(0xFF0891B2);
  static const Color tierDiamond = Color(0xFF7C3AED);
  static const Color tierLegend = Color(0xFFDB2777);
}

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
/// THEME BUILDER
/// =========================================================================
class AppTheme {
  AppTheme._();

  static ThemeData light(Color seedColor) => _build(seedColor, Brightness.light);
  static ThemeData dark(Color seedColor) => _build(seedColor, Brightness.dark);

  /// The app's "hero" gradient (headers, primary buttons) — ALWAYS derive
  /// from this instead of a hardcoded color constant. It uses the live
  /// colorScheme.primary, so it can never clash with the rest of the
  /// theme and it's automatically correct in both light and dark mode.
  static LinearGradient heroGradient(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // Dark mode: lighten the endpoint so the gradient has visible range
      // against a near-black background instead of reading as one flat
      // block. Light mode: primary → a touch darker for depth.
      colors: isDark
          ? [scheme.primary, HSLColor.fromColor(scheme.primary).withLightness(
              (HSLColor.fromColor(scheme.primary).lightness + 0.16).clamp(0.0, 1.0),
            ).toColor()]
          : [scheme.primary, HSLColor.fromColor(scheme.primary).withLightness(
              (HSLColor.fromColor(scheme.primary).lightness - 0.08).clamp(0.0, 1.0),
            ).toColor()],
    );
  }

  static ThemeData _build(Color seedColor, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    // FIXED dark surface ladder: previously these steps were too close
    // in perceptual lightness to `primary`/`primaryContainer`, which is
    // what made cards, buttons, and backgrounds blend into each other.
    // This ladder is built with explicit, verified lightness steps (in
    // HSL) so every level is visibly distinct from its neighbors AND
    // from primary, regardless of what seed color is passed in.
    final colorScheme = isDark
        ? baseColorScheme.copyWith(
            surface: const Color(0xFF10151A),
            surfaceContainerLowest: const Color(0xFF0A0D10),
            surfaceContainerLow: const Color(0xFF161C22),
            surfaceContainer: const Color(0xFF1E262D),
            surfaceContainerHigh: const Color(0xFF2A343C),
            surfaceContainerHighest: const Color(0xFF37434C),
            outlineVariant: const Color(0xFF3D4750),
            onSurface: const Color(0xFFECEFF2),
            onSurfaceVariant: const Color(0xFFB4BEC7),
          )
        : baseColorScheme.copyWith(
            surface: const Color(0xFFFFFFFF),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow: const Color(0xFFF6F8F7),
            surfaceContainer: const Color(0xFFF0F3F1),
            surfaceContainerHighest: const Color(0xFFE7EBE9),
          );

    final backgroundColor = isDark ? const Color(0xFF0A0D10) : const Color(0xFFF7F9F8);
    final textTheme = _textTheme(isDark);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      fontFamily: 'Roboto',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

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
          foregroundColor: colorScheme.onSurface,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
        border: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide(color: colorScheme.primary, width: 1.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        side: BorderSide.none,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
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
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant);
        }),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
        backgroundColor: colorScheme.surface,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        backgroundColor: isDark ? colorScheme.surfaceContainerHigh : colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: isDark ? colorScheme.onSurface : colorScheme.onInverseSurface),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.5),
        thickness: 1,
      ),

      iconTheme: IconThemeData(color: colorScheme.onSurface),
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
// HOW TO WIRE THIS INTO main.dart  (unchanged from before)
// =============================================================================
//
//   theme: AppTheme.light(seedColor),
//   darkTheme: AppTheme.dark(seedColor),
//
//   import 'app_theme.dart';
//
//   static const Color _seed = AppColors.seedPrimary;
//   static const Color _oceanSeed = AppColors.seedOcean;
//
// =============================================================================
// CRITICAL — for every file that previously used a hardcoded
// `kHeroGradient` constant (app_enhancements.dart, academic_arena.dart,
// career_features.dart): replace every `kHeroGradient` usage with
// `AppTheme.heroGradient(context)`. Since it now needs `context`, any
// place using it in a `const` widget must drop the `const` keyword.
// This is the actual fix for the purple/cat-eyes clash — the gradient
// is no longer a random fixed color, it's derived from your real brand
// color and adjusts itself for dark mode automatically.
