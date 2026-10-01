import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/scenario.dart';
import '../domain/session.dart';

/// What the face is doing. The eyes are the whole vocabulary.
enum Expression {
  neutral,
  attentive,
  thinking,
  surprised,
  happy,
  sad,
  suspicious,
  unimpressed,
  angry;

  /// The face the engine's state deserves. Phase first — a listening face
  /// is a listening face whatever the mood — then the emotion.
  static Expression of({required Emotion emotion, VoicePhase? phase}) {
    switch (phase) {
      case VoicePhase.listening:
        return Expression.attentive;
      case VoicePhase.processing:
        return Expression.thinking;
      default:
        break;
    }
    return switch (emotion) {
      Emotion.calm => Expression.neutral,
      Emotion.guarded => Expression.suspicious,
      Emotion.defensive => Expression.unimpressed,
      Emotion.frustrated => Expression.sad,
      Emotion.upset => Expression.angry,
      Emotion.angry => Expression.angry,
    };
  }
}

/// The other person: a solid black ball, two white eyes, and a life of colour
/// that comes out from behind it when there is a voice.
///
/// This is VERBAL's identity, and the rule is simple: the interface is
/// monochrome, and the only colour anywhere is the mascot's life. At rest the
/// ball is just a ball. When the other person speaks, or the user does,
/// spectrum light emerges from behind its edge and reaches outward with the
/// voice, then settles back inside when the voice stops — so you can see the
/// conversation breathing. The body never moves and is never transparent. The
/// eyes carry the expression: they glance, blink, and take the shape of the
/// mood the conversation engine is in.
class Presence extends StatefulWidget {
  const Presence({
    super.key,
    this.size = 150,
    this.expression = Expression.neutral,
    this.heat = 0,
    this.speaking = false,
    this.listening = false,
    this.level = 0,
  });

  final double size;
  final Expression expression;

  /// 0 calm → 1 hostile. Warms the light.
  final double heat;

  final bool speaking;
  final bool listening;

  /// 0..1 microphone level while listening, so the light follows the user.
  final double level;

  @override
  State<Presence> createState() => _PresenceState();
}

class _PresenceState extends State<Presence>
    with SingleTickerProviderStateMixin {
  /// One loop is six seconds: long enough that glances and blinks do not
  /// visibly repeat, short enough that the light's turn never jumps.
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
              : 'The other person looks ${widget.expression.name}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _MascotPainter(
              seconds: (still ? 0.5 : _c.value) * 6,
              expression: widget.expression,
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

/// One eye: a rounded capsule, or an arc for a smile.
class _Eye {
  const _Eye({
    this.w = 0.15,
    this.h = 0.40,
    this.tilt = -0.25,
    this.dy = 0,
    this.arc = false,
  });

  /// Fractions of the body radius.
  final double w;
  final double h;

  /// Radians; negative leans the top to the right.
  final double tilt;
  final double dy;

  /// Drawn as an upward arc (a closed, happy eye) instead of a capsule.
  final bool arc;
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({
    required this.seconds,
    required this.expression,
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
  final Expression expression;
  final double heat;
  final bool speaking;
  final bool listening;
  final double level;
  final Color ink;
  final Color bg;
  final Color signal;

  /// Soft spectrum, never neon.
  static const _spectrum = [
    Color(0xFFFF8E8E),
    Color(0xFFFFC98A),
    Color(0xFFBDF2A1),
    Color(0xFF8ADFFF),
    Color(0xFFB79CFF),
    Color(0xFFFF9BD8),
    Color(0xFFFF8E8E),
  ];

  /// Speech has a shape — phrases, with syllables inside them. Two slow
  /// sines, blended rather than rectified, so the light swells and settles
  /// instead of flickering.
  double get _voice {
    final phrase = (math.sin(seconds * math.pi * 2 * 0.55) + 1) / 2;
    final syllable = (math.sin(seconds * math.pi * 2 * 2.1 + 1.0) + 1) / 2;
    return 0.65 * phrase + 0.35 * syllable;
  }

  /// How far the light has come out, 0 (hidden behind the ball) to 1.
  double get _energy {
    if (speaking) return 0.30 + 0.70 * _voice;
    if (listening) return 0.25 + 0.75 * level;
    return 0;
  }

  /// A small deterministic number per glance, so the eyes wander rather
  /// than drift on a sine.
  static double _noise(int seed, int salt) {
    final x = math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453;
    return (x - x.floorToDouble()) * 2 - 1;
  }

  /// Where the eyes are looking, as a fraction of the body radius.
  Offset get _gaze {
    if (listening) return Offset.zero; // straight at the user, held still
    const glance = 2.4;
    final seg = (seconds / glance).floor();
    final f = (seconds - seg * glance) / glance;
    final from = Offset(_noise(seg, 1), _noise(seg, 2));
    final to = Offset(_noise(seg + 1, 1), _noise(seg + 1, 2));
    final k = Curves.easeInOut.transform((f / 0.2).clamp(0.0, 1.0));
    return Offset.lerp(from, to, k)! * (speaking ? 0.05 : 0.08);
  }

  /// 1 open, 0 shut.
  double get _lid {
    const every = 3.7;
    const blink = 0.14;
    final phase = seconds % every;
    if (phase < blink) return 1 - math.sin(math.pi * phase / blink);
    return 1;
  }

  /// The eye shapes for each expression, left then right. Drawn from the
  /// same vocabulary as the reference sheet: capsules that lean, widen,
  /// narrow or close into an arc.
  List<_Eye> get _eyes => switch (expression) {
        Expression.neutral => const [_Eye(), _Eye(dy: -0.05)],
        Expression.attentive => const [
            _Eye(h: 0.48, tilt: 0),
            _Eye(h: 0.48, tilt: 0),
          ],
        Expression.thinking => const [
            _Eye(w: 0.18, h: 0.18, tilt: 0, dy: 0.04),
            _Eye(w: 0.26, h: 0.26, tilt: 0, dy: -0.08),
          ],
        Expression.surprised => const [
            _Eye(w: 0.30, h: 0.30, tilt: 0),
            _Eye(w: 0.30, h: 0.30, tilt: 0),
          ],
        Expression.happy => const [
            _Eye(w: 0.28, h: 0.10, arc: true),
            _Eye(w: 0.28, h: 0.10, arc: true),
          ],
        Expression.sad => const [
            _Eye(h: 0.30, tilt: 0.45, dy: 0.04),
            _Eye(h: 0.30, tilt: -0.45, dy: 0.04),
          ],
        Expression.suspicious => const [
            _Eye(h: 0.22, tilt: 0),
            _Eye(h: 0.14, tilt: 0, dy: 0.02),
          ],
        Expression.unimpressed => const [
            _Eye(w: 0.26, h: 0.10, tilt: 0),
            _Eye(w: 0.26, h: 0.10, tilt: 0),
          ],
        Expression.angry => const [
            _Eye(h: 0.30, tilt: -0.55),
            _Eye(h: 0.30, tilt: 0.55),
          ],
      };

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.width * 0.30;
    final energy = _energy;
    final body = Rect.fromCircle(center: centre, radius: r);

    // 1. The life, behind the ball. A disc of spectrum whose radius is the
    //    voice: at rest it is smaller than the ball and completely hidden;
    //    as the voice rises it comes out past the edge and reaches outward.
    if (energy > 0) {
      final reach = r * (0.9 + 0.75 * energy);
      canvas.drawCircle(
        centre,
        reach,
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22)
          ..shader = SweepGradient(
            transform: GradientRotation(seconds * math.pi / 3),
            colors: [
              for (final c in _spectrum)
                Color.lerp(c, signal, heat * 0.75)!.withValues(alpha: 0.95),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: reach)),
      );
    }

    // 2. The ball: solid, lifted from the ground, lit from the top left, a
    //    hairline of light on its top edge so it reads on a black screen.
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.65),
          radius: 1.3,
          colors: [
            Color.lerp(bg, ink, 0.20)!,
            Color.lerp(bg, ink, 0.07)!,
            Color.lerp(bg, ink, 0.04)!,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(body),
    );
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
            ink.withValues(alpha: 0.50),
            ink.withValues(alpha: 0.06),
            ink.withValues(alpha: 0.50),
          ],
        ).createShader(body),
    );

    // 3. Eyes, in white, last — so they read over the light.
    final gaze = _gaze * r;
    final lid = _lid;
    final eyes = _eyes;
    final gap = r * 0.30;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.09;

    canvas.save();
    canvas.translate(centre.dx + gaze.dx, centre.dy - r * 0.10 + gaze.dy);
    for (var i = 0; i < 2; i++) {
      final e = eyes[i];
      final side = i == 0 ? -1 : 1;
      canvas.save();
      canvas.translate(side * gap, e.dy * r);
      canvas.rotate(e.tilt);
      if (e.arc) {
        final w = e.w * r;
        canvas.drawPath(
          Path()
            ..moveTo(-w / 2, 0)
            ..quadraticBezierTo(0, -e.h * r * 2.2, w / 2, 0),
          stroke,
        );
      } else {
        final h = math.max(r * 0.06, e.h * r * lid);
        final w = math.min(e.w * r, h);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Radius.circular(w),
          ),
          paint,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.seconds != seconds ||
      old.expression != expression ||
      old.heat != heat ||
      old.speaking != speaking ||
      old.listening != listening ||
      old.level != level ||
      old.ink != ink;
}
