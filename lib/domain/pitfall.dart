import 'scenario.dart';

/// A specific communication mistake, and what the other person should do about
/// it the moment it happens.
///
/// This is VERBAL's version of the *trigger turn* from SIC-Agents
/// (arXiv:2608.29481): the exact point at which a learner commits a pitfall or
/// its skilled alternative. What makes it teach rather than merely score is
/// [requiredReaction] — the simulated person's very next turn must adapt to
/// what the learner just did.
///
/// The taxonomy below is re-derived for workplace conversations. SIC-Agents'
/// own pitfalls are pediatric palliative-care moves and do not transfer; what
/// transfers is the method — a trigger turn, a paired skilled alternative, and
/// an explicit acceptance rule that can be audited.
class Pitfall {
  const Pitfall({
    required this.id,
    required this.name,
    required this.coreSkill,
    required this.detectionHint,
    required this.skilledAlternative,
    required this.requiredReaction,
    this.appliesTo = const ['all'],
  });

  final String id;

  /// Shown to the user, in the moment and in the review.
  final String name;

  /// The skill this pitfall damages. Maps onto the existing rubric.
  final Skill coreSkill;

  /// Given to the actor model so it can recognise the move. Must describe an
  /// *observable* behaviour, not an inference about intent.
  final String detectionHint;

  /// What the user should have done instead. This is the teaching.
  final String skilledAlternative;

  /// The acceptance rule. The actor's next turn MUST do this, and the benchmark
  /// checks whether it did.
  final String requiredReaction;

  /// Scenario ids this applies to, or `['all']`.
  final List<String> appliesTo;

  bool appliesToScenario(String scenarioId) =>
      appliesTo.contains('all') || appliesTo.contains(scenarioId);
}

/// The workplace pitfall taxonomy.
class PitfallLibrary {
  const PitfallLibrary._();

  static const List<Pitfall> all = [
    defendBeforeAcknowledge,
    vagueWithoutExample,
    buryTheHeadline,
    solutionBeforeValidation,
    falseHope,
    apologiseForTheDecision,
    blameShift,
    negotiateAgainstSelf,
    overExplain,
    absolutes,
    fakeQuestion,
    matchTheHeat,
  ];

  static Pitfall? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The pitfalls that can fire in a given scenario. Sending only the eligible
  /// set keeps the turn prompt short, which matters on a spoken critical path.
  static List<Pitfall> forScenario(Scenario scenario) =>
      all.where((p) => p.appliesToScenario(scenario.id)).toList();

  // ---------------------------------------------------------------------------

  static const defendBeforeAcknowledge = Pitfall(
    id: 'defend_before_acknowledge',
    name: 'Defended before acknowledging',
    coreSkill: Skill.empathy,
    detectionHint:
        'You said something emotional, and the user replied by explaining, '
        'justifying or defending the decision without first acknowledging how you feel.',
    skilledAlternative:
        'Acknowledge the feeling in one sentence before you explain anything. '
        '"I can hear this is landing hard" costs you nothing and buys you the room.',
    requiredReaction:
        'Do not engage with their explanation at all. Make it obvious they have not '
        'heard you — restate how you feel, harder and shorter than before.',
  );

  static const vagueWithoutExample = Pitfall(
    id: 'vague_without_example',
    name: 'No specific example',
    coreSkill: Skill.specificity,
    detectionHint:
        'The user made a claim about your work, behaviour or the situation without '
        'naming a specific, checkable instance — no date, no deliverable, no incident.',
    skilledAlternative:
        'Name one concrete instance. A general impression is arguable; '
        '"the Aldridge deadline slipped four days" is not.',
    requiredReaction:
        'Demand a specific example. Say plainly that you have no idea what they are '
        'referring to, and that you cannot respond to something this vague.',
  );

  static const buryTheHeadline = Pitfall(
    id: 'bury_the_headline',
    name: 'Buried the headline',
    coreSkill: Skill.clarity,
    detectionHint:
        'The user\'s turn was mostly preamble, praise or softening, and the actual '
        'message was buried at the end or never arrived.',
    skilledAlternative:
        'Say the hard thing in the first two sentences. Softening before the message '
        'does not cushion it — it just makes the landing more confusing.',
    requiredReaction:
        'Take the softening entirely at face value. Respond as though the news is '
        'good or neutral, and be visibly reassured. Make them say the hard part plainly.',
  );

  static const solutionBeforeValidation = Pitfall(
    id: 'solution_before_validation',
    name: 'Solution before validation',
    coreSkill: Skill.listening,
    detectionHint:
        'The user moved to fixes, plans or next steps while you were still '
        'expressing how you feel about the situation.',
    skilledAlternative:
        'Let the reaction finish before you offer a plan. A solution offered too '
        'early reads as a way of ending the conversation.',
    requiredReaction:
        'Refuse to discuss next steps. Say you are not there yet, and return to what '
        'you were saying before they interrupted with a plan.',
  );

  static const falseHope = Pitfall(
    id: 'false_hope',
    name: 'Left the decision open',
    coreSkill: Skill.clarity,
    detectionHint:
        'The user used conditional or hedging language about a decision that is '
        'already final — "we\'ll see", "let me look into it", "if things change" — or '
        'invited an appeal that does not exist.',
    skilledAlternative:
        'Use the past tense. The decision has been made. Any opening you leave will '
        'be taken, and taking it back later is crueller than being clear now.',
    requiredReaction:
        'Seize the opening immediately. Ask directly whether the decision can still '
        'change, and press hard on exactly the words they used.',
    appliesTo: ['termination', 'difficult_feedback', 'setting_a_boundary'],
  );

  static const apologiseForTheDecision = Pitfall(
    id: 'apologise_for_the_decision',
    name: 'Apologised for the decision',
    coreSkill: Skill.assertiveness,
    detectionHint:
        'The user apologised for the decision itself — "I\'m sorry I have to do this" '
        '— rather than expressing empathy for its impact on you.',
    skilledAlternative:
        'Be sorry about the impact, not the decision. "I\'m sorry, this is hard" is '
        'empathy; "I\'m sorry I have to do this" invites an argument about whether you do.',
    requiredReaction:
        'Ask why they are doing it, if they are sorry about it. Put the decision '
        'back on them personally.',
  );

  static const blameShift = Pitfall(
    id: 'blame_shift',
    name: 'Shifted the blame',
    coreSkill: Skill.assertiveness,
    detectionHint:
        'The user attributed the decision to someone else — leadership, HR, "the '
        'business", "above my pay grade" — instead of owning it as theirs.',
    skilledAlternative:
        'Own the decision in the first person, even when you did not make it alone. '
        'Hiding behind others costs you the authority to deliver it.',
    requiredReaction:
        'Ask to speak to whoever actually decided. Question whether they argued for '
        'you at all, or simply passed the message along.',
  );

  static const negotiateAgainstSelf = Pitfall(
    id: 'negotiate_against_self',
    name: 'Negotiated against yourself',
    coreSkill: Skill.assertiveness,
    detectionHint:
        'Before you pushed back at all, the user lowered their own ask, hedged their '
        'number, or pre-emptively offered a concession.',
    skilledAlternative:
        'State the number and stop talking. Silence after an ask is uncomfortable, '
        'and that discomfort is doing work for you.',
    requiredReaction:
        'Accept their lowered position instantly and treat the matter as settled. '
        'Move on as though the conversation is over.',
    appliesTo: ['negotiating_raise', 'setting_a_boundary', 'angry_client'],
  );

  static const overExplain = Pitfall(
    id: 'over_explain',
    name: 'Over-explained under pressure',
    coreSkill: Skill.clarity,
    detectionHint:
        'After you pushed back, the user\'s reply got longer and added more reasons, '
        'rather than getting shorter and firmer.',
    skilledAlternative:
        'Under pressure, say less. Every extra reason you add is another surface to '
        'attack, and the weakest one becomes the whole conversation.',
    requiredReaction:
        'Pick the single weakest reason they just gave and attack only that one. '
        'Ignore everything else they said.',
  );

  static const absolutes = Pitfall(
    id: 'absolutes',
    name: 'Used an absolute',
    coreSkill: Skill.specificity,
    detectionHint:
        'The user used an absolute — "you always", "you never", "every time", '
        '"constantly" — about your behaviour.',
    skilledAlternative:
        'Absolutes are almost never true, and one counterexample destroys the point. '
        'Say "twice this quarter", not "always".',
    requiredReaction:
        'Name one clear counterexample and use it to dismiss the entire point as unfair.',
  );

  static const fakeQuestion = Pitfall(
    id: 'fake_question',
    name: 'Asked a question they had already answered',
    coreSkill: Skill.clarity,
    detectionHint:
        'The user asked how you feel about it, or what you think, about something '
        'that has already been decided and is not open to your input.',
    skilledAlternative:
        'Do not ask a question whose answer cannot change anything. Say what is '
        'decided, then ask something you can genuinely act on.',
    requiredReaction:
        'Answer the question fully and sincerely, then ask whether your answer '
        'actually changes anything.',
  );

  static const matchTheHeat = Pitfall(
    id: 'match_the_heat',
    name: 'Matched the heat',
    coreSkill: Skill.composure,
    detectionHint:
        'The user met your emotion by raising their own intensity — sharper, louder, '
        'sarcastic, or visibly defensive.',
    skilledAlternative:
        'Come down as the other person goes up. Matching intensity turns a difficult '
        'conversation into an argument, and arguments have no winner here.',
    requiredReaction:
        'Escalate further. Treat their tone as proof that you are being handled '
        'unfairly, and say so.',
  );
}
