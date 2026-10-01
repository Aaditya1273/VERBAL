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

  /// The light inside: four coloured plumes that drift around the centre.
  /// Cool when calm, bleeding to warm as the pressure climbs.
  List<Color> get _plumes => [
        Color.lerp(const Color(0xFF2EE6C5), const Color(0xFFFF7A1A), heat)!,
        Color.lerp(const Color(0xFF38BDF8), const Color(0xFFFF3D3D), heat)!,
        Color.lerp(const Color(0xFF8BF0D8), const Color(0xFFFFB020), heat)!,
        Color.lerp(accent, signal, heat)!,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final tone = Color.lerp(accent, signal, heat)!;

    // Speaking swells quickly; listening breathes slowly; idle barely moves.
    final wave = math.sin(t * math.pi * 2);
    final swell = speaking
        ? 0.07 * (math.sin(t * math.pi * 6) + 1) / 2
        : listening
            ? 0.04 * (wave + 1) / 2
            : 0.015 * (wave + 1) / 2;
    final r = size.width * 0.30 * (1 + swell);
    final sphere = Rect.fromCircle(center: centre, radius: r);

    // 1. Halo: wide, soft, hotter under pressure.
    canvas.drawCircle(
      centre,
      r * (1.45 + heat * 0.25),
      Paint()
        ..color = tone.withValues(alpha: 0.26 + heat * 0.14)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );

    // 2. The glass body: dark, so the plumes read as light inside it.
    canvas.drawCircle(
      centre,
      r,
      Paint()..color = Color.lerp(bg, tone, 0.18)!,
    );

    // 3. Plumes, additive, clipped to the sphere. The whole point of the orb
    //    is that the light moves; a still sphere is a bead.
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    canvas.saveLayer(sphere, Paint());
    final speed = speaking ? 3.0 : listening ? 1.4 : 1.0;
    final plumes = _plumes;
    for (var i = 0; i < plumes.length; i++) {
      final phase = t * math.pi * 2 * speed + i * (math.pi * 2 / plumes.length);
      final orbit = r * (0.38 + 0.12 * math.sin(phase * 0.7 + i));
      final at = centre +
          Offset(math.cos(phase) * orbit, math.sin(phase * 1.3) * orbit);
      final blobR = r * (0.62 + 0.14 * math.sin(phase * 1.1 + i * 2));
      canvas.drawCircle(
        at,
        blobR,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blobR * 0.55)
          ..shader = RadialGradient(
            colors: [
              plumes[i].withValues(alpha: 0.85),
              plumes[i].withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: blobR)),
      );
    }
    canvas.restore();

    // 4. Fresnel: the edge of a sphere is darker and denser than its centre.
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            bg.withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.72, 1.0],
        ).createShader(sphere),
    );

    // 5. Specular: one soft highlight, top-left, where the light is.
    final hl = Rect.fromCenter(
      center: centre + Offset(-r * 0.36, -r * 0.46),
      width: r * 0.78,
      height: r * 0.44,
    );
    canvas.drawOval(
      hl,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.42)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14),
    );
    canvas.restore();

    // 6. Rim: a hairline that catches the light on the top edge.
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
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.75),
          ],
        ).createShader(sphere),
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
