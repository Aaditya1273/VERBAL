import 'logger.dart';

/// Every product event VERBAL emits. Typed, so event names cannot drift into
/// string literals scattered across the UI.
enum AnalyticsEvent {
  appOpened,
  onboardingStarted,
  onboardingCompleted,
  scenarioViewed,
  scenarioSelected,
  practiceStarted,
  practiceCompleted,
  practiceAbandoned,
  voiceTurnStarted,
  voiceTurnCompleted,
  pitfallDetected,
  sessionCompleted,
  analysisViewed,
  playbookCreated,
  playbookReused,
  recommendationShown,
  recommendationSelected,
  nextPracticeSelected,
  paywallViewed,
  trialStarted,
  purchaseStarted,
  purchaseCompleted,
  purchaseFailed,
  restoreCompleted,
  notificationOpened,
  experimentExposed,
}

extension AnalyticsEventName on AnalyticsEvent {
  /// snake_case wire name.
  String get wireName =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
}

/// Where events go. Swap the sink to add a real provider without touching call
/// sites.
abstract class AnalyticsSink {
  void send(String event, Map<String, Object?> properties);
}

/// Default sink: debug console only. No third-party analytics provider is wired
/// up in this build, and pretending otherwise would be a lie in the README.
class DebugAnalyticsSink implements AnalyticsSink {
  const DebugAnalyticsSink();

  @override
  void send(String event, Map<String, Object?> properties) {
    Log.d('analytics: $event ${properties.isEmpty ? '' : properties}');
  }
}

/// Records events in memory. Used by tests and by the debug event inspector.
class RecordingAnalyticsSink implements AnalyticsSink {
  final List<({String event, Map<String, Object?> properties})> events = [];

  @override
  void send(String event, Map<String, Object?> properties) {
    events.add((event: event, properties: properties));
  }

  bool contains(AnalyticsEvent e) => events.any((x) => x.event == e.wireName);

  Map<String, Object?>? propertiesOf(AnalyticsEvent e) {
    for (final x in events) {
      if (x.event == e.wireName) return x.properties;
    }
    return null;
  }

  void clear() => events.clear();
}

/// The single entry point for product analytics.
///
/// Conversation content never passes through here — only structural facts
/// (which scenario, which difficulty, how many turns). Transcripts stay on the
/// device.
class Analytics {
  Analytics(this._sink);

  final AnalyticsSink _sink;

  /// Property keys that must never carry transcript text.
  static const _forbidden = {
    'transcript',
    'reply',
    'text',
    'quote',
    'body',
    'utterance',
    'evidence',
    'partial',
  };

  /// Values longer than this are prose, not a structural fact — and prose in an
  /// analytics property is how a transcript leaks.
  static const _maxValueLength = 120;

  void track(AnalyticsEvent event,
      [Map<String, Object?> properties = const {}]) {
    // The assert is stripped from release builds, which is exactly where a leak
    // would matter. So the filter below runs in every build; the assert only
    // exists to make the mistake loud during development.
    assert(
      properties.keys.every((k) => !_forbidden.contains(k)),
      'Analytics must not carry conversation content: ${properties.keys}',
    );
    _sink.send(event.wireName, _sanitise(properties));
  }

  Map<String, Object?> _sanitise(Map<String, Object?> properties) {
    if (properties.isEmpty) return properties;

    final safe = <String, Object?>{};
    for (final entry in properties.entries) {
      if (_forbidden.contains(entry.key)) continue;
      final value = entry.value;
      if (value is String && value.length > _maxValueLength) continue;
      safe[entry.key] = value;
    }
    return safe;
  }
}
