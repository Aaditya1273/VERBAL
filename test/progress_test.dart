import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/analysis.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/progress.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/session.dart';

PracticeSession session({
  required String id,
  required Map<Skill, int> scores,
  String scenarioId = 'difficult_feedback',
  Difficulty difficulty = Difficulty.moderate,
  DateTime? startedAt,
  bool analysed = true,
}) {
  final at = startedAt ?? DateTime(2026, 1, 1);
  return PracticeSession(
    id: id,
    scenarioId: scenarioId,
    scenarioTitle: 'T',
    difficulty: difficulty,
    startedAt: at,
    endedAt: at.add(const Duration(minutes: 8)),
    turns: const [],
    analysis: analysed
        ? SessionAnalysis(
            scores: Skill.values
                .map((s) =>
                    SkillScore(skill: s, score: scores[s] ?? 50, note: ''))
                .toList(),
            worked: const [],
            weakened: const [],
            betterAlternative: const Moment(quote: '', why: ''),
            nextSkill: Skill.clarity,
            summary: '',
            playbookCandidates: const [],
          )
        : null,
  );
}

void main() {
  group('empty state', () {
    test('no sessions produces an empty profile, not fake scores', () {
      final p = ProgressCalculator.build([]);
      expect(p.isEmpty, isTrue);
      expect(p.confidence, 0);
      expect(p.observedPattern, isNull);
    });

    test('sessions without analysis are ignored', () {
      final p = ProgressCalculator.build(
          [session(id: '1', scores: {}, analysed: false)]);
      expect(p.isEmpty, isTrue);
    });
  });

  group('rolling averages', () {
    test('averages the most recent window', () {
      final sessions = [
        session(
            id: '1',
            scores: {Skill.clarity: 60},
            startedAt: DateTime(2026, 1, 1)),
        session(
            id: '2',
            scores: {Skill.clarity: 80},
            startedAt: DateTime(2026, 1, 2)),
      ];

      final p = ProgressCalculator.build(sessions);
      expect(p.standingFor(Skill.clarity)!.score, 70);
      expect(p.totalSessions, 2);
    });

    test('delta compares the recent window against the one before it', () {
      // 5 old sessions at 40, then 5 new at 80.
      final sessions = [
        for (var i = 0; i < 5; i++)
          session(
              id: 'old$i',
              scores: {Skill.clarity: 40},
              startedAt: DateTime(2026, 1, i + 1)),
        for (var i = 0; i < 5; i++)
          session(
              id: 'new$i',
              scores: {Skill.clarity: 80},
              startedAt: DateTime(2026, 2, i + 1)),
      ];

      final standing =
          ProgressCalculator.build(sessions).standingFor(Skill.clarity)!;

      expect(standing.score, 80);
      expect(standing.delta, 40);
      expect(standing.isReliable, isTrue);
    });

    test('delta is zero when there is no previous window to compare', () {
      final p = ProgressCalculator.build([
        session(id: '1', scores: {Skill.clarity: 90}),
      ]);
      expect(p.standingFor(Skill.clarity)!.delta, 0);
      expect(p.standingFor(Skill.clarity)!.isReliable, isFalse);
    });
  });

  group('strengths and focus areas', () {
    test('focus areas are the two lowest skills', () {
      final p = ProgressCalculator.build([
        session(id: '1', scores: {
          Skill.clarity: 90,
          Skill.assertiveness: 85,
          Skill.empathy: 30,
          Skill.listening: 35,
          Skill.composure: 70,
          Skill.specificity: 75,
        }),
      ]);

      final focus = p.focusAreas.map((s) => s.skill).toList();
      expect(focus, [Skill.empathy, Skill.listening]);
    });

    test('strengths only include genuinely strong skills', () {
      final p = ProgressCalculator.build([
        session(id: '1', scores: {for (final s in Skill.values) s: 55}),
      ]);
      expect(p.strengths, isEmpty, reason: 'nothing is above the 70 bar');
    });
  });

  group('scenario mastery', () {
    test('records the hardest difficulty actually cleared', () {
      final p = ProgressCalculator.build([
        session(
            id: '1',
            scores: {for (final s in Skill.values) s: 80},
            difficulty: Difficulty.moderate,
            startedAt: DateTime(2026, 1, 1)),
        session(
            id: '2',
            scores: {for (final s in Skill.values) s: 40},
            difficulty: Difficulty.expert,
            startedAt: DateTime(2026, 1, 2)),
      ]);

      final m = p.mastery.single;
      expect(m.sessions, 2);
      expect(m.bestOverall, 80);
      expect(m.highestCleared, Difficulty.moderate,
          reason: 'the expert attempt scored below the pass mark');
    });

    test('tracks each scenario separately', () {
      final p = ProgressCalculator.build([
        session(id: '1', scores: {}, scenarioId: 'a'),
        session(id: '2', scores: {}, scenarioId: 'b'),
        session(id: '3', scores: {}, scenarioId: 'b'),
      ]);

      expect(p.mastery.length, 2);
      expect(p.mastery.first.scenarioId, 'b', reason: 'most practised first');
    });
  });

  group('observed pattern', () {
    test('stays silent until there is enough evidence', () {
      final p = ProgressCalculator.build([
        session(id: '1', scores: {Skill.empathy: 10, Skill.clarity: 95}),
      ]);
      expect(p.observedPattern, isNull);
    });

    test('stays silent when skills are evenly matched', () {
      final p = ProgressCalculator.build([
        for (var i = 0; i < 4; i++)
          session(
              id: '$i',
              scores: {for (final s in Skill.values) s: 60},
              startedAt: DateTime(2026, 1, i + 1)),
      ]);
      expect(p.observedPattern, isNull);
    });

    test('names the pattern tied to the weakest skill', () {
      final p = ProgressCalculator.build([
        for (var i = 0; i < 4; i++)
          session(
              id: '$i',
              scores: {
                Skill.empathy: 25,
                Skill.clarity: 90,
                Skill.assertiveness: 85,
                Skill.composure: 80,
                Skill.listening: 78,
                Skill.specificity: 82,
              },
              startedAt: DateTime(2026, 1, i + 1)),
      ]);

      expect(p.observedPattern, isNotNull);
      expect(p.observedPattern, contains('acknowledging'));
    });
  });
}
