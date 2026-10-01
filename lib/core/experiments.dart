import 'analytics.dart';

/// A running product experiment.
enum Experiment {
  /// Does showing the Playbook immediately after the first session increase
  /// repeat practice? Control ends at the score screen; variant routes through
  /// the Playbook to the next recommended practice.
  playbookAfterFirstSession,
}

extension ExperimentKey on Experiment {
  String get key => name;
}

enum Variant { control, variant }

/// Assigns variants and records exposure.
///
/// Assignment is a deterministic hash of the user id, so a user sees the same
/// variant on every launch without a server round-trip. No results are
/// fabricated anywhere — [Analytics] is the only source of outcome data, and
/// until real sessions run there is nothing to report.
class ExperimentService {
  ExperimentService(this._analytics, {required this.userId});

  final Analytics _analytics;
  final String userId;

  final Set<String> _exposed = {};

  Variant variantOf(Experiment experiment) {
    final hash = _stableHash('${experiment.key}:$userId');
    return hash.isEven ? Variant.control : Variant.variant;
  }

  /// Call when the user actually reaches the experiment surface — not at
  /// assignment time, or exposure numbers are meaningless.
  void trackExposure(Experiment experiment) {
    if (!_exposed.add(experiment.key)) return;
    _analytics.track(AnalyticsEvent.experimentExposed, {
      'experiment': experiment.key,
      'variant': variantOf(experiment).name,
    });
  }

  bool isOn(Experiment experiment) => variantOf(experiment) == Variant.variant;

  /// FNV-1a. Stable across platforms and launches, unlike [Object.hashCode].
  static int _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
