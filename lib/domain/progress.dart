import 'difficulty.dart';
import 'scenario.dart';
import 'session.dart';

/// Where a user currently stands on one skill.
class SkillStanding {
  const SkillStanding({
    required this.skill,
    required this.score,
    required this.delta,
    required this.sampleSize,
  });

  final Skill skill;

  /// Rolling average, 0..100.
  final int score;

  /// Change against the previous window. Positive is improvement.
  final int delta;

  /// How many sessions fed this number. Below 2, treat the delta as noise.
  final int sampleSize;

  bool get isReliable => sampleSize >= 2;
}

/// How well the user has mastered a given scenario.
class ScenarioMastery {
  const ScenarioMastery({
    required this.scenarioId,
    required this.sessions,
    required this.bestOverall,
    required this.highestCleared,
  });

  final String scenarioId;
  final int sessions;
  final int bestOverall;

  /// Hardest difficulty completed with a passing score.
  final Difficulty? highestCleared;
}

/// The user's communication profile, derived entirely from session results.
///
/// Nothing here is self-reported or invented — if there are no sessions, the
/// profile is empty rather than flattering.
class CommunicationProfile {
  const CommunicationProfile({
    required this.standings,
    required this.mastery,
    required this.totalSessions,
    required this.observedPattern,
  });

  final List<SkillStanding> standings;
  final List<ScenarioMastery> mastery;
  final int totalSessions;

  /// A behavioural pattern observed across sessions, or null if too few.
  final String? observedPattern;

  bool get isEmpty => totalSessions == 0;

  /// Overall confidence figure — the mean of all reliable standings.
  int get confidence {
    if (standings.isEmpty) return 0;
    final total = standings.fold<int>(0, (s, x) => s + x.score);
    return (total / standings.length).round();
  }

  List<SkillStanding> get strengths {
    final sorted = [...standings]..sort((a, b) => b.score.compareTo(a.score));
    return sorted.where((s) => s.score >= 70).take(2).toList();
  }

  List<SkillStanding> get focusAreas {
    final sorted = [...standings]..sort((a, b) => a.score.compareTo(b.score));
    return sorted.take(2).toList();
  }

  SkillStanding? standingFor(Skill s) {
    for (final x in standings) {
      if (x.skill == s) return x;
    }
    return null;
  }

  static const empty = CommunicationProfile(
    standings: [],
    mastery: [],
    totalSessions: 0,
    observedPattern: null,
  );
}

/// Builds a [CommunicationProfile] from session history. Pure and tested.
class ProgressCalculator {
  const ProgressCalculator._();

  /// Sessions counted in the current rolling window.
  static const window = 5;

  /// A session counts as cleared at this overall score.
  static const passMark = 70;

  static CommunicationProfile build(List<PracticeSession> sessions) {
    final analysed = sessions
        .where((s) => s.isComplete && s.analysis != null)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    if (analysed.isEmpty) return CommunicationProfile.empty;

    final recent = analysed.take(window).toList();
    final previous = analysed.skip(window).take(window).toList();

    final standings = Skill.values.map((skill) {
      final now = _mean(recent, skill);
      final before = previous.isEmpty ? null : _mean(previous, skill);
      return SkillStanding(
        skill: skill,
        score: now,
        delta: before == null ? 0 : now - before,
        sampleSize: recent.length,
      );
    }).toList();

    return CommunicationProfile(
      standings: standings,
      mastery: _mastery(analysed),
      totalSessions: analysed.length,
      observedPattern: _pattern(analysed, standings),
    );
  }

  static int _mean(List<PracticeSession> sessions, Skill skill) {
    if (sessions.isEmpty) return 0;
    final total = sessions.fold<int>(
        0, (sum, s) => sum + (s.analysis?.scoreFor(skill) ?? 0));
    return (total / sessions.length).round();
  }

  static List<ScenarioMastery> _mastery(List<PracticeSession> sessions) {
    final grouped = <String, List<PracticeSession>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.scenarioId, () => []).add(s);
    }

    return grouped.entries.map((e) {
      var best = 0;
      Difficulty? cleared;
      for (final s in e.value) {
        final overall = s.analysis?.overall ?? 0;
        if (overall > best) best = overall;
        if (overall >= passMark) {
          if (cleared == null || s.difficulty.index > cleared.index) {
            cleared = s.difficulty;
          }
        }
      }
      return ScenarioMastery(
        scenarioId: e.key,
        sessions: e.value.length,
        bestOverall: best,
        highestCleared: cleared,
      );
    }).toList()
      ..sort((a, b) => b.sessions.compareTo(a.sessions));
  }

  /// A single observed behavioural pattern, stated only when there is enough
  /// evidence. Returns null rather than guessing.
  static String? _pattern(
      List<PracticeSession> sessions, List<SkillStanding> standings) {
    if (sessions.length < 3) return null;

    final weakest =
        ([...standings]..sort((a, b) => a.score.compareTo(b.score))).first;
    final strongest =
        ([...standings]..sort((a, b) => b.score.compareTo(a.score))).first;

    if (strongest.score - weakest.score < 15) return null;

    return switch (weakest.skill) {
      Skill.empathy =>
        'You make your point well, but you tend to move on before acknowledging how the other person feels.',
      Skill.listening =>
        'You hold your position clearly, but you tend to answer the objection you expected rather than the one you got.',
      Skill.composure =>
        'You start strong and lose ground once the other person gets emotional.',
      Skill.specificity =>
        'You stay calm and kind, but your examples stay general enough to be arguable.',
      Skill.assertiveness =>
        'You read the room well, then soften the message until it stops landing.',
      Skill.clarity =>
        'You cover a lot of ground, but the actual message arrives late or wrapped in qualifiers.',
    };
  }
}
