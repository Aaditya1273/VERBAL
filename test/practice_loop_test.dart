import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbal/app/providers.dart';
import 'package:verbal/core/analytics.dart';
import 'package:verbal/core/billing.dart';
import 'package:verbal/core/config.dart';
import 'package:verbal/core/experiments.dart';
import 'package:verbal/core/failures.dart';
import 'package:verbal/core/voice.dart';
import 'package:verbal/data/local/memory_repositories.dart';
import 'package:verbal/data/remote/actor_service.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/domain/session.dart';
import 'package:verbal/features/practice/practice_controller.dart';

/// An actor that replies deterministically and reports whatever signal the test
/// asks for.
class FakeActor implements ActorService {
  FakeActor({this.signal = const TurnSignal(), this.analysis});

  TurnSignal signal;
  String? analysis;
  int replies = 0;
  final directives = <TurnDirective>[];

  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async {
    replies++;
    directives.add(directive);
    return ActorReply(text: 'reply $replies', signal: signal);
  }

  @override
  Future<String> analyse(String prompt) async {
    if (analysis == null) throw const AiUnavailableFailure();
    return analysis!;
  }
}

/// An actor that blocks until the test releases it, so two turns can be made
/// to overlap deliberately.
class SlowActor implements ActorService {
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async {
    calls++;
    await gate.future;
    return const ActorReply(text: 'slow reply', signal: TurnSignal());
  }

  @override
  Future<String> analyse(String prompt) async =>
      throw const AiUnavailableFailure();
}

/// Fails the first N calls, then succeeds. For retry behaviour.
class FlakyActor implements ActorService {
  FlakyActor({this.failures = 1});

  int failures;
  int calls = 0;
  final directives = <TurnDirective>[];

  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async {
    calls++;
    directives.add(directive);
    if (calls <= failures) throw const AiUnavailableFailure();
    return const ActorReply(text: 'recovered reply', signal: TurnSignal());
  }

  @override
  Future<String> analyse(String prompt) async =>
      throw const AiUnavailableFailure();
}

/// An actor that is always down.
class BrokenActor implements ActorService {
  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async =>
      throw const AiUnavailableFailure();

  @override
  Future<String> analyse(String prompt) async =>
      throw const AiUnavailableFailure();
}

class FakeRecognizer implements SpeechRecognizer {
  final _controller = StreamController<Heard>.broadcast();
  bool prepared = false;
  bool listening = false;
  Failure? prepareFailure;

  @override
  Stream<Heard> get heard => _controller.stream;

  @override
  bool get isListening => listening;

  @override
  Future<bool> prepare() async {
    if (prepareFailure != null) throw prepareFailure!;
    prepared = true;
    return true;
  }

  @override
  Future<void> start() async => listening = true;

  @override
  Future<void> stop() async => listening = false;

  @override
  Future<void> cancel() async => listening = false;

  @override
  Future<void> dispose() async => _controller.close();
}

class RecordingVoice implements VoiceSynthesizer {
  final spoken = <String>[];
  final voices = <String?>[];

  @override
  Future<void> speak(String text, {String? voice}) async {
    spoken.add(text);
    voices.add(voice);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

const _analysisJson = '''
{"summary":"You held the line.","objectiveMet":true,
 "scores":[{"skill":"clarity","score":80,"note":"You named the gap."}],
 "worked":[{"quote":"a","why":"b"}],"weakened":[],
 "betterAlternative":{"quote":"c","why":"d"},"nextSkill":"empathy",
 "playbookCandidates":[{"kind":"winningLine","title":"T","body":"B",
 "whyItWorks":"W","skill":"clarity"}]}
''';

({
  ProviderContainer container,
  MemorySessionRepository sessions,
  MemoryPlaybookRepository playbook,
  RecordingAnalyticsSink analytics
}) harness(
    {required ActorService actor,
    SpeechRecognizer? recognizer,
    VoiceSynthesizer? voice}) {
  final sessions = MemorySessionRepository();
  final playbook = MemoryPlaybookRepository();
  final sink = RecordingAnalyticsSink();

  final container = ProviderContainer(overrides: [
    configProvider.overrideWithValue(const AppConfig(
      geminiApiKey: '',
      elevenLabsApiKey: '',
      elevenLabsVoiceId: 'v',
      revenueCatAndroidKey: '',
      revenueCatIosKey: '',
      oneSignalAppId: '',
    )),
    analyticsProvider.overrideWithValue(Analytics(sink)),
    sessionRepositoryProvider.overrideWithValue(sessions),
    playbookRepositoryProvider.overrideWithValue(playbook),
    profileRepositoryProvider.overrideWithValue(MemoryProfileRepository()),
    billingProvider.overrideWithValue(UnconfiguredBilling()),
    actorServiceProvider.overrideWithValue(actor),
    speechRecognizerProvider.overrideWithValue(recognizer ?? FakeRecognizer()),
    voiceSynthesizerProvider.overrideWithValue(voice ?? RecordingVoice()),
    experimentServiceProvider
        .overrideWithValue(ExperimentService(Analytics(sink), userId: 'u')),
  ]);

  return (
    container: container,
    sessions: sessions,
    playbook: playbook,
    analytics: sink
  );
}

const _args = PracticeArgs(
    scenarioId: 'difficult_feedback', difficulty: Difficulty.moderate);

/// Reads the controller and holds a listener, so the autoDispose provider is
/// not collected while a test awaits.
PracticeController controllerOf(ProviderContainer container) {
  container.listen(practiceControllerProvider(_args), (_, __) {},
      fireImmediately: true);
  return container.read(practiceControllerProvider(_args).notifier);
}

void main() {
  group('the practice loop', () {
    test('opens with the scenario\'s scripted line and speaks it', () async {
      final voice = RecordingVoice();
      final h = harness(actor: FakeActor(), voice: voice);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();

      expect(controller.state.turns.single.speaker, Speaker.actor);
      expect(controller.state.turns.single.text,
          ScenarioLibrary.difficultFeedback.openingLine);
      expect(
          voice.spoken.single, ScenarioLibrary.difficultFeedback.openingLine);
      expect(h.analytics.contains(AnalyticsEvent.practiceStarted), isTrue);
    });

    test('a user turn produces an actor reply and advances the engine',
        () async {
      final actor = FakeActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('Your last two deadlines slipped.');

      expect(actor.replies, 1);
      expect(controller.engine.userTurns, 1);
      expect(controller.state.turns.map((t) => t.speaker).toList(),
          [Speaker.actor, Speaker.user, Speaker.actor]);
      expect(h.analytics.contains(AnalyticsEvent.voiceTurnCompleted), isTrue);
    });

    test('the first objection reaches the actor as a directive', () async {
      final actor = FakeActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('I want to talk about your recent work.');

      expect(actor.directives.single.raiseObjection?.id,
          ScenarioLibrary.difficultFeedback.objections.first.id);
    });

    test('a handled objection is not scored against a newly raised one',
        () async {
      final actor = FakeActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();

      // Turn 1 draws out the first objection.
      await controller.submitTyped('I want to talk about your recent work.');
      final raised = actor.directives.first.raiseObjection!.id;
      expect(controller.engine.pendingObjection?.id, raised);

      // Turn 2 answers it. The directive for this turn may raise the next
      // objection — the user must still be credited for the one they answered.
      actor.signal = TurnSignal(
        objectionAddressedId: raised,
        acknowledgedEmotion: true,
      );
      await controller
          .submitTyped('You are right that I should have raised this sooner.');

      expect(controller.engine.wellHandledCount, 1);
      expect(controller.engine.handledObjectionIds, contains(raised));
      expect(controller.engine.poorStreak, 0);
    });

    test('empty input is ignored rather than burning a turn', () async {
      final actor = FakeActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('   ');

      expect(actor.replies, 0);
      expect(controller.engine.userTurns, 0);
      expect(controller.state.phase, VoicePhase.idle);
    });
  });

  group('finishing', () {
    test('saves the transcript and analysis, and emits the events', () async {
      final h = harness(actor: FakeActor(analysis: _analysisJson));
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('This is a performance concern.');
      final id = await controller.finish(EndReason.userEnded);

      final saved = await h.sessions.byId(id!);
      expect(saved, isNotNull);
      expect(saved!.isComplete, isTrue);
      expect(saved.turns, isNotEmpty);
      expect(saved.analysis?.overall, greaterThan(0));
      expect(saved.analysis?.nextSkill.name, 'empathy');
      expect(h.analytics.contains(AnalyticsEvent.sessionCompleted), isTrue);
    });

    test('a failed analysis still saves the transcript, with no fake scores',
        () async {
      // FakeActor with no analysis payload throws on analyse().
      final h = harness(actor: FakeActor());
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('We need to talk about the deadlines.');
      final id = await controller.finish(EndReason.userEnded);

      final saved = await h.sessions.byId(id!);
      expect(saved!.turns, isNotEmpty, reason: 'transcript survives');
      expect(saved.analysis!.overall, 0, reason: 'no invented scores');
      expect(saved.analysis!.summary, contains('could not analyse'));
    });

    test('a session with no user turns is not scored', () async {
      final h = harness(actor: FakeActor(analysis: _analysisJson));
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      final id = await controller.finish(EndReason.abandoned);

      final saved = await h.sessions.byId(id!);
      expect(saved!.analysis!.overall, 0);
    });

    test('finishing twice is a no-op', () async {
      final h = harness(actor: FakeActor(analysis: _analysisJson));
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      final first = await controller.finish(EndReason.userEnded);
      final second = await controller.finish(EndReason.userEnded);

      expect(second, first);
      expect((await h.sessions.all()).length, 1);
    });
  });

  group('failure handling', () {
    test('an AI outage surfaces a message and keeps the session alive',
        () async {
      final h = harness(actor: BrokenActor());
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('I need to give you some feedback.');

      expect(controller.state.phase, VoicePhase.error);
      expect(controller.state.failure, isA<AiUnavailableFailure>());
      expect(controller.state.isFinished, isFalse);
      // The user's turn is kept so nothing they said is lost.
      expect(controller.state.turns.last.speaker, Speaker.user);
    });

    test('a denied microphone does not block the conversation', () async {
      final recognizer = FakeRecognizer()
        ..prepareFailure = const MicrophonePermissionFailure();
      final h = harness(actor: FakeActor(), recognizer: recognizer);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();

      expect(controller.state.failure, isA<MicrophonePermissionFailure>());
      // Typed input still works, which is the documented fallback.
      await controller.submitTyped('I can still type this.');
      expect(controller.engine.userTurns, 1);
    });
  });

  group('downstream state', () {
    test('the finished session is visible to the rest of the app', () async {
      final h = harness(actor: FakeActor(analysis: _analysisJson));
      addTearDown(h.container.dispose);

      // Warm the caches the way the home screen does before a session.
      expect(await h.container.read(sessionsProvider.future), isEmpty);
      await h.container.read(profileProvider.future);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('This is a performance concern.');
      final id = await controller.finish(EndReason.userEnded);

      // Without invalidation these would still serve the pre-session cache,
      // and the analysis screen would report "session not found".
      final sessions = await h.container.read(sessionsProvider.future);
      expect(sessions.map((s) => s.id), contains(id));

      final profile = await h.container.read(profileProvider.future);
      expect(profile.isEmpty, isFalse);
      expect(profile.totalSessions, 1);
    });
  });

  group('turn discipline', () {
    test('a second submit is rejected while a turn is in flight', () async {
      final actor = SlowActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();

      final first = controller.submitTyped('First thing I say.');
      await Future<void>.delayed(Duration.zero);

      // The talk button released and a final transcript landed at once.
      await controller.submitTyped('Second thing, fired twice.');

      expect(actor.calls, 1, reason: 'only one turn may be in flight');
      expect(controller.state.phase, VoicePhase.processing);

      actor.gate.complete();
      await first;

      expect(controller.engine.userTurns, 1);
      expect(
          controller.state.turns.where((t) => t.speaker == Speaker.user).length,
          1);
    });

    test('the engine advances exactly once per accepted turn', () async {
      final actor = FakeActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();

      await Future.wait([
        controller.submitTyped('one'),
        controller.submitTyped('two'),
        controller.submitTyped('three'),
      ]);

      expect(controller.engine.userTurns, 1);
      expect(actor.replies, 1);
    });

    test('turns are refused once the session is complete', () async {
      final h = harness(actor: FakeActor(analysis: _analysisJson));
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.finish(EndReason.userEnded);

      await controller.submitTyped('Too late to say this.');

      expect(controller.engine.userTurns, 0);
      expect(controller.state.phase, VoicePhase.completed);
      expect(controller.state.isFinished, isTrue);
    });

    test('phase and isFinished can never disagree', () async {
      final h = harness(actor: FakeActor(analysis: _analysisJson));
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      expect(controller.state.isFinished, controller.state.phase.isTerminal);

      await controller.submitTyped('Something.');
      expect(controller.state.isFinished, controller.state.phase.isTerminal);

      await controller.finish(EndReason.userEnded);
      expect(controller.state.isFinished, controller.state.phase.isTerminal);
    });
  });

  group('failure recovery', () {
    test('a failed turn does not consume the pending objection', () async {
      final actor = FlakyActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('I want to talk about your recent work.');

      expect(controller.state.phase, VoicePhase.error);
      expect(controller.engine.raisedObjectionIds, isEmpty,
          reason: 'nothing was said, so nothing was raised');
      expect(controller.state.canRetry, isTrue);
    });

    test('retry re-sends the turn and raises the same objection', () async {
      final actor = FlakyActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('I want to talk about your recent work.');
      await controller.retryLastTurn();

      expect(actor.calls, 2);
      expect(actor.directives[0].raiseObjection!.id,
          actor.directives[1].raiseObjection!.id,
          reason: 'the objection survived the failure');
      expect(controller.engine.userTurns, 1);
      expect(controller.engine.raisedObjectionIds.length, 1);

      // The user's words appear once, not twice.
      final userTurns =
          controller.state.turns.where((t) => t.speaker == Speaker.user);
      expect(userTurns.length, 1);
      expect(controller.state.phase, VoicePhase.idle);
    });

    test('retry is a no-op when there is nothing to retry', () async {
      final actor = FakeActor();
      final h = harness(actor: actor);
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.retryLastTurn();

      expect(actor.replies, 0);
      expect(controller.engine.userTurns, 0);
    });
  });

  group('latency instrumentation', () {
    test('a completed turn records real stage timings', () async {
      final h = harness(actor: FakeActor());
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('Naming the specific misses.');

      final timing = controller.state.lastTiming;
      expect(timing, isNotNull);
      expect(timing!.actorMs, greaterThanOrEqualTo(0));
      expect(timing.toFirstAudioMs, timing.transcriptMs + timing.actorMs);
      expect(timing.totalMs,
          timing.transcriptMs + timing.actorMs + timing.speechMs);

      final event = h.analytics.propertiesOf(AnalyticsEvent.voiceTurnCompleted);
      expect(event, isNotNull);
      expect(event!['toFirstAudioMs'], isA<int>());
    });

    test('a failed turn records no timing', () async {
      final h = harness(actor: BrokenActor());
      addTearDown(h.container.dispose);

      final controller = controllerOf(h.container);
      await controller.open();
      await controller.submitTyped('Something that will not land.');

      expect(controller.state.lastTiming, isNull);
      expect(h.analytics.contains(AnalyticsEvent.voiceTurnCompleted), isFalse);
    });
  });
}
