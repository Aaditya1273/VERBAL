import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// VERBAL's design tokens.
///
/// Restrained on purpose: one accent, one signal colour, a lot of space, and
/// typography doing most of the work. This is a training tool for serious
/// conversations — it should feel closer to a well-made notebook than to a game.
class VerbalTokens {
  const VerbalTokens._();

  // Light
  static const lightBg = Color(0xFFF7F6F3);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightRaised = Color(0xFFF1EFEA);
  static const lightInk = Color(0xFF14171C);
  static const lightMuted = Color(0xFF6B7280);
  static const lightLine = Color(0xFFE3E0DA);

  // Dark
  static const darkBg = Color(0xFF0E1116);
  static const darkSurface = Color(0xFF171B22);
  static const darkRaised = Color(0xFF1F242D);
  static const darkInk = Color(0xFFF2F3F5);
  static const darkMuted = Color(0xFF9AA3AF);
  static const darkLine = Color(0xFF262C36);

  /// Accent — calm, professional, never neon.
  static const accentLight = Color(0xFF175E54);
  static const accentDark = Color(0xFF44A794);

  /// Signal — live microphone, pressure, anything demanding attention.
  static const signalLight = Color(0xFFB4400E);
  static const signalDark = Color(0xFFF97316);

  // Spacing scale.
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  static const radius = 20.0;
  static const radiusLarge = 30.0;
  static const radiusPill = 999.0;

  /// Minimum touch target.
  static const tap = 48.0;
}

/// Semantic colours resolved for the current brightness.
@immutable
class VerbalColors extends ThemeExtension<VerbalColors> {
  const VerbalColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.signal,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color signal;

  static const light = VerbalColors(
    bg: VerbalTokens.lightBg,
    surface: VerbalTokens.lightSurface,
    raised: VerbalTokens.lightRaised,
    ink: VerbalTokens.lightInk,
    muted: VerbalTokens.lightMuted,
    line: VerbalTokens.lightLine,
    accent: VerbalTokens.accentLight,
    signal: VerbalTokens.signalLight,
  );

  static const dark = VerbalColors(
    bg: VerbalTokens.darkBg,
    surface: VerbalTokens.darkSurface,
    raised: VerbalTokens.darkRaised,
    ink: VerbalTokens.darkInk,
    muted: VerbalTokens.darkMuted,
    line: VerbalTokens.darkLine,
    accent: VerbalTokens.accentDark,
    signal: VerbalTokens.signalDark,
  );

  @override
  VerbalColors copyWith({
    Color? bg,
    Color? surface,
    Color? raised,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? signal,
  }) =>
      VerbalColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        raised: raised ?? this.raised,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        accent: accent ?? this.accent,
        signal: signal ?? this.signal,
      );

  @override
  VerbalColors lerp(VerbalColors? other, double t) {
    if (other == null) return this;
    return VerbalColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      signal: Color.lerp(signal, other.signal, t)!,
    );
  }
}

/// The lit ground every screen sits on.
///
/// A single named backdrop is what makes a set of screens read as one product
/// rather than a set of pages: a deep base with two soft accent blooms, so the
/// dark never goes flat.
class VerbalBackdrop extends StatelessWidget {
  const VerbalBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(c.bg, c.accent, dark ? 0.07 : 0.035)!,
            c.bg,
            Color.lerp(c.bg, c.signal, dark ? 0.045 : 0.02)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// A frosted panel. Used for anything that should feel like it is floating
/// above the ground rather than printed on it.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VerbalTokens.md),
    this.radius = VerbalTokens.radius,
    this.accent = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = accent ? c.accent : c.surface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: accent
                      ? [
                          c.accent.withValues(alpha: dark ? 0.26 : 0.16),
                          c.accent.withValues(alpha: dark ? 0.10 : 0.07),
                        ]
                      : [
                          tint.withValues(alpha: dark ? 0.55 : 0.90),
                          tint.withValues(alpha: dark ? 0.32 : 0.74),
                        ],
                ),
                border: Border.all(
                  color: accent
                      ? c.accent.withValues(alpha: 0.42)
                      : c.line.withValues(alpha: dark ? 0.55 : 1),
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

extension VerbalTheme on BuildContext {
  VerbalColors get c => Theme.of(this).extension<VerbalColors>()!;
  TextTheme get t => Theme.of(this).textTheme;

  /// True when the user has asked the OS to reduce motion. Long animations are
  /// skipped rather than merely shortened.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? VerbalColors.dark : VerbalColors.light;

  final text = _textTheme(c);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: c.surface,
    ).copyWith(primary: c.accent, error: c.signal),
    textTheme: text,
    extensions: [c],
    dividerColor: c.line,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium,
      iconTheme: IconThemeData(color: c.ink),
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VerbalTokens.radius),
        side: BorderSide(color: c.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: isDark ? VerbalTokens.darkBg : Colors.white,
        minimumSize: const Size.fromHeight(VerbalTokens.tap + 4),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VerbalTokens.radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size.fromHeight(VerbalTokens.tap),
        side: BorderSide(color: c.line),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VerbalTokens.radius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: text.labelLarge,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface.withValues(alpha: 0.72),
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent.withValues(alpha: 0.20),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(text.labelSmall),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.bg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VerbalTokens.radius),
      ),
    ),
  );
}

TextTheme _textTheme(VerbalColors c) {
  // Tight, confident display type; generous, readable body type.
  return TextTheme(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.1,
      letterSpacing: -0.8,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      height: 1.15,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    headlineSmall: TextStyle(
      fontSize: 21,
      height: 1.2,
      letterSpacing: -0.3,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    titleSmall: TextStyle(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: c.ink,
    ),
    bodyLarge: TextStyle(fontSize: 17, height: 1.45, color: c.ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: c.ink),
    bodySmall: TextStyle(fontSize: 13.5, height: 1.45, color: c.muted),
    labelLarge: const TextStyle(
        fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.0,
      color: c.muted,
    ),
    labelSmall: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: c.muted,
    ),
  );
}
