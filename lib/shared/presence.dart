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

  /// The face the engine's state deserves. While the user speaks the other
  /// person is attentive, whatever the mood; while it thinks it is surprised;
  /// once it answers, the mood decides.
  static Expression of({required Emotion emotion, VoicePhase? phase}) {
    switch (phase) {
      case VoicePhase.listening:
        return Expression.attentive;
      case VoicePhase.processing:
        return Expression.surprised;
      case VoicePhase.speaking:
        return emotion.index >= Emotion.frustrated.index
            ? Expression.surprised
            : Expression.excited;
      default:
        return Expression.neutral;
    }
  }

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
class Presence extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // Reduce-motion gets the still neutral face rather than the animated one.
    final face = expression == Expression.attentive && context.reduceMotion
        ? Expression.neutral
        : expression;
    return Semantics(
      label: 'The other person looks ${face.name}',
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        child: Image.asset(
          face.asset,
          key: ValueKey(face),
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
