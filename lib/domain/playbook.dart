import 'analysis.dart';
import 'scenario.dart';

/// A reusable communication asset the user has kept from a session.
///
/// The Playbook is the thing that makes practice compound — every session
/// leaves something behind that is useful in the next one.
class PlaybookEntry {
  const PlaybookEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.whyItWorks,
    required this.skill,
    required this.sourceScenarioId,
    required this.createdAt,
    this.timesUsed = 0,
    this.lastUsedAt,
  });

  final String id;
  final PlaybookKind kind;
  final String title;

  /// The line or framework itself — this is what the user re-reads.
  final String body;
  final String whyItWorks;
  final Skill skill;
  final String sourceScenarioId;
  final DateTime createdAt;

  /// How many sessions have surfaced this entry as a prompt.
  final int timesUsed;
  final DateTime? lastUsedAt;

  PlaybookEntry copyWith({int? timesUsed, DateTime? lastUsedAt}) =>
      PlaybookEntry(
        id: id,
        kind: kind,
        title: title,
        body: body,
        whyItWorks: whyItWorks,
        skill: skill,
        sourceScenarioId: sourceScenarioId,
        createdAt: createdAt,
        timesUsed: timesUsed ?? this.timesUsed,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  factory PlaybookEntry.fromCandidate(
    PlaybookCandidate c, {
    required String id,
    required String scenarioId,
    required DateTime createdAt,
  }) =>
      PlaybookEntry(
        id: id,
        kind: c.kind,
        title: c.title,
        body: c.body,
        whyItWorks: c.whyItWorks,
        skill: c.skill,
        sourceScenarioId: scenarioId,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'body': body,
        'whyItWorks': whyItWorks,
        'skill': skill.name,
        'sourceScenarioId': sourceScenarioId,
        'createdAt': createdAt.toIso8601String(),
        'timesUsed': timesUsed,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };

  factory PlaybookEntry.fromJson(Map<String, dynamic> j) => PlaybookEntry(
        id: j['id'] as String,
        kind: PlaybookKindX.fromName(j['kind'] as String? ?? ''),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        whyItWorks: j['whyItWorks'] as String? ?? '',
        skill:
            SkillLabel.fromName(j['skill'] as String? ?? '') ?? Skill.clarity,
        sourceScenarioId: j['sourceScenarioId'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        timesUsed: (j['timesUsed'] as num? ?? 0).toInt(),
        lastUsedAt: DateTime.tryParse(j['lastUsedAt'] as String? ?? ''),
      );
}

/// Decides which saved entries are worth putting in front of the user before a
/// given practice session. Pure and tested — this is the reuse half of the
/// retention loop, and showing the wrong entries makes the feature feel random.
class PlaybookMatcher {
  const PlaybookMatcher._();

  /// Entries relevant to [scenario], best first.
  ///
  /// Relevance, in order of weight: came from this scenario, serves a skill the
  /// scenario stresses, then recency. Entries already used a lot are nudged down
  /// so the same line does not surface forever.
  static List<PlaybookEntry> relevantFor(
    Scenario scenario,
    List<PlaybookEntry> entries, {
    int limit = 3,
  }) {
    if (entries.isEmpty) return const [];

    final scored = entries.map((e) {
      var score = 0.0;
      if (e.sourceScenarioId == scenario.id) score += 3;
      if (scenario.rubricFocus.contains(e.skill)) score += 2;
      if (e.kind == PlaybookKind.mistake) score += 0.5;
      score -= e.timesUsed * 0.35;
      return (entry: e, score: score);
    }).toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return b.entry.createdAt.compareTo(a.entry.createdAt);
      });

    return scored.take(limit).map((s) => s.entry).toList();
  }

  /// Entries addressing a skill the user is weak at.
  static List<PlaybookEntry> forSkill(Skill skill, List<PlaybookEntry> entries,
          {int limit = 5}) =>
      entries.where((e) => e.skill == skill).take(limit).toList();
}
