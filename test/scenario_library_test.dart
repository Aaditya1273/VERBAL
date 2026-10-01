import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/actor_prompt.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/features/onboarding/onboarding_screen.dart';

void main() {
  group('library integrity', () {
    test('scenario ids are unique', () {
      final ids = ScenarioLibrary.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every scenario is fully authored', () {
      for (final s in ScenarioLibrary.all) {
        expect(s.context, isNotEmpty, reason: s.id);
        expect(s.userObjective, isNotEmpty, reason: s.id);
        expect(s.successCriteria, isNotEmpty, reason: s.id);
        expect(s.rubricFocus, isNotEmpty, reason: s.id);
        expect(s.actor.knownFacts, isNotEmpty, reason: s.id);
        expect(s.actor.constraints, isNotEmpty, reason: s.id);
        expect(s.escalationStages, isNotEmpty, reason: s.id);
      }
    });

    test('objection ids are unique within a scenario', () {
      for (final s in ScenarioLibrary.all) {
        final ids = s.objections.map((o) => o.id).toList();
        expect(ids.toSet().length, ids.length, reason: s.id);
      }
    });

    test('every scenario has enough objections for the hardest difficulty', () {
      final needed = Difficulty.boss.profile.objectionCount;
      for (final s in ScenarioLibrary.all) {
        expect(s.objections.length, greaterThanOrEqualTo(needed), reason: s.id);
      }
    });

    test('byId finds real scenarios and returns null otherwise', () {
      expect(ScenarioLibrary.byId('termination'), isNotNull);
      expect(ScenarioLibrary.byId('nope'), isNull);
    });

    test('byInterest falls back to the whole library', () {
      expect(ScenarioLibrary.byInterest('managing'), isNotEmpty);
      expect(ScenarioLibrary.byInterest('unknown').length,
          ScenarioLibrary.all.length);
    });
  });

  group('actor safety', () {
    test('every prompt carries the hard limits', () {
      for (final s in ScenarioLibrary.all) {
        final prompt =
            ActorPrompt.system(scenario: s, difficulty: Difficulty.boss);

        expect(prompt, contains('Never claim to be a real person'),
            reason: s.id);
        expect(prompt, contains('legally required'), reason: s.id);
        expect(prompt, contains('HR, legal, medical or financial advice'),
            reason: s.id);
        expect(prompt, contains('KNOWN FACTS'), reason: s.id);
      }
    });

    test('the termination scenario forbids legal claims explicitly', () {
      final constraints =
          ScenarioLibrary.termination.actor.constraints.join(' ').toLowerCase();
      expect(constraints, contains('legally'));
      expect(constraints, contains('jurisdiction'));
    });

    test('turn instructions carry the concession rule', () {
      const scenario = ScenarioLibrary.negotiatingRaise;
      final engine =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.expert)
            ..start();
      final directive = engine.nextDirective();

      final turn = ActorPrompt.turn(directive, scenario);
      expect(turn, contains('Do NOT concede'));
      expect(turn, contains('under ${directive.maxWords} words'));
    });
  });

  group('interest routing', () {
    test('every onboarding interest reaches a matching scenario', () {
      // Reads the list the UI actually renders. The previous version of this
      // test hand-copied the keys, so it passed while the screen was silently
      // missing an option.
      for (final offered in OnboardingScreen.interests) {
        final matches = ScenarioLibrary.all
            .where((s) => s.skillTags.contains(offered.key))
            .toList();
        expect(matches, isNotEmpty,
            reason: 'onboarding offers "${offered.label}" '
                '(${offered.key}) with no scenario behind it');
      }
    });

    test('a free scenario exists for a first session', () {
      expect(ScenarioLibrary.all.any((s) => !s.isPro), isTrue);
    });

    test('the library covers more than one category', () {
      expect(ScenarioLibrary.all.map((s) => s.category).toSet().length,
          greaterThan(1));
    });
  });
}
