import 'difficulty.dart';
import 'progress.dart';
import 'scenario.dart';
import 'scenario_library.dart';
import 'session.dart';

/// What VERBAL suggests the user does next, and why.
class NextPractice {
  const NextPractice({
    required this.scenario,
    required this.difficulty,
    required this.reason,
    required this.targetSkill,
  });

  final Scenario scenario;
  final Difficulty difficulty;

  /// Shown to the user. Must be a real reason derived from their history.
  final String reason;
  final Skill targetSkill;
}

/// Chooses the next practice from actual performance. Pure and tested.
///
/// This is the hinge of the retention loop: a weak skill becomes a specific
/// recommendation, which becomes the next session.
class Recommender {
  const Recommender._();

  static NextPractice next({
    required CommunicationProfile profile,
    required List<PracticeSession> history,
    List<Scenario> library = ScenarioLibrary.all,
    String? interest,
  }) {
    if (library.isEmpty) {
      throw ArgumentError('Cannot recommend from an empty scenario library.');
    }

    // No history: start with the scenario matching their stated interest, on
    // moderate, so the first session has real pushback but is not punishing.
    if (profile.isEmpty) {
      final pool =
          interest == null ? library : ScenarioLibrary.byInterest(interest);
      final pick = pool.firstWhere((s) => !s.isPro, orElse: () => pool.first);
      return NextPractice(
        scenario: pick,
        difficulty: Difficulty.moderate,
        reason: 'A good first conversation to feel what pressure does to you.',
        targetSkill: pick.rubricFocus.first,
      );
    }

    final weakest = profile.focusAreas.first;

    // Prefer a scenario that actually stresses the weak skill.
    final stressing =
        library.where((s) => s.rubricFocus.contains(weakest.skill)).toList();
    final scenario = stressing.isEmpty
        ? _leastPractised(library, profile)
        : _leastPractised(stressing, profile);

    return NextPractice(
      scenario: scenario,
      difficulty: _difficultyFor(scenario, profile),
      reason: _reason(weakest, scenario, profile),
      targetSkill: weakest.skill,
    );
  }

  static Scenario _leastPractised(
      List<Scenario> pool, CommunicationProfile profile) {
    final counts = {for (final m in profile.mastery) m.scenarioId: m.sessions};
    final sorted = [...pool]
      ..sort((a, b) => (counts[a.id] ?? 0).compareTo(counts[b.id] ?? 0));
    return sorted.first;
  }

  /// Step up only when the last attempt at this scenario actually cleared.
  static Difficulty _difficultyFor(
      Scenario scenario, CommunicationProfile profile) {
    ScenarioMastery? mastery;
    for (final m in profile.mastery) {
      if (m.scenarioId == scenario.id) mastery = m;
    }

    if (mastery == null || mastery.sessions == 0) return Difficulty.moderate;

    final cleared = mastery.highestCleared;
    if (cleared == null) {
      // Tried it, never cleared it — do not escalate.
      return mastery.bestOverall < 50 ? Difficulty.easy : Difficulty.moderate;
    }

    final next = (cleared.index + 1).clamp(0, Difficulty.values.length - 1);
    return Difficulty.values[next];
  }

  static String _reason(
      SkillStanding weakest, Scenario scenario, CommunicationProfile profile) {
    if (!weakest.isReliable) {
      return 'One more session will tell us where your real gaps are.';
    }
    if (weakest.delta > 3) {
      return '${weakest.skill.label} is improving. This scenario will test whether it holds under more pressure.';
    }
    if (weakest.delta < -3) {
      return '${weakest.skill.label} slipped in your recent sessions. This one puts it front and centre.';
    }
    return '${weakest.skill.label} is your lowest skill at ${weakest.score}. ${scenario.title} is built to stress it.';
  }
}
