import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/analysis.dart';
import 'package:verbal/domain/playbook.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';

PlaybookEntry entry({
  required String id,
  required Skill skill,
  String scenarioId = 'other',
  int timesUsed = 0,
  PlaybookKind kind = PlaybookKind.winningLine,
  int ageDays = 0,
}) =>
    PlaybookEntry(
      id: id,
      kind: kind,
      title: 'T-$id',
      body: 'B-$id',
      whyItWorks: 'W',
      skill: skill,
      sourceScenarioId: scenarioId,
      createdAt: DateTime(2026, 1, 1).subtract(Duration(days: ageDays)),
      timesUsed: timesUsed,
    );

void main() {
  const scenario =
      ScenarioLibrary.difficultFeedback; // focus: clarity, specificity, empathy

  group('PlaybookMatcher.relevantFor', () {
    test('returns nothing when the playbook is empty', () {
      expect(PlaybookMatcher.relevantFor(scenario, const []), isEmpty);
    });

    test('ranks same-scenario entries above same-skill entries', () {
      final sameScenario =
          entry(id: 'same', skill: Skill.composure, scenarioId: scenario.id);
      final sameSkill = entry(id: 'skill', skill: Skill.clarity);

      final result =
          PlaybookMatcher.relevantFor(scenario, [sameSkill, sameScenario]);

      expect(result.first.id, 'same');
    });

    test('ranks a focus-skill entry above an unrelated one', () {
      final focus = entry(id: 'focus', skill: Skill.empathy);
      final unrelated = entry(id: 'other', skill: Skill.assertiveness);

      final result = PlaybookMatcher.relevantFor(scenario, [unrelated, focus]);

      expect(result.first.id, 'focus');
    });

    test('demotes entries that keep resurfacing', () {
      final fresh = entry(id: 'fresh', skill: Skill.clarity);
      final overused =
          entry(id: 'overused', skill: Skill.clarity, timesUsed: 10);

      final result = PlaybookMatcher.relevantFor(scenario, [overused, fresh]);

      expect(result.first.id, 'fresh');
    });

    test('breaks ties by recency', () {
      final older = entry(id: 'older', skill: Skill.clarity, ageDays: 30);
      final newer = entry(id: 'newer', skill: Skill.clarity);

      final result = PlaybookMatcher.relevantFor(scenario, [older, newer]);

      expect(result.first.id, 'newer');
    });

    test('respects the limit', () {
      final entries =
          List.generate(10, (i) => entry(id: '$i', skill: Skill.clarity));
      expect(
          PlaybookMatcher.relevantFor(scenario, entries, limit: 3).length, 3);
    });
  });

  group('PlaybookEntry', () {
    test('is created from an analysis candidate', () {
      const c = PlaybookCandidate(
        kind: PlaybookKind.framework,
        title: 'Acknowledge then hold',
        body:
            'I want to acknowledge what you said before I explain the decision.',
        whyItWorks: 'Acknowledges emotion without abandoning the objective.',
        skill: Skill.empathy,
      );

      final e = PlaybookEntry.fromCandidate(c,
          id: 'p1', scenarioId: 'termination', createdAt: DateTime(2026, 5, 1));

      expect(e.kind, PlaybookKind.framework);
      expect(e.body, contains('acknowledge'));
      expect(e.sourceScenarioId, 'termination');
      expect(e.timesUsed, 0);
    });

    test('round-trips through JSON including usage', () {
      final e = entry(id: 'x', skill: Skill.listening, timesUsed: 3)
          .copyWith(lastUsedAt: DateTime(2026, 6, 1));

      final back = PlaybookEntry.fromJson(e.toJson());

      expect(back.id, e.id);
      expect(back.skill, Skill.listening);
      expect(back.timesUsed, 3);
      expect(back.lastUsedAt, DateTime(2026, 6, 1));
    });

    test('unknown kinds degrade to a winning line rather than throwing', () {
      expect(PlaybookKindX.fromName('nonsense'), PlaybookKind.winningLine);
    });
  });
}
