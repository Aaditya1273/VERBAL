/// Difficulty is not a label. Each level carries a behavioural profile that the
/// [ConversationEngine] uses to schedule objections, escalate emotion and decide
/// when (or whether) the AI actor is allowed to concede.
enum Difficulty { easy, moderate, hard, expert, boss }

extension DifficultyLabel on Difficulty {
  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.moderate => 'Moderate',
        Difficulty.hard => 'Hard',
        Difficulty.expert => 'Expert',
        Difficulty.boss => 'Boss',
      };

  String get blurb => switch (this) {
        Difficulty.easy => 'Low resistance. Good for a first run.',
        Difficulty.moderate => 'Basic disagreement and pushback.',
        Difficulty.hard => 'Emotional reactions and multiple objections.',
        Difficulty.expert => 'Complex escalation and competing objections.',
        Difficulty.boss => 'Sustained high-pressure simulation.',
      };

  DifficultyProfile get profile => DifficultyProfile.of(this);
}

/// The concrete knobs difficulty turns.
class DifficultyProfile {
  const DifficultyProfile({
    required this.difficulty,
    required this.resistance,
    required this.volatility,
    required this.objectionCount,
    required this.objectionCadence,
    required this.wellHandledToConcede,
    required this.escalationSpeed,
    required this.minTurns,
    required this.maxTurns,
    required this.allowsEarlyResolution,
  });

  final Difficulty difficulty;

  /// 0..1 — how hard the actor holds their position.
  final double resistance;

  /// 0..1 — how strongly emotion colours the actor's replies.
  final double volatility;

  /// How many distinct objections the actor will raise in a session.
  final int objectionCount;

  /// Raise a new objection every N user turns.
  final int objectionCadence;

  /// How many objections the user must handle well before the actor softens.
  final int wellHandledToConcede;

  /// Escalation stages advanced per poorly-handled turn.
  final int escalationSpeed;

  /// The session cannot resolve before this many user turns.
  final int minTurns;

  /// Hard ceiling; the engine closes the conversation here.
  final int maxTurns;

  /// Whether a single strong turn can resolve the conversation early.
  final bool allowsEarlyResolution;

  static DifficultyProfile of(Difficulty d) => switch (d) {
        Difficulty.easy => const DifficultyProfile(
            difficulty: Difficulty.easy,
            resistance: 0.2,
            volatility: 0.15,
            objectionCount: 1,
            objectionCadence: 3,
            wellHandledToConcede: 1,
            escalationSpeed: 0,
            minTurns: 3,
            maxTurns: 10,
            allowsEarlyResolution: true,
          ),
        Difficulty.moderate => const DifficultyProfile(
            difficulty: Difficulty.moderate,
            resistance: 0.4,
            volatility: 0.35,
            objectionCount: 2,
            objectionCadence: 2,
            wellHandledToConcede: 2,
            escalationSpeed: 1,
            minTurns: 4,
            maxTurns: 12,
            allowsEarlyResolution: true,
          ),
        Difficulty.hard => const DifficultyProfile(
            difficulty: Difficulty.hard,
            resistance: 0.6,
            volatility: 0.6,
            objectionCount: 3,
            objectionCadence: 2,
            wellHandledToConcede: 2,
            escalationSpeed: 1,
            minTurns: 5,
            maxTurns: 14,
            allowsEarlyResolution: false,
          ),
        Difficulty.expert => const DifficultyProfile(
            difficulty: Difficulty.expert,
            resistance: 0.78,
            volatility: 0.75,
            objectionCount: 4,
            objectionCadence: 1,
            wellHandledToConcede: 3,
            escalationSpeed: 2,
            minTurns: 6,
            maxTurns: 16,
            allowsEarlyResolution: false,
          ),
        Difficulty.boss => const DifficultyProfile(
            difficulty: Difficulty.boss,
            resistance: 0.92,
            volatility: 0.9,
            objectionCount: 5,
            objectionCadence: 1,
            wellHandledToConcede: 4,
            escalationSpeed: 2,
            minTurns: 7,
            maxTurns: 18,
            allowsEarlyResolution: false,
          ),
      };
}
