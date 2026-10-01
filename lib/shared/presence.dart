import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../domain/scenario.dart';
import '../domain/session.dart';

/// What the face is doing.
enum Expression {
  /// At rest: eyes up and to the right.
  neutral,

  /// The user is speaking: eyes to the centre, listening. Animated.
  attentive,

  /// Taken aback — the face while it thinks, and under pressure.
  surprised,

  /// Answering, happily.
  excited;

  /// The face the engine's state deserves: at rest nearly always, and
  /// attentive while the user is speaking. The rest of the sheet is there
  /// for when a moment earns it.
  static Expression of({required Emotion emotion, VoicePhase? phase}) =>
      phase == VoicePhase.listening
          ? Expression.attentive
          : Expression.neutral;

  String get asset => switch (this) {
        Expression.neutral => 'assets/mascot/neutre.png',
        Expression.attentive => 'assets/mascot/attentif.gif',
        Expression.surprised => 'assets/mascot/surpris.png',
        Expression.excited => 'assets/mascot/excite.png',
      };
}

/// The other person: a small white cloud with two eyes.
///
/// Drawn artwork, not a painter — four faces are enough to feel alive, and
/// the drawn ones are better than anything generated at runtime. This is
/// VERBAL's identity; it is the only thing on screen that is not type or
/// glass.
class Presence extends StatefulWidget {
  const Presence({
    super.key,
    this.size = 150,
    this.expression = Expression.neutral,
    // Kept so call sites read the same whichever face is drawn.
    this.heat = 0,
    this.speaking = false,
    this.listening = false,
    this.level = 0,
  });

  final double size;
  final Expression expression;
  final double heat;
  final bool speaking;
  final bool listening;
  final double level;

  @override
  State<Presence> createState() => _PresenceState();
}

class _PresenceState extends State<Presence>
    with SingleTickerProviderStateMixin {
  /// Blink cycle. Long enough not to read as a tic.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
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
    final still = context.reduceMotion;
    // Reduce-motion gets the still neutral face rather than the animated one.
    final face = widget.expression == Expression.attentive && still
        ? Expression.neutral
        : widget.expression;
    final image = Image.asset(
      face.asset,
      key: ValueKey(face),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
    return Semantics(
      label: 'The other person looks ${face.name}',
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : const Duration(milliseconds: 220),
        child: face != Expression.neutral || still
            ? image
            : AnimatedBuilder(
                animation: _c,
                builder: (context, child) => CustomPaint(
                  foregroundPainter: _Blink(_c.value),
                  child: child,
                ),
                child: image,
              ),
      ),
    );
  }
}

/// Closes the resting face's eyes for a moment, once per cycle.
///
/// The artwork is a white cloud, so a white lid drawn over each eye is
/// invisible against the body and the eye simply disappears from the top
/// down. Eye boxes are measured from the artwork, as fractions of it.
class _Blink extends CustomPainter {
  const _Blink(this.t);

  final double t;

  static const _body = Color(0xFFF5F5F3);
  static const _eyes = [
    Rect.fromLTRB(0.496, 0.316, 0.609, 0.461),
    Rect.fromLTRB(0.648, 0.270, 0.746, 0.410),
  ];

  /// 0 open → 1 shut, during a 140 ms window at the start of the cycle.
  double get _shut {
    const window = 0.14 / 4.2;
    if (t > window) return 0;
    return math.sin(math.pi * t / window);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shut = _shut;
    if (shut == 0) return;
    final paint = Paint()..color = _body;
    for (final e in _eyes) {
      final box = Rect.fromLTRB(e.left * size.width, e.top * size.height,
          e.right * size.width, e.bottom * size.height);
      final lid = Rect.fromLTWH(
          box.left - 1, box.top - 1, box.width + 2, box.height * shut + 1);
      canvas.drawRRect(
          RRect.fromRectAndRadius(lid, Radius.circular(box.width / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(_Blink old) => old.t != t;
}
