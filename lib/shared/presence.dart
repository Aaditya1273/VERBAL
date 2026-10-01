import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The other person: a white ball, two eyes, a halo of colour.
///
/// The interface is monochrome on purpose, so this is the only colour on any
/// screen — the eye always knows where the other person is. It does not bob
/// about; what makes it alive is the halo, which beats with the voice, and
/// the eyes, which glance, blink, open wide to listen and narrow under
/// pressure.
class Presence extends StatefulWidget {
  const Presence({
    super.key,
    this.size = 150,
    this.heat = 0,
    this.speaking = false,
    this.listening = false,
    this.level = 0,
  });

  final double size;

  /// 0 calm → 1 hostile. Drives the halo's warmth and the eyes' squint.
  final double heat;

  final bool speaking;
  final bool listening;

  /// 0..1 microphone level while listening, so the halo beats with the user.
  final double level;

  @override
  State<Presence> createState() => _PresenceState();
}

class _PresenceState extends State<Presence>
    with SingleTickerProviderStateMixin {
  /// One loop is six seconds: long enough that glances and blinks do not
  /// visibly repeat, short enough that the halo's turn never jumps.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
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
            painter: _MascotPainter(
              seconds: (still ? 0.5 : _c.value) * 6,
              heat: widget.heat.clamp(0.0, 1.0),
              speaking: widget.speaking && !still,
              listening: widget.listening,
              level: widget.level.clamp(0.0, 1.0),
              ink: c.ink,
              bg: c.bg,
              signal: c.signal,
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.seconds,
    required this.heat,
    required this.speaking,
    required this.listening,
    required this.level,
    required this.ink,
    required this.bg,
    required this.signal,
  });

  /// Time within the six-second loop.
  final double seconds;
  final double heat;
  final bool speaking;
  final bool listening;
  final double level;
  final Color ink;
  final Color bg;
  final Color signal;

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

  /// Speech has a rhythm — syllables inside phrases. Two sines, one fast and
  /// one slow, rectified, read as talking without any audio analysis.
  double get _beat {
    final syllable = math.sin(seconds * math.pi * 2 * 4.3);
    final phrase = math.sin(seconds * math.pi * 2 * 0.9 + 0.7);
    return math.max(0.0, syllable * phrase);
  }

  /// How alive the halo is right now, 0..1.
  double get _energy {
    if (speaking) return 0.3 + 0.7 * _beat;
    if (listening) return 0.25 + 0.75 * level;
    return 0.12 + 0.06 * (math.sin(seconds * math.pi / 3) + 1) / 2;
  }

  /// A small deterministic number per glance, so the eyes wander rather
  /// than drift on a sine.
  static double _noise(int seed, int salt) {
    final x = math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453;
    return (x - x.floorToDouble()) * 2 - 1;
  }

  /// Where the eyes are looking, as a fraction of the ball's radius.
  Offset get _gaze {
    // Listening: straight at the user, held still.
    if (listening) return Offset.zero;
    const glance = 2.4;
    final seg = (seconds / glance).floor();
    final f = (seconds - seg * glance) / glance;
    final from = Offset(_noise(seg, 1), _noise(seg, 2));
    final to = Offset(_noise(seg + 1, 1), _noise(seg + 1, 2));
    // Move during the first fifth of each glance, then hold.
    final k = Curves.easeInOut.transform((f / 0.2).clamp(0.0, 1.0));
    final at = Offset.lerp(from, to, k)!;
    return at * (speaking ? 0.05 : 0.08);
  }

  /// 1 open, 0 shut.
  double get _lid {
    const every = 3.7;
    const blink = 0.14;
    final phase = seconds % every;
    if (phase < blink) return 1 - math.sin(math.pi * phase / blink);
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.width * 0.30;
    final energy = _energy;

    // 1. Halo: a ring of spectrum, blurred wide, turning slowly. It beats
    //    with the voice, and under pressure bleeds toward the signal colour.
    final haloRect = Rect.fromCircle(center: centre, radius: r * 1.6);
    canvas.drawCircle(
      centre,
      r * (1.16 + 0.10 * energy + heat * 0.14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * (0.40 + 0.35 * energy + heat * 0.2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.40)
        ..shader = SweepGradient(
          transform: GradientRotation(seconds * math.pi / 3),
          colors: [
            for (final c in _spectrum)
              Color.lerp(c, signal, heat * 0.8)!
                  .withValues(alpha: 0.30 + 0.65 * energy),
          ],
        ).createShader(haloRect),
    );

    // 2. Body: white, shaded softly toward the bottom-right so it reads as a
    //    ball rather than a disc. It stays put.
    final body = Rect.fromCircle(center: centre, radius: r);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.15,
          colors: [
            ink,
            ink,
            Color.lerp(ink, bg, 0.22)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(body),
    );

    // 3. Eyes: two capsules, top-right, tilted. They glance, blink, open
    //    wide to listen and narrow to a squint under pressure. Hot, the
    //    inner ends drop — a brow without drawing one.
    final gaze = _gaze * r;
    final open = _lid *
        (listening ? 1.12 : 1.0) *
        (1 - 0.55 * heat) *
        (speaking ? 1 - 0.08 * _beat : 1);
    final eyeH = math.max(r * 0.06, r * 0.40 * open);
    final eyeW = r * 0.15;
    final gap = r * 0.26 * (1 - 0.15 * heat);
    final eye = Paint()..color = bg;

    canvas.save();
    canvas.translate(
        centre.dx + r * 0.22 + gaze.dx, centre.dy - r * 0.22 + gaze.dy);
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.translate(side * gap / 2, side > 0 ? -r * 0.05 : 0);
      canvas.rotate(-0.25 + side * 0.35 * heat);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: eyeW, height: eyeH),
          Radius.circular(eyeW),
        ),
        eye,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.seconds != seconds ||
      old.heat != heat ||
      old.speaking != speaking ||
      old.listening != listening ||
      old.level != level ||
      old.ink != ink;
}
