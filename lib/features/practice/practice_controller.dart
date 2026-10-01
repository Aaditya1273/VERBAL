import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics.dart';
import '../../core/failures.dart';
import '../../core/logger.dart';
import '../../core/notifications.dart';
import '../../core/voice.dart';
import '../../data/remote/actor_service.dart';
import '../../domain/actor_prompt.dart';
import '../../domain/analysis.dart';
import '../../domain/analysis_prompt.dart';
import '../../domain/conversation_engine.dart';
import '../../domain/difficulty.dart';
import '../../domain/pitfall.dart';
import '../../domain/scenario.dart';
import '../../domain/session.dart';

/// Everything the practice screen renders.
class PracticeState {
  const PracticeState({
    required this.scenario,
    required this.difficulty,
    required this.phase,
    required this.turns,
    required this.levels,
    this.partial = '',
    this.pressure = 0,
    this.emotion = Emotion.calm,
    this.failure,
    this.sessionId,
    this.analysing = false,
    this.lastTiming,
    this.lastPitfall,
  });

  final Scenario scenario;
  final Difficulty difficulty;
  final VoicePhase phase;
  final List<Turn> turns;

  /// Recent mic levels, most recent first.
  final List<double> levels;

  /// Live partial transcript while the user is speaking.
  final String partial;

  final double pressure;
  final Emotion emotion;
  final Failure? failure;
  final String? sessionId;
  final bool analysing;

  /// Stage timings for the most recent turn. Null until one completes.
  final TurnTiming? lastTiming;

  /// The pitfall committed on the most recent turn, surfaced live. Null once a
  /// clean turn follows.
  final Pitfall? lastPitfall;

  /// Derived from [phase] rather than stored separately, so the two can never
  /// disagree.
  bool get isFinished => phase.isTerminal;

  /// True when the user's last turn could not be delivered and is retryable.
  bool get canRetry => phase == VoicePhase.error && failure != null;

  /// The actor's most recent line — the one shown large on screen.
  String get currentLine {
    for (final t in turns.reversed) {
      if (t.speaker == Speaker.actor) return t.text;
    }
    return '';
  }

  bool get canSpeak => phase == VoicePhase.idle || phase == VoicePhase.error;

  PracticeState copyWith({
    VoicePhase? phase,
    List<Turn>? turns,
    List<double>? levels,
    String? partial,
    double? pressure,
    Emotion? emotion,
    Failure? failure,
    bool clearFailure = false,
    String? sessionId,
    bool? analysing,
    TurnTiming? lastTiming,
    Pitfall? lastPitfall,
    bool clearPitfall = false,
  }) =>
      PracticeState(
        scenario: scenario,
        difficulty: difficulty,
        phase: phase ?? this.phase,
        turns: turns ?? this.turns,
        levels: levels ?? this.levels,
        partial: partial ?? this.partial,
        pressure: pressure ?? this.pressure,
        emotion: emotion ?? this.emotion,
        failure: clearFailure ? null : (failure ?? this.failure),
        sessionId: sessionId ?? this.sessionId,
        analysing: analysing ?? this.analysing,
        lastTiming: lastTiming ?? this.lastTiming,
        lastPitfall: clearPitfall ? null : (lastPitfall ?? this.lastPitfall),
      );
}

/// Arguments for a practice run.
class PracticeArgs {
  const PracticeArgs({required this.scenarioId, required this.difficulty});

  final String scenarioId;
  final Difficulty difficulty;

  @override
  bool operator ==(Object other) =>
      other is PracticeArgs &&
      other.scenarioId == scenarioId &&
      other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash(scenarioId, difficulty);
}

/// Drives one practice conversation end to end.
///
/// Owns the turn loop: listen → transcribe → ask the actor → speak → repeat,
/// with the [ConversationEngine] deciding what the actor is allowed to do.
class PracticeController extends StateNotifier<PracticeState> {
  PracticeController({
    required Scenario scenario,
    required Difficulty difficulty,
    required SpeechRecognizer recognizer,
    required VoiceSynthesizer voice,
    required ActorService actor,
    required this.ref,
  })  : _engine =
            ConversationEngine(scenario: scenario, difficulty: difficulty),
        _recognizer = recognizer,
        _voice = voice,
        _actor = actor,
        _systemPrompt =
            ActorPrompt.system(scenario: scenario, difficulty: difficulty),
        super(PracticeState(
          scenario: scenario,
          difficulty: difficulty,
          phase: VoicePhase.idle,
          turns: const [],
          levels: const [],
        ));

  final ConversationEngine _engine;
  final SpeechRecognizer _recognizer;
  final VoiceSynthesizer _voice;
  final ActorService _actor;
  final String _systemPrompt;
  final Ref ref;

  StreamSubscription<Heard>? _sub;
  final _sessionId = 's_${DateTime.now().microsecondsSinceEpoch}';
  final _startedAt = DateTime.now();
  bool _disposed = false;

  /// Guards the turn pipeline. A turn is indivisible: nothing else may start
  /// one while it runs.
  bool _turnInFlight = false;

  /// Incremented per accepted turn. A result tagged with an older sequence is
  /// from a turn that has been superseded or abandoned, and is dropped.
  int _turnSeq = 0;

  /// Set when [stopListening] is waiting for a final transcript, so a final
  /// result arriving in that window cancels the fallback submit.
  Completer<String>? _awaitingFinal;

  /// The user turn that failed to reach the actor, kept so it can be retried
  /// without the user repeating themselves.
  String? _retryText;

  /// Observations captured turn by turn while the conversation was live.
  final _evidence = <String>[];

  static const _levelWindow = 48;

  /// How long to wait for a final transcript after the user releases the
  /// button before falling back to the last partial.
  static const _finalTranscriptGrace = Duration(milliseconds: 900);

  ConversationEngine get engine => _engine;

  /// Prepare the microphone and deliver the opening line.
  Future<void> open() async {
    _track(AnalyticsEvent.practiceStarted, {
      'scenario': state.scenario.id,
      'difficulty': state.difficulty.name,
    });

    unawaited(ref.read(profileRepositoryProvider).recordSessionStarted());
    _engine.start();

    try {
      await _recognizer.prepare();
      _sub = _recognizer.heard.listen(_onHeard, onError: _onVoiceError);
    } on Failure catch (f) {
      // Voice unavailable is recoverable — the user can type instead.
      _set(state.copyWith(phase: VoicePhase.error, failure: f));
    }

    final opening =
        state.scenario.openingLine ?? 'So — what did you want to talk about?';
    await _deliver(opening);
  }

  void _onHeard(Heard heard) {
    if (_disposed || state.phase.isTerminal) return;

    // Level-only events drive the waveform and carry no transcript.
    if (heard.text.isEmpty && !heard.isFinal) {
      if (heard.level > 0) {
        _set(state.copyWith(
          levels: [heard.level, ...state.levels].take(_levelWindow).toList(),
        ));
      }
      return;
    }

    // Transcripts are only meaningful while the microphone is live. Anything
    // arriving later belongs to a turn that has already moved on.
    if (!state.phase.isCapturing) return;

    if (heard.isFinal) {
      final pending = _awaitingFinal;
      if (pending != null && !pending.isCompleted) {
        // stopListening() is waiting for exactly this.
        pending.complete(heard.text);
        return;
      }
      unawaited(_submit(heard.text));
    } else {
      _set(state.copyWith(partial: heard.text));
    }
  }

  void _onVoiceError(Object error) {
    if (_disposed) return;
    final failure =
        error is Failure ? error : VoiceFailure.recognitionUnavailable;
    _set(state.copyWith(phase: VoicePhase.error, failure: failure));
  }

  /// Start capturing the user's turn.
  Future<void> listen() async {
    // Never open the microphone while the actor is speaking or thinking.
    if (!state.canSpeak || _turnInFlight) return;

    try {
      await _voice.stop();
      if (_disposed) return;
      _set(state.copyWith(
          phase: VoicePhase.listening, partial: '', clearFailure: true));
      _track(AnalyticsEvent.voiceTurnStarted, {
        'scenario': state.scenario.id,
        'turn': _engine.userTurns + 1,
      });
      await _recognizer.start();
    } on Failure catch (f) {
      _set(state.copyWith(phase: VoicePhase.error, failure: f));
    } on Object catch (e, st) {
      Log.e('could not start listening', e, st);
      _set(state.copyWith(
          phase: VoicePhase.error,
          failure: VoiceFailure.recognitionUnavailable));
    }
  }

  /// Stop capturing and submit what was heard.
  ///
  /// Recognition delivers its final result slightly after [stop]. We wait a
  /// bounded moment for it and fall back to the last partial, which is what
  /// makes short utterances survive.
  Future<void> stopListening() async {
    if (!state.phase.isCapturing) return;

    final waiter = Completer<String>();
    _awaitingFinal = waiter;
    _sttStopwatch = Stopwatch()..start();

    try {
      await _recognizer.stop();
    } on Object catch (e, st) {
      Log.w('stop listening failed: $e');
      Log.e('stt stop', e, st);
    }

    String text;
    try {
      text = await waiter.future.timeout(_finalTranscriptGrace);
    } on TimeoutException {
      text = state.partial;
    } finally {
      _awaitingFinal = null;
    }

    await _submit(text);
  }

  /// Text entry — the fallback when recognition is unavailable, and the
  /// accessibility path.
  Future<void> submitTyped(String text) {
    _sttStopwatch = null;
    return _submit(text);
  }

  /// Re-send the turn that failed to reach the actor.
  ///
  /// The engine never committed that directive, so the objection the actor was
  /// about to raise is still pending and is not silently skipped.
  Future<void> retryLastTurn() async {
    final text = _retryText;
    if (text == null || _turnInFlight) return;
    _retryText = null;
    await _submit(text, isRetry: true);
  }

  Stopwatch? _sttStopwatch;

  Future<void> _submit(String rawText, {bool isRetry = false}) async {
    final text = rawText.trim();
    if (_disposed || state.phase.isTerminal) return;

    // One turn at a time. Without this, a final transcript and the release of
    // the talk button can both start a turn and corrupt the engine.
    if (_turnInFlight) {
      Log.w('ignored a second submit while a turn was in flight');
      return;
    }

    if (text.isEmpty) {
      _set(state.copyWith(phase: VoicePhase.idle, partial: ''));
      return;
    }

    _turnInFlight = true;
    final seq = ++_turnSeq;

    final transcriptMs = _sttStopwatch?.elapsedMilliseconds ?? 0;
    _sttStopwatch = null;

    try {
      // A retry re-sends the same words; do not show them twice.
      final turns = isRetry
          ? state.turns
          : [
              ...state.turns,
              Turn(speaker: Speaker.user, text: text, at: DateTime.now()),
            ];

      _set(state.copyWith(
        turns: turns,
        partial: '',
        phase: VoicePhase.processing,
        levels: const [],
        clearFailure: true,
      ));

      // Peek, do not commit: if the actor never answers, the objection this
      // directive would raise must stay pending rather than being consumed.
      final openObjectionId = _engine.pendingObjection?.id;
      final directive = _engine.peekDirective();

      final actorWatch = Stopwatch()..start();
      ActorReply reply;
      try {
        reply = await _actor.respond(
          scenario: state.scenario,
          directive: directive,
          history: turns,
          systemPrompt: _systemPrompt,
        );
      } on Failure catch (f) {
        _retryText = text;
        _set(state.copyWith(phase: VoicePhase.error, failure: f));
        return;
      } on Object catch (e, st) {
        Log.e('actor turn failed', e, st);
        _retryText = text;
        _set(state.copyWith(
            phase: VoicePhase.error, failure: const AiUnavailableFailure()));
        return;
      }
      actorWatch.stop();

      // The session may have ended, or a newer turn started, while we waited.
      if (_disposed || seq != _turnSeq || state.phase.isTerminal) return;

      // The line exists, so the directive really happened.
      _engine
        ..commitDirective(directive)
        ..recordUserTurnAgainst(reply.signal, openObjectionId);

      final observed = reply.signal.evidence;
      if (observed != null) {
        _evidence.add('Turn ${_engine.userTurns}: $observed');
      }

      // The engine, not the model, decides whether a pitfall really fired.
      final pitfall = _engine.pendingContingency;
      _set(pitfall == null
          ? state.copyWith(clearPitfall: true)
          : state.copyWith(lastPitfall: pitfall));
      if (pitfall != null) {
        _track(AnalyticsEvent.pitfallDetected, {
          'scenario': state.scenario.id,
          'pitfall': pitfall.id,
          'turn': _engine.userTurns,
        });
      }

      final speechMs = await _deliver(reply.text, seq: seq);

      if (_disposed || seq != _turnSeq) return;

      final timing = TurnTiming(
        transcriptMs: transcriptMs,
        actorMs: actorWatch.elapsedMilliseconds,
        speechMs: speechMs,
      );
      _set(state.copyWith(lastTiming: timing));

      _track(AnalyticsEvent.voiceTurnCompleted, {
        'scenario': state.scenario.id,
        'turn': _engine.userTurns,
        ...timing.toJson(),
      });

      if (directive.shouldClose) {
        _engine.completeNaturally();
        _turnInFlight = false;
        await finish(EndReason.resolved);
        return;
      }
    } finally {
      _turnInFlight = false;
    }
  }

  /// Say a line, show it, and report how long the audio took.
  Future<int> _deliver(String text, {int? seq}) async {
    if (_disposed) return 0;

    final turn =
        Turn(speaker: Speaker.actor, text: plainSpeech(text), at: DateTime.now());
    _set(state.copyWith(
      turns: [...state.turns, turn],
      phase: VoicePhase.speaking,
      pressure: _engine.pressure,
      emotion: _engine.emotion,
    ));

    final watch = Stopwatch()..start();

    final voiceOn =
        await ref.read(profileRepositoryProvider).voiceOutputEnabled();
    if (voiceOn) {
      try {
        await _voice.speak(text, voice: state.scenario.actor.voice);
      } on Failure catch (f) {
        // The line is already on screen, so this degrades rather than blocks.
        _set(state.copyWith(failure: f));
      } on Object catch (e, st) {
        Log.e('speaking failed', e, st);
        _set(state.copyWith(failure: VoiceFailure.synthesisFailed));
      }
    }
    watch.stop();

    if (_disposed) return watch.elapsedMilliseconds;

    // A newer turn, or the end of the session, owns the state now.
    if (seq != null && seq != _turnSeq) return watch.elapsedMilliseconds;
    if (!state.phase.isTerminal) {
      _set(state.copyWith(phase: VoicePhase.idle));
    }
    return watch.elapsedMilliseconds;
  }

  /// End the conversation and run analysis.
  Future<String?> finish(EndReason reason) async {
    if (state.isFinished) return state.sessionId;

    await _recognizer.cancel();
    await _voice.stop();
    if (!_engine.isFinished) _engine.endSession(reason);

    _set(state.copyWith(
      phase: VoicePhase.completed,
      analysing: true,
      sessionId: _sessionId,
    ));

    // A session the user walked out of is a different signal from one that
    // reached its natural end, and the difference matters for retention.
    final abandoned = reason != EndReason.resolved && _engine.userTurns == 0;
    _track(
      abandoned
          ? AnalyticsEvent.practiceAbandoned
          : AnalyticsEvent.practiceCompleted,
      {
        'scenario': state.scenario.id,
        'difficulty': state.difficulty.name,
        'turns': _engine.userTurns,
        'objectionsHandled': _engine.handledObjectionIds.length,
        'endReason': reason.name,
      },
    );

    var session = PracticeSession(
      id: _sessionId,
      scenarioId: state.scenario.id,
      scenarioTitle: state.scenario.title,
      difficulty: state.difficulty,
      startedAt: _startedAt,
      endedAt: DateTime.now(),
      endReason: reason,
      turns: state.turns,
      objectionsRaised: _engine.raisedObjectionIds.length,
      objectionsHandled: _engine.handledObjectionIds.length,
    );

    // Save the transcript first: analysis can fail, the record should not.
    final repo = ref.read(sessionRepositoryProvider);
    try {
      await repo.save(session);
    } on Failure catch (f) {
      Log.e('could not save session: ${f.message}');
    }

    final analysis = await _analyse(session);
    session = session.copyWith(analysis: analysis);

    try {
      await repo.save(session);
    } on Failure catch (f) {
      Log.e('could not save analysis: ${f.message}');
    }

    _track(AnalyticsEvent.sessionCompleted, {
      'scenario': state.scenario.id,
      'overall': analysis.overall,
      'analysed': analysis.overall > 0,
    });

    // Everything downstream — the analysis screen, history, progress, the next
    // recommendation, the weekly allowance — reads cached providers. Without
    // this the session that was just saved is invisible to all of them.
    ref
      ..invalidate(sessionsProvider)
      ..invalidate(profileProvider)
      ..invalidate(nextPracticeProvider)
      ..invalidate(allowanceProvider);

    await _recordRetentionMoment(analysis);

    if (!_disposed) _set(state.copyWith(analysing: false));
    return _sessionId;
  }

  /// Turn the result into the moment that would bring the user back.
  ///
  /// Built from the skill the analysis actually identified, so the copy is never
  /// a generic "come back". No push provider is attached in this build — the
  /// scheduler records the moment and stops there.
  Future<void> _recordRetentionMoment(SessionAnalysis analysis) async {
    if (analysis.overall == 0) return;

    try {
      final next = await ref.read(nextPracticeProvider.future);
      final notification = RetentionCopy.forSkillGap(
        skillLabel: analysis.nextSkill.label,
        scenarioTitle: next.scenario.title,
        scenarioId: next.scenario.id,
      );
      await LocalOnlyScheduler(ref.read(analyticsProvider))
          .schedule(notification);
    } on Object catch (e, s) {
      // Retention is never allowed to break finishing a session.
      Log.w('could not record retention moment: $e');
      Log.e('retention', e, s);
    }
  }

  Future<SessionAnalysis> _analyse(PracticeSession session) async {
    // Nothing meaningful was said — score honestly instead of inventing.
    if (session.userTurnCount == 0) {
      return AnalysisParser.fallback(
        focus: state.scenario.rubricFocus,
        pitfalls: _engine.committedPitfalls,
      );
    }

    try {
      final raw = await _actor.analyse(AnalysisPrompt.build(
        scenario: state.scenario,
        session: session,
        engine: _engine,
        turnEvidence: _evidence,
      ));
      return AnalysisParser.parse(
        raw,
        focus: state.scenario.rubricFocus,
        pitfalls: _engine.committedPitfalls,
      );
    } on Failure catch (f) {
      Log.w('analysis unavailable: ${f.message}');
      return AnalysisParser.fallback(
        focus: state.scenario.rubricFocus,
        pitfalls: _engine.committedPitfalls,
      );
    } on Object catch (e, s) {
      Log.e('analysis failed', e, s);
      return AnalysisParser.fallback(
        focus: state.scenario.rubricFocus,
        pitfalls: _engine.committedPitfalls,
      );
    }
  }

  void _track(AnalyticsEvent e, [Map<String, Object?> props = const {}]) =>
      ref.read(analyticsProvider).track(e, props);

  void _set(PracticeState next) {
    if (_disposed) return;
    state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    unawaited(_recognizer.cancel());
    unawaited(_voice.stop());
    super.dispose();
  }
}

final practiceControllerProvider = StateNotifierProvider.autoDispose
    .family<PracticeController, PracticeState, PracticeArgs>((ref, args) {
  final scenario =
      ref.watch(scenariosProvider).firstWhere((s) => s.id == args.scenarioId);

  return PracticeController(
    scenario: scenario,
    difficulty: args.difficulty,
    recognizer: ref.watch(speechRecognizerProvider),
    voice: ref.watch(voiceSynthesizerProvider),
    actor: ref.watch(actorServiceProvider),
    ref: ref,
  );
});

/// Dashes are a writer's habit, not a speaker's. A line shown large on
/// screen and read aloud should be plain sentences.
String plainSpeech(String text) => text
    .replaceAll(RegExp(r'\s*[—–]\s*'), ', ')
    .replaceAll(RegExp(r'\s*--\s*'), ', ')
    .replaceAll(', ,', ',');
