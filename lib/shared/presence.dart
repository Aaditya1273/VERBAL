import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The other person: one black ball, two white marks, a halo of colour.
///
/// The interface is monochrome on purpose, so this is the only colour on any
/// screen — the eye always knows where the other person is. It breathes while
/// they listen, swells as they speak, and as the pressure climbs the halo
/// runs warm and the two marks narrow to a squint.
class Presence extends StatefulWidget {
  const Presence({
    super.key,
    this.size = 150,
    this.heat = 0,
    this.speaking = false,
    this.listening = false,
  });

  final double size;

  /// 0 calm → 1 hostile. Drives the colour.
  final double heat;

  final bool speaking;
  final bool listening;

  @override
  State<Presence> createState() => _PresenceState();
}

class _PresenceState extends State<Presence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion must stop the ticker, not freeze the value it reads.
    if (context.reduceMotion) {
      _c
        ..stop()
        ..value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final still = context.reduceMotion;
    return Semantics(
      label: widget.speaking
          ? 'The other person is speaking'
          : widget.listening
              ? 'The other person is listening'
              : 'The other person',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _OrbPainter(
              t: still ? 0.5 : _c.value,
              heat: widget.heat.clamp(0.0, 1.0),
              speaking: widget.speaking && !still,
              listening: widget.listening,
              accent: c.accent,
              signal: c.signal,
              bg: c.bg,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.t,
    required this.heat,
    required this.speaking,
    required this.listening,
    required this.accent,
    required this.signal,
    required this.bg,
  });

  final double t;
  final double heat;
  final bool speaking;
  final bool listening;
  final Color accent;
  final Color signal;
  final Color bg;

  /// Soft spectrum, never neon: the halo is colour, not a warning light.
  static const _spectrum = [
    Color(0xFFFF8E8E),
    Color(0xFFFFC98A),
    Color(0xFFBDF2A1),
    Color(0xFF8ADFFF),
    Color(0xFFB79CFF),
    Color(0xFFFF9BD8),
    Color(0xFFFF8E8E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);

    // Speaking swells quickly; listening breathes slowly; idle barely moves.
    final wave = math.sin(t * math.pi * 2);
    final swell = speaking
        ? 0.08 * (math.sin(t * math.pi * 6) + 1) / 2
        : listening
            ? 0.045 * (wave + 1) / 2
            : 0.02 * (wave + 1) / 2;
    final r = size.width * 0.30 * (1 + swell);

    // 1. Halo: a ring of spectrum, blurred wide, turning slowly. Under
    //    pressure it bleeds toward the signal colour and reaches further.
    final halo = Rect.fromCircle(center: centre, radius: r * 1.5);
    canvas.drawCircle(
      centre,
      r * (1.18 + heat * 0.18),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * (0.55 + heat * 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.42)
        ..shader = SweepGradient(
          transform: GradientRotation(t * math.pi * 2),
          colors: [
            for (final c in _spectrum)
              Color.lerp(c, signal, heat * 0.8)!
                  .withValues(alpha: 0.55 + heat * 0.25),
          ],
        ).createShader(halo),
    );

    // 2. Body: near-black, lit faintly from the top-left so it reads as a
    //    sphere against a black ground.
    final body = Rect.fromCircle(center: centre, radius: r);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.5, -0.6),
          radius: 1.1,
          colors: [
            Color.lerp(bg, accent, 0.26)!,
            Color.lerp(bg, accent, 0.08)!,
            bg,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(body),
    );
    // Rim light along the top edge.
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: math.pi * 3,
          colors: [
            accent.withValues(alpha: 0.55),
            accent.withValues(alpha: 0.04),
            accent.withValues(alpha: 0.55),
          ],
        ).createShader(body),
    );

    // 3. The two marks: highlights that double as eyes. Calm, they are tall
    //    and open; under pressure they narrow to a squint.
    final markH = r * (0.36 - heat * 0.18);
    final markW = r * 0.14;
    final mark = Paint()..color = accent;
    canvas.save();
    canvas.translate(centre.dx + r * 0.30, centre.dy - r * 0.30);
    canvas.rotate(-0.32);
    for (final dx in [-r * 0.22, r * 0.22]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(dx, dx > 0 ? -r * 0.06 : 0),
              width: markW,
              height: markH),
          Radius.circular(markW),
        ),
        mark,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.heat != heat ||
      old.speaking != speaking ||
      old.listening != listening ||
      old.accent != accent;
}
