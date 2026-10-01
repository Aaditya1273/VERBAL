import 'dart:convert';

import 'scenario.dart';

/// The seven moves of DEAR MAN, the DBT interpersonal-effectiveness skill.
///
/// Used by IMBUE (arXiv:2402.12556), whose feedback was rated 25% more
/// expert-like than GPT-4's on the same transcripts. It sits alongside
/// VERBAL's six skills rather than replacing them: the six describe how the
/// conversation felt, DEAR MAN describes whether the ask was actually built
/// properly.
enum DearMan {
  describe,
  express,
  assert_,
  reinforce,
  mindful,
  confident,
  negotiate
}

extension DearManX on DearMan {
  String get label => switch (this) {
        DearMan.describe => 'Describe',
        DearMan.express => 'Express',
        DearMan.assert_ => 'Assert',
        DearMan.reinforce => 'Reinforce',
        DearMan.mindful => 'Mindful',
        DearMan.confident => 'Appear confident',
        DearMan.negotiate => 'Negotiate',
      };

  String get description => switch (this) {
        DearMan.describe => 'State the facts, without judgement or spin.',
        DearMan.express => 'Say how you feel about it, in your own voice.',
        DearMan.assert_ => 'Ask for what you want, or say no, in plain words.',
        DearMan.reinforce => 'Make the upside of agreeing explicit.',
        DearMan.mindful => 'Stay on your objective when pulled off it.',
        DearMan.confident => 'Sound like someone who means it.',
        DearMan.negotiate => 'Offer something, or ask for an alternative.',
      };

  /// The wire name used in the model contract. `assert` is a Dart keyword, so
  /// the enum value carries a trailing underscore the JSON does not.
  String get wireName => this == DearMan.assert_ ? 'assert' : name;

  static DearMan? fromName(String raw) {
    final key = raw.trim().toLowerCase();
    for (final d in DearMan.values) {
      if (d.wireName == key) return d;
    }
    return null;
  }
}

/// One DEAR MAN component, scored with its evidence.
class DearManScore {
  const DearManScore({
    required this.component,
    required this.score,
    required this.note,
  });

  final DearMan component;

  /// 0..100.
  final int score;
  final String note;

  Map<String, dynamic> toJson() =>
      {'component': component.wireName, 'score': score, 'note': note};

  factory DearManScore.fromJson(Map<String, dynamic> j) => DearManScore(
        component: DearManX.fromName(j['component'] as String? ?? '') ??
            DearMan.describe,
        score: (j['score'] as num? ?? 0).round().clamp(0, 100),
        note: j['note'] as String? ?? '',
      );
}

/// One skill score plus the evidence behind it.
class SkillScore {
  const SkillScore({
    required this.skill,
    required this.score,
    required this.note,
  });

  final Skill skill;

  /// 0..100.
  final int score;

  /// Why this score — must reference the conversation, not a generality.
  final String note;

  Map<String, dynamic> toJson() =>
      {'skill': skill.name, 'score': score, 'note': note};

  factory SkillScore.fromJson(Map<String, dynamic> j) => SkillScore(
        skill:
            SkillLabel.fromName(j['skill'] as String? ?? '') ?? Skill.clarity,
        score: (j['score'] as num? ?? 0).round().clamp(0, 100),
        note: j['note'] as String? ?? '',
      );
}

/// A moment in the transcript worth keeping.
class Moment {
  const Moment({required this.quote, required this.why});

  final String quote;
  final String why;

  Map<String, dynamic> toJson() => {'quote': quote, 'why': why};

  factory Moment.fromJson(Map<String, dynamic> j) => Moment(
        quote: j['quote'] as String? ?? '',
        why: j['why'] as String? ?? '',
      );
}

/// Structured post-session feedback.
class SessionAnalysis {
  const SessionAnalysis({
    required this.scores,
    required this.worked,
    required this.weakened,
    required this.betterAlternative,
    required this.nextSkill,
    required this.summary,
    required this.playbookCandidates,
    this.objectiveMet = false,
    this.committedPitfalls = const [],
    this.dearMan = const [],
  });

  final List<SkillScore> scores;

  /// Concrete things the user did well, quoted from the transcript.
  final List<Moment> worked;

  /// Concrete things that cost them, quoted from the transcript.
  final List<Moment> weakened;

  /// A specific rewritten line the user could have used instead.
  final Moment betterAlternative;

  /// The single highest-impact skill to practise next.
  final Skill nextSkill;

  final String summary;

  /// Lines and frameworks worth saving to the Playbook.
  final List<PlaybookCandidate> playbookCandidates;

  final bool objectiveMet;

  /// Pitfalls the engine recorded during the conversation.
  ///
  /// Engine facts, not model opinion: these are trigger turns that actually
  /// fired and were reacted to, so the review can show what the user did and
  /// what they should have done instead.
  final List<String> committedPitfalls;

  /// DEAR MAN scores, when the model supplied them. Optional by design: an
  /// older saved session simply has none.
  final List<DearManScore> dearMan;

  /// Mean of all skill scores — the headline number.
  int get overall {
    if (scores.isEmpty) return 0;
    final total = scores.fold<int>(0, (sum, s) => sum + s.score);
    return (total / scores.length).round();
  }

  int scoreFor(Skill s) => scores
      .firstWhere((x) => x.skill == s,
          orElse: () => SkillScore(skill: s, score: 0, note: ''))
      .score;

  Map<String, dynamic> toJson() => {
        'scores': scores.map((s) => s.toJson()).toList(),
        'worked': worked.map((m) => m.toJson()).toList(),
        'weakened': weakened.map((m) => m.toJson()).toList(),
        'betterAlternative': betterAlternative.toJson(),
        'nextSkill': nextSkill.name,
        'summary': summary,
        'objectiveMet': objectiveMet,
        'committedPitfalls': committedPitfalls,
        'dearMan': dearMan.map((d) => d.toJson()).toList(),
        'playbookCandidates':
            playbookCandidates.map((c) => c.toJson()).toList(),
      };

  factory SessionAnalysis.fromJson(Map<String, dynamic> j) => SessionAnalysis(
        scores: (j['scores'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SkillScore.fromJson)
            .toList(),
        worked: (j['worked'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Moment.fromJson)
            .toList(),
        weakened: (j['weakened'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Moment.fromJson)
            .toList(),
        betterAlternative: Moment.fromJson(
            (j['betterAlternative'] as Map<String, dynamic>?) ?? const {}),
        nextSkill: SkillLabel.fromName(j['nextSkill'] as String? ?? '') ??
            Skill.clarity,
        summary: j['summary'] as String? ?? '',
        objectiveMet: j['objectiveMet'] == true,
        committedPitfalls: (j['committedPitfalls'] as List? ?? [])
            .whereType<String>()
            .toList(),
        dearMan: (j['dearMan'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DearManScore.fromJson)
            .toList(),
        playbookCandidates: (j['playbookCandidates'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PlaybookCandidate.fromJson)
            .toList(),
      );
}

/// A Playbook item the analysis suggests, before the user accepts it.
class PlaybookCandidate {
  const PlaybookCandidate({
    required this.kind,
    required this.title,
    required this.body,
    required this.whyItWorks,
    required this.skill,
  });

  final PlaybookKind kind;
  final String title;

  /// The line or framework itself.
  final String body;
  final String whyItWorks;
  final Skill skill;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'body': body,
        'whyItWorks': whyItWorks,
        'skill': skill.name,
      };

  factory PlaybookCandidate.fromJson(Map<String, dynamic> j) =>
      PlaybookCandidate(
        kind: PlaybookKindX.fromName(j['kind'] as String? ?? ''),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        whyItWorks: j['whyItWorks'] as String? ?? '',
        skill:
            SkillLabel.fromName(j['skill'] as String? ?? '') ?? Skill.clarity,
      );
}

enum PlaybookKind {
  winningLine,
  betterAlternative,
  framework,
  principle,
  mistake
}

extension PlaybookKindX on PlaybookKind {
  String get label => switch (this) {
        PlaybookKind.winningLine => 'Winning line',
        PlaybookKind.betterAlternative => 'Better alternative',
        PlaybookKind.framework => 'Framework',
        PlaybookKind.principle => 'Principle',
        PlaybookKind.mistake => 'Mistake to avoid',
      };

  static PlaybookKind fromName(String raw) {
    final key = raw.trim();
    for (final k in PlaybookKind.values) {
      if (k.name == key) return k;
    }
    return PlaybookKind.winningLine;
  }
}

/// Turns whatever the model returned into a [SessionAnalysis].
///
/// Models wrap JSON in prose and markdown fences, omit fields, and return scores
/// outside 0-100. This normalises all of that, and is unit tested against those
/// exact failure shapes.
class AnalysisParser {
  const AnalysisParser._();

  static SessionAnalysis parse(
    String raw, {
    required List<Skill> focus,
    List<String> pitfalls = const [],
  }) {
    final map = _extractJson(raw);
    if (map == null) return fallback(focus: focus, pitfalls: pitfalls);

    final analysis = SessionAnalysis.fromJson(map);
    return _withAllSkills(analysis, focus, pitfalls);
  }

  /// Pull the first balanced JSON object out of a model response.
  static Map<String, dynamic>? _extractJson(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // Strip ```json fences.
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final fenced = fence.firstMatch(text);
    if (fenced != null) text = fenced.group(1)!.trim();

    final start = text.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(start, i + 1));
            return decoded is Map<String, dynamic> ? decoded : null;
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Guarantee a score for every skill so the UI and progress maths never have
  /// to deal with holes.
  static SessionAnalysis _withAllSkills(
      SessionAnalysis a, List<Skill> focus, List<String> pitfalls) {
    final bySkill = {for (final s in a.scores) s.skill: s};
    // A skill the scenario is built to stress deserves a truthful gap, not a
    // flattering midpoint, when the model said nothing about it.
    final complete = Skill.values
        .map((s) =>
            bySkill[s] ??
            SkillScore(
                skill: s,
                score: 50,
                note: focus.contains(s)
                    ? 'This scenario stresses ${s.label.toLowerCase()}, but the '
                        'session produced no clear signal either way.'
                    : 'Not enough signal this session.'))
        .toList();
    return SessionAnalysis(
      scores: complete,
      worked: a.worked,
      weakened: a.weakened,
      betterAlternative: a.betterAlternative,
      nextSkill: a.nextSkill,
      summary: a.summary,
      objectiveMet: a.objectiveMet,
      committedPitfalls: pitfalls,
      dearMan: a.dearMan,
      playbookCandidates: a.playbookCandidates,
    );
  }

  /// Used when analysis genuinely could not be produced. Deliberately honest:
  /// it does not invent scores or feedback.
  static SessionAnalysis fallback({
    required List<Skill> focus,
    List<String> pitfalls = const [],
  }) =>
      SessionAnalysis(
        scores: Skill.values
            .map((s) => SkillScore(
                skill: s,
                score: 0,
                note: 'Analysis unavailable for this session.'))
            .toList(),
        worked: const [],
        weakened: const [],
        betterAlternative: const Moment(quote: '', why: ''),
        nextSkill: focus.isEmpty ? Skill.clarity : focus.first,
        summary:
            'We could not analyse this session. Your transcript is saved — you can retry analysis.',
        committedPitfalls: pitfalls,
        playbookCandidates: const [],
      );
}
