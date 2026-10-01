import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/scenario.dart';

/// Echo — VERBAL's mascot.
///
/// Echo is the person on the other side of the conversation, drawn rather than
/// described. A rounded form with a waveform crest, because the product is
/// voice and the waveform is already its visual language.
///
/// The important part is that Echo is **not decoration**. Its expression is
/// driven by the live [Emotion] the conversation engine is in, so the user can
/// read the room at a glance — calm eyes and an even crest when things are
/// fine, a jagged crest and a hard stare when they have pushed too far. The
/// mascot is a read-out of the state machine.
///
/// Drawn with a painter rather than an asset: it scales to any size, themes
/// itself, and animates without a file pipeline.
class Echo extends StatefulWidget {
  const Echo({
    super.key,
    this.size = 120,
    this.emotion = Emotion.calm,
    this.speaking = false,
    this.listening = false,
  });

  final double size;

  /// Where the conversation currently is. Drives the whole expression.
  final Emotion emotion;

  /// The actor is talking: the crest animates.
  final bool speaking;

  /// The user is talking: Echo leans in and watches.
  final bool listening;

  @override
  State<Echo> createState() => _EchoState();
}

class _EchoState extends State<Echo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion must actually stop the ticker, not merely freeze the value
    // it reads: a controller left repeating keeps the whole frame scheduler
    // busy, which is bad for battery and makes the widget untestable.
    if (context.reduceMotion) {
      _c
        ..stop()
        ..value = 0.25;
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
    // Reduce-motion holds a pose instead; the ticker is stopped in
    // didChangeDependencies.
    final still = context.reduceMotion;

    return Semantics(
      label: 'The other person appears ${widget.emotion.label.toLowerCase()}',
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _EchoPainter(
              t: still ? 0.25 : _c.value,
              emotion: widget.emotion,
              speaking: widget.speaking && !still,
              listening: widget.listening,
              accent: c.accent,
              signal: c.signal,
              ink: c.ink,
              surface: c.surface,
            ),
          ),
        ),
      ),
    );
  }
}

class _EchoPainter extends CustomPainter {
  _EchoPainter({
    required this.t,
    required this.emotion,
    required this.speaking,
    required this.listening,
    required this.accent,
    required this.signal,
    required this.ink,
    required this.surface,
  });

  final double t;
  final Emotion emotion;
  final bool speaking;
  final bool listening;
  final Color accent;
  final Color signal;
  final Color ink;
  final Color surface;

  /// 0 (calm) to 1 (angry).
  double get _heat => emotion.index / (Emotion.values.length - 1);

  Color get _skin => Color.lerp(accent, signal, _heat * 0.85)!;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final breathe = math.sin(t * math.pi * 2) * (w * 0.012);

    // --- body: a soft rounded form, never a sharp edge ---------------------
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.34 + breathe, w * 0.64, h * 0.52),
      Radius.circular(w * 0.30),
    );

    // Glow sits behind, and intensifies with the heat in the room.
    canvas.drawRRect(
      bodyRect.inflate(w * 0.045),
      Paint()
        ..color = _skin.withValues(alpha: 0.14 + _heat * 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.07),
    );

    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_skin, Colors.white, 0.22)!,
            _skin,
            Color.lerp(_skin, Colors.black, 0.24)!,
          ],
        ).createShader(bodyRect.outerRect),
    );

    _paintCrest(canvas, size, breathe);
    _paintFace(canvas, size, bodyRect, breathe);
  }

  /// The waveform crest — the app's own visual language, worn as a feature.
  void _paintCrest(Canvas canvas, Size size, double breathe) {
    final w = size.width;
    final h = size.height;
    const bars = 7;
    final slot = (w * 0.56) / bars;
    final barW = slot * 0.42;
    final baseY = h * 0.34 + breathe;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;

    for (var i = 0; i < bars; i++) {
      // Middle bars are tallest; heat makes the shape jagged rather than even.
      final fromCentre = (i - (bars - 1) / 2).abs() / ((bars - 1) / 2);
      var height = (1 - fromCentre * 0.65) * h * 0.20;

      if (speaking) {
        height *= 0.7 + 0.5 * (math.sin(t * math.pi * 6 + i * 1.1) + 1) / 2;
      }
      // Anger spikes alternate bars: a calm crest is even, an angry one is not.
      height *= 1 + _heat * (i.isEven ? 0.38 : -0.22);

      final x = w * 0.22 + slot * (i + 0.5);
      paint.color = Color.lerp(_skin, Colors.white, 0.35)!
          .withValues(alpha: 0.55 + _heat * 0.35);
      canvas.drawLine(
          Offset(x, baseY), Offset(x, baseY - height.clamp(2.0, h)), paint);
    }
  }

  void _paintFace(Canvas canvas, Size size, RRect body, double breathe) {
    final w = size.width;
    final h = size.height;
    final eyeY = h * 0.52 + breathe;
    final gap = w * 0.15;
    final cx = w / 2;

    // Pupils drift toward the viewer when listening — Echo leans in.
    final look = listening ? w * 0.012 : 0.0;

    // Eyes narrow as the conversation heats up.
    final eyeH = h * (0.085 - _heat * 0.042);
    final eyeW = w * (0.070 - _heat * 0.012);

    final white = Paint()..color = surface;
    final pupil = Paint()..color = ink;

    for (final dx in [-gap, gap]) {
      final rect = Rect.fromCenter(
        center: Offset(cx + dx, eyeY),
        width: eyeW * 2,
        height: eyeH * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(eyeW)),
        white,
      );
      canvas.drawCircle(
        Offset(cx + dx + look, eyeY + look * 0.5),
        eyeW * 0.52,
        pupil,
      );
      // Catchlight keeps it alive rather than blank.
      canvas.drawCircle(
        Offset(cx + dx + look + eyeW * 0.2, eyeY - eyeH * 0.35),
        eyeW * 0.17,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    // Brows appear only under pressure, and angle inward.
    if (_heat > 0.25) {
      final brow = Paint()
        ..color = ink.withValues(alpha: (_heat - 0.25) * 1.6)
        ..strokeWidth = h * 0.016
        ..strokeCap = StrokeCap.round;
      final tilt = _heat * h * 0.030;
      for (final dx in [-gap, gap]) {
        final inner =
            Offset(cx + dx + (dx < 0 ? eyeW : -eyeW), eyeY - eyeH * 1.5 + tilt);
        final outer =
            Offset(cx + dx - (dx < 0 ? eyeW : -eyeW), eyeY - eyeH * 1.9);
        canvas.drawLine(inner, outer, brow);
      }
    }

    // Mouth: a soft smile when calm, flattening and turning down as it heats.
    final mouthW = w * 0.14;
    final mouthY = eyeY + h * 0.14;
    final curve = (0.5 - _heat) * h * 0.055;
    final path = Path()
      ..moveTo(cx - mouthW, mouthY)
      ..quadraticBezierTo(cx, mouthY + curve * 2, cx + mouthW, mouthY);

    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.018
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EchoPainter old) =>
      old.t != t ||
      old.emotion != emotion ||
      old.speaking != speaking ||
      old.listening != listening ||
      old.accent != accent;
}
