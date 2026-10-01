import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/analysis.dart';
import 'package:verbal/domain/scenario.dart';

const _good = '''
{
  "summary": "You delivered the message but buried it.",
  "objectiveMet": true,
  "scores": [
    {"skill": "clarity", "score": 72, "note": "You named the missed deadline."},
    {"skill": "empathy", "score": 41, "note": "You moved past her reaction."}
  ],
  "worked": [{"quote": "The Aldridge deadline slipped by four days.", "why": "Concrete."}],
  "weakened": [{"quote": "It is not a big deal.", "why": "Undercut your own message."}],
  "betterAlternative": {"quote": "This is a performance concern.", "why": "States the stakes."},
  "nextSkill": "empathy",
  "playbookCandidates": [
    {"kind": "winningLine", "title": "Name the gap", "body": "The deadline slipped by four days.",
     "whyItWorks": "Specific and checkable.", "skill": "specificity"}
  ]
}
''';

void main() {
  const focus = [Skill.clarity, Skill.empathy];

  group('AnalysisParser', () {
    test('parses a well-formed response', () {
      final a = AnalysisParser.parse(_good, focus: focus);

      expect(a.summary, 'You delivered the message but buried it.');
      expect(a.objectiveMet, isTrue);
      expect(a.scoreFor(Skill.clarity), 72);
      expect(a.nextSkill, Skill.empathy);
      expect(a.worked.single.quote, contains('Aldridge'));
      expect(a.playbookCandidates.single.skill, Skill.specificity);
    });

    test('always returns a score for every skill', () {
      final a = AnalysisParser.parse(_good, focus: focus);
      expect(a.scores.length, Skill.values.length);
      for (final s in Skill.values) {
        expect(a.scores.any((x) => x.skill == s), isTrue, reason: s.name);
      }
    });

    test('strips markdown fences', () {
      final a = AnalysisParser.parse('```json\n$_good\n```', focus: focus);
      expect(a.scoreFor(Skill.clarity), 72);
    });

    test('ignores prose wrapped around the JSON', () {
      final a = AnalysisParser.parse(
          'Sure! Here is the analysis:\n$_good\nHope that helps.',
          focus: focus);
      expect(a.scoreFor(Skill.clarity), 72);
    });

    test('handles braces inside string values', () {
      const raw = '{"summary": "they said {maybe} to me", "scores": [], '
          '"nextSkill": "clarity", "worked": [], "weakened": [], '
          '"betterAlternative": {"quote": "a", "why": "b"}, "playbookCandidates": []}';
      final a = AnalysisParser.parse(raw, focus: focus);
      expect(a.summary, 'they said {maybe} to me');
    });

    test('clamps out-of-range scores', () {
      const raw = '{"scores": [{"skill": "clarity", "score": 140, "note": ""},'
          '{"skill": "empathy", "score": -20, "note": ""}], "nextSkill": "clarity"}';
      final a = AnalysisParser.parse(raw, focus: focus);
      expect(a.scoreFor(Skill.clarity), 100);
      expect(a.scoreFor(Skill.empathy), 0);
    });

    test('falls back rather than inventing feedback on unparseable output', () {
      for (final junk in ['', 'I cannot help with that.', '{"broken": ']) {
        final a = AnalysisParser.parse(junk, focus: focus);
        expect(a.overall, 0, reason: 'junk: "$junk"');
        expect(a.worked, isEmpty);
        expect(a.summary, contains('could not analyse'));
        expect(a.nextSkill, Skill.clarity);
      }
    });

    test('survives an unknown skill name', () {
      const raw = '{"scores": [{"skill": "charisma", "score": 90, "note": ""}],'
          ' "nextSkill": "telepathy"}';
      final a = AnalysisParser.parse(raw, focus: focus);
      expect(a.scores.length, Skill.values.length);
      expect(a.nextSkill, Skill.clarity);
    });
  });

  group('SessionAnalysis', () {
    test('overall is the mean of all skill scores', () {
      const a = SessionAnalysis(
        scores: [
          SkillScore(skill: Skill.clarity, score: 80, note: ''),
          SkillScore(skill: Skill.empathy, score: 40, note: ''),
        ],
        worked: [],
        weakened: [],
        betterAlternative: Moment(quote: '', why: ''),
        nextSkill: Skill.empathy,
        summary: '',
        playbookCandidates: [],
      );
      expect(a.overall, 60);
    });

    test('round-trips through JSON', () {
      final a = AnalysisParser.parse(_good, focus: focus);
      final b = SessionAnalysis.fromJson(a.toJson());

      expect(b.scoreFor(Skill.clarity), a.scoreFor(Skill.clarity));
      expect(b.nextSkill, a.nextSkill);
      expect(b.playbookCandidates.length, a.playbookCandidates.length);
      expect(b.betterAlternative.quote, a.betterAlternative.quote);
    });
  });

  group('DEAR MAN', () {
    const raw = '''
{"summary":"x","nextSkill":"clarity","scores":[],"worked":[],"weakened":[],
 "betterAlternative":{"quote":"a","why":"b"},"playbookCandidates":[],
 "dearMan":[
   {"component":"describe","score":80,"note":"Named the two dates."},
   {"component":"assert","score":40,"note":"Never actually made the ask."},
   {"component":"negotiate","score":65,"note":"Offered a follow-up."}
 ]}''';

    test('parses the components, including the assert keyword clash', () {
      final a = AnalysisParser.parse(raw, focus: focus);

      expect(a.dearMan, hasLength(3));
      expect(a.dearMan[0].component, DearMan.describe);
      expect(a.dearMan[1].component, DearMan.assert_,
          reason: 'JSON says "assert"; Dart cannot name an enum that');
      expect(a.dearMan[1].score, 40);
      expect(a.dearMan[1].note, 'Never actually made the ask.');
    });

    test('wire names round-trip', () {
      for (final d in DearMan.values) {
        expect(DearManX.fromName(d.wireName), d, reason: d.name);
      }
      expect(DearMan.assert_.wireName, 'assert');
    });

    test('an unknown component degrades instead of throwing', () {
      expect(DearManX.fromName('improvise'), isNull);
      final a = AnalysisParser.parse(
          '{"dearMan":[{"component":"improvise","score":10,"note":""}],'
          '"nextSkill":"clarity"}',
          focus: focus);
      expect(a.dearMan.single.component, DearMan.describe,
          reason: 'falls back rather than losing the score');
    });

    test('scores are clamped like every other score', () {
      final a = AnalysisParser.parse(
          '{"dearMan":[{"component":"mindful","score":900,"note":""}],'
          '"nextSkill":"clarity"}',
          focus: focus);
      expect(a.dearMan.single.score, 100);
    });

    test('an analysis without DEAR MAN is still valid', () {
      final a = AnalysisParser.parse(_good, focus: focus);
      expect(a.dearMan, isEmpty);
      expect(a.overall, greaterThan(0), reason: 'the six skills still scored');
    });

    test('survives the JSON round-trip', () {
      final a = AnalysisParser.parse(raw, focus: focus);
      final back = SessionAnalysis.fromJson(a.toJson());

      expect(back.dearMan.map((d) => d.component),
          a.dearMan.map((d) => d.component));
      expect(back.dearMan[1].score, 40);
    });
  });

  group('engine-recorded pitfalls', () {
    test('are attached to the analysis, not taken from the model', () {
      final a = AnalysisParser.parse(_good,
          focus: focus, pitfalls: ['over_explain', 'over_explain']);

      expect(a.committedPitfalls, ['over_explain', 'over_explain'],
          reason: 'repeats matter — the review shows a count');
    });

    test('survive an analysis failure', () {
      final a = AnalysisParser.parse('not json at all',
          focus: focus, pitfalls: ['match_the_heat']);

      expect(a.overall, 0, reason: 'no invented scores');
      expect(a.committedPitfalls, ['match_the_heat'],
          reason: 'the engine still knows what happened');
    });

    test('round-trip through JSON', () {
      final a =
          AnalysisParser.parse(_good, focus: focus, pitfalls: ['absolutes']);
      expect(SessionAnalysis.fromJson(a.toJson()).committedPitfalls,
          ['absolutes']);
    });
  });

  group('focus skills get an honest gap', () {
    test('a missing focus skill says so instead of scoring a bland 50', () {
      final a = AnalysisParser.parse(
          '{"scores":[{"skill":"clarity","score":70,"note":"x"}],'
          '"nextSkill":"clarity"}',
          focus: [Skill.empathy]);

      final empathy = a.scores.firstWhere((s) => s.skill == Skill.empathy);
      expect(empathy.score, 50);
      expect(empathy.note, contains('stresses empathy'),
          reason: 'focus was previously accepted and ignored');

      final listening = a.scores.firstWhere((s) => s.skill == Skill.listening);
      expect(listening.note, 'Not enough signal this session.');
    });
  });
}
