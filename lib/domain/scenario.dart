import 'difficulty.dart';

/// What the user is practising. Scenarios are data, never widget logic, so a new
/// scenario can be added without touching the UI or the conversation engine.
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.shortDescription,
    required this.category,
    required this.context,
    required this.userObjective,
    required this.actor,
    required this.objections,
    required this.escalationStages,
    required this.successCriteria,
    required this.rubricFocus,
    required this.estimatedMinutes,
    required this.skillTags,
    this.isPro = false,
    this.openingLine,
  });

  final String id;
  final String title;
  final String shortDescription;
  final ScenarioCategory category;

  /// Situation briefing shown to the user and given to the actor.
  final String context;

  /// What a good outcome looks like for the user.
  final String userObjective;

  final ActorProfile actor;

  /// Ordered pool. The engine decides which and when, based on difficulty.
  final List<Objection> objections;

  /// Emotional/positional stages the actor can move through under pressure.
  final List<EscalationStage> escalationStages;

  final List<String> successCriteria;

  /// Skills this scenario is designed to stress, weighted highest in analysis.
  final List<Skill> rubricFocus;

  final int estimatedMinutes;
  final List<String> skillTags;
  final bool isPro;

  /// Optional scripted first line. Keeps the opening deterministic and fast.
  final String? openingLine;

  /// Difficulties that make sense for this scenario.
  List<Difficulty> get supportedDifficulties => Difficulty.values;
}

enum ScenarioCategory { management, career, conflict, sales }

extension ScenarioCategoryLabel on ScenarioCategory {
  String get label => switch (this) {
        ScenarioCategory.management => 'Managing people',
        ScenarioCategory.career => 'Career',
        ScenarioCategory.conflict => 'Conflict',
        ScenarioCategory.sales => 'Sales',
      };
}

/// The person on the other side of the table.
class ActorProfile {
  const ActorProfile({
    required this.name,
    required this.role,
    required this.personality,
    required this.objective,
    required this.initialEmotion,
    required this.knownFacts,
    required this.constraints,
    this.voice = 'Kore',
  });

  final String name;
  final String role;

  /// How they speak and carry themselves.
  final String personality;

  /// What they are trying to achieve — deliberately in tension with the user's.
  final String objective;

  final Emotion initialEmotion;

  /// Facts the actor may assert. Anything outside this is off-limits, which is
  /// what stops the model inventing authoritative claims.
  final List<String> knownFacts;

  /// Hard behavioural boundaries.
  final List<String> constraints;

  /// Gemini TTS prebuilt voice name. A voice-first rehearsal falls apart if the
  /// character sounds nothing like the person described above.
  final String voice;
}

enum Emotion { calm, guarded, defensive, frustrated, upset, angry }

extension EmotionLabel on Emotion {
  String get label => switch (this) {
        Emotion.calm => 'Calm',
        Emotion.guarded => 'Guarded',
        Emotion.defensive => 'Defensive',
        Emotion.frustrated => 'Frustrated',
        Emotion.upset => 'Upset',
        Emotion.angry => 'Angry',
      };

  /// Escalate by [steps], clamped to the most intense state.
  Emotion escalate(int steps) {
    final next = (index + steps).clamp(0, Emotion.values.length - 1);
    return Emotion.values[next];
  }

  Emotion soften(int steps) {
    final next = (index - steps).clamp(0, Emotion.values.length - 1);
    return Emotion.values[next];
  }
}

/// The layer a conflict is being argued on.
///
/// From Interests-Rights-Power theory, as operationalised for LLM roleplay by
/// Rehearsal (arXiv:2309.12309). Conflicts escalate upward — a person who
/// cannot get what they need shifts to fairness, and then to leverage. The
/// skilled move is to bring the conversation back down to interests, which is
/// the behaviour Rehearsal measured a 67% reduction in competitive strategies
/// against.
enum IrpLayer {
  /// What they actually need — security, respect, recognition.
  interest,

  /// What they think is fair — precedent, process, equity.
  rights,

  /// What they can do about it — escalation, leverage, threat.
  power,
}

extension IrpLayerX on IrpLayer {
  String get label => switch (this) {
        IrpLayer.interest => 'Interests',
        IrpLayer.rights => 'Rights',
        IrpLayer.power => 'Power',
      };

  /// How the actor argues when standing on this layer.
  String get stance => switch (this) {
        IrpLayer.interest =>
          'Argue from what you actually need — security, respect, being valued. '
              'Speak about yourself, not about rules.',
        IrpLayer.rights =>
          'Argue from fairness — what was agreed, what happened to others, what '
              'the process should have been.',
        IrpLayer.power =>
          'Argue from what you can do about it — who else you can involve, what '
              'you can withdraw. Never make a legal claim.',
      };
}

/// A specific piece of resistance the actor can raise.
class Objection {
  const Objection({
    required this.id,
    required this.line,
    required this.intent,
    required this.resolvedWhen,
    required this.layer,
  });

  final String id;

  /// Roughly what the actor says. The model paraphrases; the intent is fixed.
  final String line;

  /// What the objection is really about.
  final String intent;

  /// What the user must do for this objection to count as handled.
  final String resolvedWhen;

  /// Which layer of the conflict this objection is fought on.
  final IrpLayer layer;
}

class EscalationStage {
  const EscalationStage({
    required this.index,
    required this.emotion,
    required this.behaviour,
  });

  final int index;
  final Emotion emotion;

  /// How the actor behaves once this stage is reached.
  final String behaviour;
}

/// The six skills VERBAL scores. Used by analysis, progress and recommendation.
enum Skill {
  clarity,
  empathy,
  assertiveness,
  composure,
  listening,
  specificity
}

extension SkillLabel on Skill {
  String get label => switch (this) {
        Skill.clarity => 'Clarity',
        Skill.empathy => 'Empathy',
        Skill.assertiveness => 'Assertiveness',
        Skill.composure => 'Composure',
        Skill.listening => 'Listening',
        Skill.specificity => 'Specificity',
      };

  String get description => switch (this) {
        Skill.clarity => 'Saying the actual message without hedging.',
        Skill.empathy => 'Acknowledging the other person\'s experience.',
        Skill.assertiveness => 'Holding the position under pressure.',
        Skill.composure => 'Staying steady when the temperature rises.',
        Skill.listening => 'Responding to what was said, not your script.',
        Skill.specificity => 'Concrete examples instead of generalities.',
      };

  static Skill? fromName(String raw) {
    final key = raw.trim().toLowerCase();
    for (final s in Skill.values) {
      if (s.name == key) return s;
    }
    return null;
  }
}
