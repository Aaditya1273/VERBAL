import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The other person's presence: a lit orb, not a face.
///
/// A drawn face reads as a toy. A light reads as a presence — and a light can
/// still say everything the session needs it to: it breathes while the other
/// person listens, swells as they speak, and runs hot as the pressure climbs.
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

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.width * 0.28;
    final tone = Color.lerp(accent, signal, heat)!;

    // Speaking swells quickly; listening breathes slowly; idle barely moves.
    final wave = math.sin(t * math.pi * 2);
    final swell = speaking
        ? 0.10 * (math.sin(t * math.pi * 6) + 1) / 2
        : listening
            ? 0.05 * (wave + 1) / 2
            : 0.02 * (wave + 1) / 2;

    // Halo: a wide soft glow, hotter and wider under pressure.
    canvas.drawCircle(
      centre,
      r * (1.55 + swell * 2 + heat * 0.25),
      Paint()
        ..color = tone.withValues(alpha: 0.22 + heat * 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
    );

    // Core: lit from the top-left, like everything else on the ground.
    final core = Rect.fromCircle(center: centre, radius: r * (1 + swell));
    canvas.drawCircle(
      centre,
      core.width / 2,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.55),
          radius: 0.95,
          colors: [
            Color.lerp(tone, Colors.white, 0.72)!,
            Color.lerp(tone, Colors.white, 0.18)!,
            tone,
            Color.lerp(tone, bg, 0.45)!,
          ],
          stops: const [0.0, 0.28, 0.72, 1.0],
        ).createShader(core),
    );

    // Ring: a hairline that catches the light on the top edge.
    canvas.drawCircle(
      centre,
      core.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: math.pi * 3,
          colors: [
            Colors.white.withValues(alpha: 0.65),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.65),
          ],
        ).createShader(core),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.heat != heat ||
      old.speaking != speaking ||
      old.listening != listening ||
      old.accent != accent;
}
