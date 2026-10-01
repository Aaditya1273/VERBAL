import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
/// Not a flat gradient: a light source. Teal pours in from the top and falls
/// off into the base, a quieter lamp of the same hue sits low, and
/// a pool of shade on the left gives the headline darker ground to sit on.
/// Film grain keeps the large gradients from banding and gives the glass
/// something to catch. One ground, every screen — that is what makes a set of
/// screens read as one product.
class VerbalBackdrop extends StatefulWidget {
  const VerbalBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<VerbalBackdrop> createState() => _VerbalBackdropState();
}

class _VerbalBackdropState extends State<VerbalBackdrop> {
  static ui.Image? _grain;
  static Future<ui.Image>? _loading;

  /// 128px of tiled noise, generated once per process. Seeded so every launch
  /// looks the same.
  static Future<ui.Image> _makeGrain() {
    const side = 128;
    final rnd = math.Random(7);
    final px = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i++) {
      // Premultiplied: a white speck at alpha a is (a, a, a, a), a black one
      // is (0, 0, 0, a). Unpremultiplied white would paint opaque static.
      final a = rnd.nextInt(14);
      final v = rnd.nextBool() ? a : 0;
      px[i * 4] = v;
      px[i * 4 + 1] = v;
      px[i * 4 + 2] = v;
      px[i * 4 + 3] = a;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        px, side, side, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  @override
  void initState() {
    super.initState();
    if (_grain == null) {
      (_loading ??= _makeGrain()).then((img) {
        _grain = img;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CustomPaint(
      painter: _LitGround(
        bg: c.bg,
        accent: c.accent,
        signal: c.signal,
        grain: _grain,
      ),
      child: widget.child,
    );
  }
}

class _LitGround extends CustomPainter {
  const _LitGround({
    required this.bg,
    required this.accent,
    required this.signal,
    required this.grain,
  });

  final Color bg;
  final Color accent;
  final Color signal;
  final ui.Image? grain;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // Light pouring from the top, falling into the base by mid-screen.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(accent, Colors.white, 0.18)!,
            accent,
            Color.lerp(accent, bg, 0.55)!,
            bg,
            bg,
          ],
          stops: const [0.0, 0.10, 0.30, 0.58, 1.0],
        ).createShader(rect),
    );

    void bloom(Offset centre, double radius, Color colour) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [colour, colour.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    // The hot spot of the lamp, top right.
    bloom(Offset(w * 0.72, h * 0.04), w * 0.85,
        Color.lerp(accent, Colors.white, 0.45)!.withValues(alpha: 0.55));
    // Shade pooling from the left, so the headline sits on darker ground.
    bloom(Offset(w * 0.0, h * 0.46), w * 0.95, bg.withValues(alpha: 0.6));
    // A second, quieter lamp low down so the bottom of a long page never goes
    // flat black. Same hue as the top: one light, one product.
    bloom(Offset(w * 0.5, h * 1.12), w * 0.95, accent.withValues(alpha: 0.22));

    final g = grain;
    if (g != null) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ImageShader(
            g,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.identity().storage,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_LitGround old) =>
      old.bg != bg ||
      old.accent != accent ||
      old.signal != signal ||
      old.grain != grain;
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
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
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
                          c.accent.withValues(alpha: dark ? 0.30 : 0.16),
                          c.accent.withValues(alpha: dark ? 0.10 : 0.07),
                        ]
                      : [
                          tint.withValues(alpha: dark ? 0.34 : 0.90),
                          tint.withValues(alpha: dark ? 0.16 : 0.74),
                        ],
                ),
                border: Border.all(
                  color: accent
                      ? c.accent.withValues(alpha: 0.42)
                      : c.ink.withValues(alpha: dark ? 0.10 : 0.08),
                ),
              ),
              child: Stack(
                children: [
                  // The hairline that catches the light along the top edge —
                  // the one detail that separates glass from a grey card.
                  Positioned(
                    top: 0,
                    left: radius * 0.6,
                    right: radius * 0.6,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          c.ink.withValues(alpha: 0),
                          c.ink.withValues(alpha: dark ? 0.55 : 0.25),
                          c.ink.withValues(alpha: 0),
                        ]),
                      ),
                    ),
                  ),
                  Padding(padding: padding, child: child),
                ],
              ),
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
        minimumSize: const Size.fromHeight(VerbalTokens.tap + 8),
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size.fromHeight(VerbalTokens.tap),
        side: BorderSide(color: c.ink.withValues(alpha: 0.18)),
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
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
  // Large statements are light and tight — weight 300 reads as confidence,
  // bold reads as shouting. Body type stays generous and readable.
  return TextTheme(
    displaySmall: TextStyle(
      fontSize: 40,
      height: 1.04,
      letterSpacing: -1.6,
      fontWeight: FontWeight.w300,
      color: c.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      height: 1.1,
      letterSpacing: -1.0,
      fontWeight: FontWeight.w300,
      color: c.ink,
    ),
    headlineSmall: TextStyle(
      fontSize: 23,
      height: 1.22,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w400,
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
