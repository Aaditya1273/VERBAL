import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/progress.dart';
import 'package:verbal/domain/recommendation.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';

import 'progress_test.dart' show session;

void main() {
  group('first-time user', () {
    test('recommends a free scenario on moderate', () {
      final n = Recommender.next(
          profile: CommunicationProfile.empty, history: const []);

      expect(n.difficulty, Difficulty.moderate);
      expect(n.scenario.isPro, isFalse);
      expect(n.reason, isNotEmpty);
    });

    test('respects a stated interest', () {
      final n = Recommender.next(
        profile: CommunicationProfile.empty,
        history: const [],
        interest: 'negotiating',
      );
      expect(n.scenario.id, ScenarioLibrary.negotiatingRaise.id);
    });

    test('falls back to the full library for an unknown interest', () {
      final n = Recommender.next(
        profile: CommunicationProfile.empty,
        history: const [],
        interest: 'underwater_basket_weaving',
      );
      expect(ScenarioLibrary.all, contains(n.scenario));
    });
  });

  group('experienced user', () {
    test('targets the weakest skill', () {
      final profile = ProgressCalculator.build([
        for (var i = 0; i < 3; i++)
          session(
              id: '$i',
              scores: {
                Skill.composure: 20,
                Skill.empathy: 22,
                Skill.clarity: 90,
                Skill.assertiveness: 88,
                Skill.listening: 85,
                Skill.specificity: 86,
              },
              startedAt: DateTime(2026, 1, i + 1)),
      ]);

      final n = Recommender.next(profile: profile, history: const []);

      expect(n.targetSkill, Skill.composure);
      expect(n.scenario.rubricFocus, contains(Skill.composure));
      expect(n.reason, contains('Composure'));
    });

    test('steps difficulty up only after clearing the current one', () {
      final profile = ProgressCalculator.build([
        session(
          id: '1',
          scores: {for (final s in Skill.values) s: 85},
          scenarioId: ScenarioLibrary.termination.id,
          difficulty: Difficulty.moderate,
        ),
      ]);

      final n = Recommender.next(
          profile: profile,
          library: [ScenarioLibrary.termination],
          history: const []);

      expect(n.difficulty, Difficulty.hard);
    });

    test('does not escalate after a failed attempt', () {
      final profile = ProgressCalculator.build([
        session(
          id: '1',
          scores: {for (final s in Skill.values) s: 55},
          scenarioId: ScenarioLibrary.termination.id,
          difficulty: Difficulty.hard,
        ),
      ]);

      final n = Recommender.next(
          profile: profile,
          library: [ScenarioLibrary.termination],
          history: const []);

      expect(n.difficulty, Difficulty.moderate,
          reason: 'scored above 50 but never cleared it');
    });

    test('drops to easy after a bad attempt', () {
      final profile = ProgressCalculator.build([
        session(
          id: '1',
          scores: {for (final s in Skill.values) s: 20},
          scenarioId: ScenarioLibrary.termination.id,
          difficulty: Difficulty.hard,
        ),
      ]);

      final n = Recommender.next(
          profile: profile,
          library: [ScenarioLibrary.termination],
          history: const []);

      expect(n.difficulty, Difficulty.easy);
    });

    test('never recommends past the hardest difficulty', () {
      final profile = ProgressCalculator.build([
        session(
          id: '1',
          scores: {for (final s in Skill.values) s: 95},
          scenarioId: ScenarioLibrary.termination.id,
          difficulty: Difficulty.boss,
        ),
      ]);

      final n = Recommender.next(
          profile: profile,
          library: [ScenarioLibrary.termination],
          history: const []);

      expect(n.difficulty, Difficulty.boss);
    });

    test('prefers the scenario practised least', () {
      final profile = ProgressCalculator.build([
        for (var i = 0; i < 3; i++)
          session(
            id: 'a$i',
            scores: {for (final s in Skill.values) s: 40},
            scenarioId: ScenarioLibrary.difficultFeedback.id,
            startedAt: DateTime(2026, 1, i + 1),
          ),
      ]);

      final n = Recommender.next(
        profile: profile,
        library: [
          ScenarioLibrary.difficultFeedback,
          ScenarioLibrary.termination
        ],
        history: const [],
      );

      expect(n.scenario.id, ScenarioLibrary.termination.id);
    });
  });

  test('an empty library is a programming error, not a crash to ship', () {
    expect(
      () => Recommender.next(
          profile: CommunicationProfile.empty,
          history: const [],
          library: const []),
      throwsArgumentError,
    );
  });
}
