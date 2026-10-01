import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/core/analytics.dart';
import 'package:verbal/core/experiments.dart';
import 'package:verbal/core/notifications.dart';

void main() {
  group('event names', () {
    test('are snake_case on the wire', () {
      expect(AnalyticsEvent.practiceStarted.wireName, 'practice_started');
      expect(AnalyticsEvent.appOpened.wireName, 'app_opened');
      expect(AnalyticsEvent.playbookReused.wireName, 'playbook_reused');
    });

    test('are unique', () {
      final names = AnalyticsEvent.values.map((e) => e.wireName).toList();
      expect(names.toSet().length, names.length);
    });
  });

  group('Analytics', () {
    test('records events with their properties', () {
      final sink = RecordingAnalyticsSink();
      Analytics(sink)
          .track(AnalyticsEvent.practiceStarted, {'scenario': 'termination'});

      expect(sink.contains(AnalyticsEvent.practiceStarted), isTrue);
      expect(sink.propertiesOf(AnalyticsEvent.practiceStarted),
          {'scenario': 'termination'});
    });

    test('refuses to carry conversation content', () {
      final analytics = Analytics(RecordingAnalyticsSink());

      expect(
        () => analytics.track(AnalyticsEvent.voiceTurnCompleted,
            {'transcript': 'something private'}),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => analytics.track(
            AnalyticsEvent.sessionCompleted, {'quote': 'what they said'}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('strips oversized free text even when asserts are disabled', () {
      // Release builds drop the assert, so the runtime filter must hold on its
      // own. A long free-text value is prose, not a structural fact.
      final sink = RecordingAnalyticsSink();
      Analytics(sink).track(AnalyticsEvent.sessionCompleted, {
        'scenario': 'termination',
        'note': 'x' * 500,
      });

      final props = sink.propertiesOf(AnalyticsEvent.sessionCompleted)!;
      expect(props['scenario'], 'termination');
      expect(props.containsKey('note'), isFalse);
    });

    test('keeps ordinary structural properties intact', () {
      final sink = RecordingAnalyticsSink();
      Analytics(sink).track(AnalyticsEvent.voiceTurnCompleted, {
        'scenario': 'angry_client',
        'turn': 3,
        'toFirstAudioMs': 1420,
      });

      expect(sink.propertiesOf(AnalyticsEvent.voiceTurnCompleted), {
        'scenario': 'angry_client',
        'turn': 3,
        'toFirstAudioMs': 1420,
      });
    });
  });

  group('ExperimentService', () {
    test('assignment is stable for the same user', () {
      final a = ExperimentService(Analytics(RecordingAnalyticsSink()),
          userId: 'user-42');
      final b = ExperimentService(Analytics(RecordingAnalyticsSink()),
          userId: 'user-42');

      expect(a.variantOf(Experiment.playbookAfterFirstSession),
          b.variantOf(Experiment.playbookAfterFirstSession));
    });

    test('splits the population across users', () {
      final variants = <Variant>{};
      for (var i = 0; i < 50; i++) {
        variants.add(ExperimentService(Analytics(RecordingAnalyticsSink()),
                userId: 'user-$i')
            .variantOf(Experiment.playbookAfterFirstSession));
      }
      expect(variants.length, 2, reason: 'both arms should be assigned');
    });

    test('exposure is tracked once, with the variant', () {
      final sink = RecordingAnalyticsSink();
      final service = ExperimentService(Analytics(sink), userId: 'u')
        ..trackExposure(Experiment.playbookAfterFirstSession)
        ..trackExposure(Experiment.playbookAfterFirstSession);

      final exposures = sink.events
          .where((e) => e.event == AnalyticsEvent.experimentExposed.wireName);

      expect(exposures.length, 1);
      expect(exposures.first.properties['experiment'],
          'playbookAfterFirstSession');
      expect(exposures.first.properties['variant'],
          service.variantOf(Experiment.playbookAfterFirstSession).name);
    });
  });

  group('retention copy', () {
    test('names the skill and the scenario, and deep-links to it', () {
      final n = RetentionCopy.forSkillGap(
        skillLabel: 'Empathy',
        scenarioTitle: 'Termination Conversation',
        scenarioId: 'termination',
      );

      expect(n.moment, RetentionMoment.practiceRecommended);
      expect(n.body, contains('Empathy'));
      expect(n.body, contains('Termination Conversation'));
      expect(n.deepLink, '/scenarios/termination');
    });

    test('improvement copy carries the actual delta', () {
      final n = RetentionCopy.forImprovement(skillLabel: 'Clarity', delta: 12);
      expect(n.title, contains('Clarity'));
      expect(n.body, contains('12'));
    });

    test('the local scheduler records the moment without a push provider',
        () async {
      final sink = RecordingAnalyticsSink();
      await LocalOnlyScheduler(Analytics(sink))
          .schedule(RetentionCopy.forInactivity(days: 5));

      final event = sink.propertiesOf(AnalyticsEvent.notificationOpened);
      expect(event, isNotNull);
      expect(event!['moment'], 'userInactive');
      expect(event['scheduled'], isFalse,
          reason: 'no provider is attached in this build');
    });
  });
}
