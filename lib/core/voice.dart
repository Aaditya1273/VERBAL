import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'config.dart';
import 'elevenlabs_request.dart';
import 'gemini_tts_request.dart';
import 'failures.dart';
import 'logger.dart';

/// What the recogniser heard, so far.
class Heard {
  const Heard({required this.text, required this.isFinal, this.level = 0});

  final String text;
  final bool isFinal;

  /// 0..1 input level, for the waveform.
  final double level;
}

/// Turns the user's speech into text.
abstract class SpeechRecognizer {
  Future<bool> prepare();
  Stream<Heard> get heard;
  Future<void> start();
  Future<void> stop();
  Future<void> cancel();
  bool get isListening;
  Future<void> dispose();
}

/// On-device recognition.
///
/// Deliberately not a cloud STT call: it is free, it has no per-turn latency
/// cost, and the user's speech never leaves the phone before they finish
/// speaking. Only the finished text is sent to the actor model.
class DeviceSpeechRecognizer implements SpeechRecognizer {
  DeviceSpeechRecognizer();

  final _speech = stt.SpeechToText();
  final _controller = StreamController<Heard>.broadcast();
  bool _available = false;

  @override
  Stream<Heard> get heard => _controller.stream;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> prepare() async {
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied || status.isRestricted) {
      throw const MicrophonePermissionFailure.permanent();
    }
    if (!status.isGranted) throw const MicrophonePermissionFailure();

    try {
      _available = await _speech.initialize(
        onError: (e) {
          Log.w('stt error: ${e.errorMsg}');
          // A no-match is a normal outcome, not a failure worth surfacing.
          if (e.errorMsg != 'error_no_match' && !_controller.isClosed) {
            _controller.addError(VoiceFailure.recognitionUnavailable);
          }
        },
        onStatus: (s) => Log.d('stt status: $s'),
      );
    } on Object catch (e, s) {
      Log.e('stt init failed', e, s);
      _available = false;
    }

    if (!_available) throw VoiceFailure.recognitionUnavailable;
    return _available;
  }

  @override
  Future<void> start() async {
    if (!_available) await prepare();
    await _speech.listen(
      onResult: (r) {
        if (_controller.isClosed) return;
        _controller.add(Heard(
          text: r.recognizedWords,
          isFinal: r.finalResult,
        ));
      },
      onSoundLevelChange: (level) {
        if (_controller.isClosed) return;
        // Platform levels are roughly -2..10; normalise for the waveform.
        _controller.add(Heard(
          text: '',
          isFinal: false,
          level: ((level + 2) / 12).clamp(0.0, 1.0),
        ));
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(minutes: 2),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  @override
  Future<void> dispose() async {
    await _speech.cancel();
    await _controller.close();
  }
}

/// Speaks the actor's replies.
abstract class VoiceSynthesizer {
  /// Completes when the line has finished playing.
  ///
  /// [voice] names the character speaking, where the provider supports it. A
  /// rehearsal falls apart if every character sounds like the same person, so
  /// this is a per-line property rather than a global setting.
  Future<void> speak(String text, {String? voice});
  Future<void> stop();
  Future<void> dispose();
}

/// The device's built-in voice. Always available, no key, no network.
class DeviceVoice implements VoiceSynthesizer {
  DeviceVoice() {
    unawaited(_configure());
  }

  final _tts = FlutterTts();
  bool _stopped = false;

  Future<void> _configure() async {
    try {
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } on Object catch (e) {
      Log.w('tts configuration failed: $e');
    }
  }

  /// Rough upper bound on how long a line can take to read aloud, so a TTS
  /// engine that never reports completion cannot strand the session.
  static Duration budgetFor(String text) {
    final words = text.trim().split(RegExp(r'\s+')).length;
    // ~150 wpm plus a fixed allowance for engine start-up.
    return Duration(milliseconds: 3000 + (words * 400));
  }

  @override
  Future<void> speak(String text, {String? voice}) async {
    if (text.trim().isEmpty) return;
    _stopped = false;
    try {
      await _tts.speak(text).timeout(budgetFor(text), onTimeout: () async {
        Log.w('device tts did not report completion; continuing');
        await _tts.stop();
        return null;
      });
    } on Object catch (e, s) {
      if (_stopped) return;
      Log.e('device tts failed', e, s);
      throw VoiceFailure.synthesisFailed;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    try {
      await _tts.stop();
    } on Object catch (e) {
      Log.w('tts stop failed: $e');
    }
  }

  @override
  Future<void> dispose() => stop();
}

/// Fetches audio for a line, or null when this provider cannot serve it.
typedef AudioFetcher = Future<List<int>?> Function(String text, String? voice);

/// A voice that fetches audio over the network and plays it, falling back to
/// the device voice whenever the network cannot deliver.
///
/// One implementation, two providers. The playback guards below — completion,
/// cancellation and a hard budget all resolving the same future — are the
/// fiddly part, and writing them twice is how one copy ends up deadlocking.
class NetworkVoice implements VoiceSynthesizer {
  NetworkVoice({
    required AudioFetcher fetch,
    required VoiceSynthesizer fallback,
    required this.label,
  })  : _fetch = fetch,
        _fallback = fallback;

  /// ElevenLabs. Free accounts cannot use library voices and will 402 here,
  /// which is a fall back, not a crash.
  factory NetworkVoice.elevenLabs({
    required AppConfig config,
    required VoiceSynthesizer fallback,
    http.Client? client,
  }) {
    final c = client ?? http.Client();
    return NetworkVoice(
      label: 'elevenlabs',
      fallback: fallback,
      fetch: (text, voice) async {
        final r = await c
            .post(
              ElevenLabsRequest.uri(config),
              headers: ElevenLabsRequest.headers(config),
              body: ElevenLabsRequest.body(text),
            )
            .timeout(ElevenLabsRequest.timeout);

        // A JSON error body can arrive with a 200; handing that to the player
        // produces silence rather than an error.
        if (r.statusCode != 200 ||
            !ElevenLabsRequest.looksLikeMp3(r.bodyBytes)) {
          Log.w('elevenlabs ${r.statusCode}: no playable audio');
          return null;
        }
        return r.bodyBytes;
      },
    );
  }

  /// Gemini TTS, on the key the actor already uses. No second account.
  factory NetworkVoice.gemini({
    required AppConfig config,
    required VoiceSynthesizer fallback,
    http.Client? client,
    String model = GeminiTtsRequest.model,
  }) {
    final c = client ?? http.Client();
    return NetworkVoice(
      label: 'gemini-tts',
      fallback: fallback,
      fetch: (text, voice) async {
        final r = await c
            .post(
              GeminiTtsRequest.uri(model),
              headers: GeminiTtsRequest.headers(config),
              body: GeminiTtsRequest.body(text,
                  voice: voice ?? GeminiTtsRequest.defaultVoice),
            )
            .timeout(GeminiTtsRequest.timeout);

        if (r.statusCode != 200) {
          Log.w('gemini tts ${r.statusCode}');
          return null;
        }
        final audio = GeminiTtsRequest.audioFrom(r.body);
        if (audio == null || !GeminiTtsRequest.looksLikeWav(audio)) {
          Log.w('gemini tts returned no playable audio');
          return null;
        }
        return audio;
      },
    );
  }

  final AudioFetcher _fetch;
  final VoiceSynthesizer _fallback;

  /// Named in logs so a failure says which provider gave up.
  final String label;

  /// Created on first play, not on construction.
  ///
  /// A voice that always falls through — a blocked ElevenLabs account, say —
  /// should not allocate an audio player it never uses, and constructing one
  /// touches platform channels that do not exist off-device.
  AudioPlayer? _playerOrNull;
  AudioPlayer get _player => _playerOrNull ??= AudioPlayer();

  StreamSubscription<void>? _completeSub;
  Completer<void>? _playback;
  bool _stopped = false;

  @override
  Future<void> speak(String text, {String? voice}) async {
    if (text.trim().isEmpty) return;
    _stopped = false;

    List<int>? audio;
    try {
      audio = await _fetch(text, voice);
    } on TimeoutException {
      Log.w('$label timed out; using device voice');
    } on Object catch (e, s) {
      Log.e('$label request failed', e, s);
    }

    // Cancelled while the request was in flight.
    if (_stopped) return;

    if (audio == null) {
      await _fallback.speak(text, voice: voice);
      return;
    }

    await _play(audio, text, voice);
  }

  /// Play the audio, bounded.
  ///
  /// `onPlayerComplete` can simply never fire — audio focus loss, a corrupt
  /// buffer, a stop() from another turn. Awaiting it unguarded strands the
  /// session on "speaking" forever.
  Future<void> _play(List<int> bytes, String text, String? voice) async {
    final playback = Completer<void>();
    _playback = playback;

    void finish() {
      if (!playback.isCompleted) playback.complete();
    }

    try {
      await _completeSub?.cancel();
      _completeSub = _player.onPlayerComplete.listen(
        (_) => finish(),
        onError: (Object e) {
          Log.w('$label playback error: $e');
          finish();
        },
      );

      await _player.play(BytesSource(Uint8List.fromList(bytes)));

      await playback.future.timeout(
        DeviceVoice.budgetFor(text),
        onTimeout: () {
          Log.w('$label playback did not complete in budget; moving on');
          unawaited(_player.stop());
        },
      );
    } on Object catch (e, s) {
      Log.e('$label playback failed', e, s);
      if (!_stopped) await _fallback.speak(text, voice: voice);
    } finally {
      await _completeSub?.cancel();
      _completeSub = null;
      _playback = null;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    // Release anyone awaiting playback before tearing the player down.
    final pending = _playback;
    if (pending != null && !pending.isCompleted) pending.complete();
    try {
      await _playerOrNull?.stop();
    } on Object catch (e) {
      Log.w('$label player stop failed: $e');
    }
    await _fallback.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _completeSub?.cancel();
    await _playerOrNull?.dispose();
    await _fallback.dispose();
  }
}
