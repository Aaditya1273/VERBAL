import 'analysis.dart';
import 'conversation_engine.dart';
import 'difficulty.dart';

enum Speaker { user, actor }

/// One utterance in a practice conversation.
class Turn {
  const Turn({
    required this.speaker,
    required this.text,
    required this.at,
    this.isPartial = false,
  });

  final Speaker speaker;
  final String text;
  final DateTime at;

  /// True while speech recognition is still refining this turn.
  final bool isPartial;

  Turn copyWith({String? text, bool? isPartial}) => Turn(
        speaker: speaker,
        text: text ?? this.text,
        at: at,
        isPartial: isPartial ?? this.isPartial,
      );

  Map<String, dynamic> toJson() => {
        'speaker': speaker.name,
        'text': text,
        'at': at.toIso8601String(),
      };

  factory Turn.fromJson(Map<String, dynamic> json) => Turn(
        speaker: json['speaker'] == 'user' ? Speaker.user : Speaker.actor,
        text: json['text'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// A completed (or in-flight) practice session.
class PracticeSession {
  const PracticeSession({
    required this.id,
    required this.scenarioId,
    required this.scenarioTitle,
    required this.difficulty,
    required this.startedAt,
    required this.turns,
    this.endedAt,
    this.endReason,
    this.analysis,
    this.objectionsRaised = 0,
    this.objectionsHandled = 0,
  });

  final String id;
  final String scenarioId;
  final String scenarioTitle;
  final Difficulty difficulty;
  final DateTime startedAt;
  final DateTime? endedAt;
  final EndReason? endReason;
  final List<Turn> turns;
  final SessionAnalysis? analysis;
  final int objectionsRaised;
  final int objectionsHandled;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  int get userTurnCount => turns.where((t) => t.speaker == Speaker.user).length;

  bool get isComplete => endedAt != null;

  PracticeSession copyWith({
    DateTime? endedAt,
    EndReason? endReason,
    List<Turn>? turns,
    SessionAnalysis? analysis,
    int? objectionsRaised,
    int? objectionsHandled,
  }) =>
      PracticeSession(
        id: id,
        scenarioId: scenarioId,
        scenarioTitle: scenarioTitle,
        difficulty: difficulty,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        endReason: endReason ?? this.endReason,
        turns: turns ?? this.turns,
        analysis: analysis ?? this.analysis,
        objectionsRaised: objectionsRaised ?? this.objectionsRaised,
        objectionsHandled: objectionsHandled ?? this.objectionsHandled,
      );

  /// Plain transcript, used for analysis requests and the session detail view.
  String get transcript => turns
      .where((t) => !t.isPartial && t.text.trim().isNotEmpty)
      .map((t) => '${t.speaker == Speaker.user ? 'YOU' : 'THEM'}: ${t.text}')
      .join('\n');
}

/// The single authoritative state of a practice session.
///
/// One enum, not a phase plus a scattering of booleans — that is what allows
/// contradictions like "listening" while the actor is still speaking.
enum VoicePhase {
  idle,
  listening,
  processing,
  speaking,
  paused,
  completed,
  error,
}

extension VoicePhaseLabel on VoicePhase {
  String get label => switch (this) {
        VoicePhase.idle => 'READY',
        VoicePhase.listening => 'LISTENING',
        VoicePhase.processing => 'THINKING',
        VoicePhase.speaking => 'SPEAKING',
        VoicePhase.paused => 'PAUSED',
        VoicePhase.completed => 'COMPLETE',
        VoicePhase.error => 'ERROR',
      };

  /// The session has ended; no further turns are accepted.
  bool get isTerminal => this == VoicePhase.completed;

  /// The microphone is live.
  bool get isCapturing => this == VoicePhase.listening;

  /// The app is working and must not accept a new turn.
  bool get isBusy =>
      this == VoicePhase.processing || this == VoicePhase.speaking;
}

/// How long each stage of one turn took.
///
/// Recorded from real clocks so latency can be measured on a device rather
/// than estimated. Nothing here is synthesised.
class TurnTiming {
  const TurnTiming({
    required this.transcriptMs,
    required this.actorMs,
    required this.speechMs,
  });

  /// Stop-speaking → final transcript in hand.
  final int transcriptMs;

  /// Request sent → actor reply parsed.
  final int actorMs;

  /// Reply in hand → audio finished.
  final int speechMs;

  /// Stop-speaking → audio started, which is the number the user feels.
  int get toFirstAudioMs => transcriptMs + actorMs;

  int get totalMs => transcriptMs + actorMs + speechMs;

  Map<String, Object?> toJson() => {
        'transcriptMs': transcriptMs,
        'actorMs': actorMs,
        'speechMs': speechMs,
        'toFirstAudioMs': toFirstAudioMs,
      };
}
