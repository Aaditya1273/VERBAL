import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:verbal/core/config.dart';
import 'package:verbal/core/elevenlabs_request.dart';
import 'package:verbal/core/failures.dart';
import 'package:verbal/core/gemini_tts_request.dart';
import 'package:verbal/core/voice.dart';
import 'package:verbal/domain/scenario_library.dart';

void main() {
  // Deliberately no TestWidgetsFlutterBinding.ensureInitialized(): it eagerly
  // initialises the audio plugin, which has no implementation in a headless
  // test. NetworkVoice only touches the player once it has audio to play, so
  // the fall-through paths below stay reachable without a device.

  group('speech budget', () {
    test('scales with the length of the line', () {
      final short = DeviceVoice.budgetFor('No.');
      final long = DeviceVoice.budgetFor(
          'I want to acknowledge what you are saying before I explain how the '
          'decision was reached, because I think both things matter here.');

      expect(long, greaterThan(short));
    });

    test('always leaves room for engine start-up', () {
      // A TTS engine that never reports completion must still be given a fair
      // chance before the session moves on.
      expect(DeviceVoice.budgetFor('Hi').inMilliseconds,
          greaterThanOrEqualTo(3000));
    });

    test('handles empty and whitespace input without collapsing to zero', () {
      expect(DeviceVoice.budgetFor('').inMilliseconds, greaterThan(0));
      expect(DeviceVoice.budgetFor('   ').inMilliseconds, greaterThan(0));
    });

    test('stays bounded for a realistic actor line', () {
      // Actor replies are capped at ~55 words by the engine's directive.
      final words = List.filled(55, 'word').join(' ');
      expect(DeviceVoice.budgetFor(words).inSeconds, lessThan(30),
          reason: 'a stuck engine must not hold the session for half a minute');
    });
  });

  group('microphone permission failures', () {
    test('an ordinary denial can be asked about again', () {
      const f = MicrophonePermissionFailure();
      expect(f.permanentlyDenied, isFalse);
      expect(f.message, contains('type your turn'));
    });

    test('a permanent denial points at Settings instead of re-asking', () {
      const f = MicrophonePermissionFailure.permanent();
      expect(f.permanentlyDenied, isTrue);
      expect(f.message.toLowerCase(), contains('settings'));
    });

    test('both remain Failures the UI can render', () {
      expect(const MicrophonePermissionFailure(), isA<Failure>());
      expect(const MicrophonePermissionFailure.permanent(), isA<Failure>());
    });
  });

  group('failure messages', () {
    test('every failure says something a user can act on', () {
      const failures = <Failure>[
        NetworkFailure(),
        AiUnavailableFailure(),
        AiNotConfiguredFailure(),
        VoiceFailure.recognitionUnavailable,
        VoiceFailure.synthesisFailed,
        MicrophonePermissionFailure(),
        MicrophonePermissionFailure.permanent(),
        StorageFailure(),
        BillingFailure.unavailable,
        AnalysisFailure(),
      ];

      for (final f in failures) {
        expect(f.message, isNotEmpty, reason: '$f');
        // No raw exception text or stack traces leaking into the UI.
        expect(f.message, isNot(contains('Exception')), reason: '$f');
        expect(f.message, isNot(contains('#0')), reason: '$f');
        expect(f.message.length, lessThan(200), reason: '$f is a wall of text');
      }
    });
  });

  group('ElevenLabs request shape', () {
    const config = AppConfig(
      geminiApiKey: '',
      elevenLabsApiKey: 'secret',
      elevenLabsVoiceId: 'voice123',
      revenueCatAndroidKey: '',
      revenueCatIosKey: '',
      oneSignalAppId: '',
    );

    test('targets the configured voice', () {
      expect(ElevenLabsRequest.uri(config).toString(), endsWith('/voice123'));
    });

    test('sends the key as a header, never in the URL', () {
      expect(ElevenLabsRequest.headers(config)['xi-api-key'], 'secret');
      expect(
          ElevenLabsRequest.uri(config).toString(), isNot(contains('secret')));
    });

    test('asks for the low-latency model', () {
      expect(
          ElevenLabsRequest.body('hello'), contains(ElevenLabsRequest.model));
      expect(ElevenLabsRequest.body('hello'), contains('hello'));
    });

    group('audio guard', () {
      test('accepts an ID3-tagged MP3', () {
        expect(
            ElevenLabsRequest.looksLikeMp3([0x49, 0x44, 0x33, 0x04]), isTrue);
      });

      test('accepts a bare MPEG frame sync', () {
        expect(ElevenLabsRequest.looksLikeMp3([0xFF, 0xFB, 0x90]), isTrue);
      });

      test('rejects a JSON error body served with a 200', () {
        // ElevenLabs can answer 200 with JSON; handing that to the player is
        // silence, not an error, which is the worst possible failure mode.
        final json = '{"detail":"nope"}'.codeUnits;
        expect(ElevenLabsRequest.looksLikeMp3(json), isFalse);
      });

      test('rejects empty and truncated bodies', () {
        expect(ElevenLabsRequest.looksLikeMp3([]), isFalse);
        expect(ElevenLabsRequest.looksLikeMp3([0xFF]), isFalse);
      });
    });
  });

  group('Gemini TTS request', () {
    const config = AppConfig(
      geminiApiKey: 'gkey',
      elevenLabsApiKey: '',
      elevenLabsVoiceId: '',
      revenueCatAndroidKey: '',
      revenueCatIosKey: '',
      oneSignalAppId: '',
    );

    test('sends the key as a header, never in the URL', () {
      expect(GeminiTtsRequest.headers(config)['x-goog-api-key'], 'gkey');
      expect(GeminiTtsRequest.uri(GeminiTtsRequest.model).toString(),
          isNot(contains('gkey')));
    });

    test('asks for audio, with the named voice', () {
      final body = GeminiTtsRequest.body('hello', voice: 'Puck');
      expect(body, contains('AUDIO'));
      expect(body, contains('Puck'));
      expect(body, contains('hello'));
    });

    test('defaults the voice when none is given', () {
      expect(
          GeminiTtsRequest.body('hi'), contains(GeminiTtsRequest.defaultVoice));
    });

    group('response parsing', () {
      String responseWith(String base64) =>
          '{"candidates":[{"content":{"parts":[{"inlineData":'
          '{"mimeType":"audio/wav","data":"$base64"}}]}}]}';

      test('extracts the audio', () {
        final wav = base64Encode(utf8.encode('RIFF....WAVErest'));
        final audio = GeminiTtsRequest.audioFrom(responseWith(wav));

        expect(audio, isNotNull);
        expect(GeminiTtsRequest.looksLikeWav(audio!), isTrue);
      });

      test('accepts the snake_case spelling the REST API also uses', () {
        final wav = base64Encode(utf8.encode('RIFF....WAVEx'));
        final body = '{"candidates":[{"content":{"parts":[{"inline_data":'
            '{"data":"$wav"}}]}}]}';
        expect(GeminiTtsRequest.audioFrom(body), isNotNull);
      });

      test('returns null for a refusal or a block, rather than throwing', () {
        // A safety block, a quota error and a text-only reply all arrive as a
        // 200 with no audio part. The caller falls back; it must not crash.
        for (final body in [
          '{"candidates":[]}',
          '{"candidates":[{"content":{"parts":[{"text":"I cannot."}]}}]}',
          '{"promptFeedback":{"blockReason":"SAFETY"}}',
          'not json at all',
          '',
        ]) {
          expect(GeminiTtsRequest.audioFrom(body), isNull, reason: body);
        }
      });
    });

    group('audio guard', () {
      test('accepts a RIFF/WAVE container', () {
        expect(
            GeminiTtsRequest.looksLikeWav(
                utf8.encode('RIFF\u0000\u0000\u0000\u0000WAVEfmt ')),
            isTrue);
      });

      test('rejects MP3, JSON and truncated bodies', () {
        expect(GeminiTtsRequest.looksLikeWav([0xFF, 0xFB, 0x90]), isFalse);
        expect(
            GeminiTtsRequest.looksLikeWav(utf8.encode('{"error":1}')), isFalse);
        expect(GeminiTtsRequest.looksLikeWav(utf8.encode('RIFF')), isFalse);
        expect(GeminiTtsRequest.looksLikeWav([]), isFalse);
      });
    });
  });

  group('casting', () {
    test('every actor has a voice', () {
      for (final s in ScenarioLibrary.all) {
        expect(s.actor.voice.trim(), isNotEmpty, reason: s.id);
      }
    });

    test('characters do not all sound like the same person', () {
      final voices = ScenarioLibrary.all.map((s) => s.actor.voice).toSet();
      expect(voices.length, ScenarioLibrary.all.length,
          reason: 'a voice-first rehearsal needs distinct characters');
    });
  });

  group('provider fall-through', () {
    // The chain is built inside out: elevenlabs -> gemini -> device. An earlier
    // version dead-ended ElevenLabs straight onto the device voice, so a
    // blocked ElevenLabs account never reached Gemini at all.
    test('a provider that cannot serve hands off to the next', () async {
      final next = _RecordingFallback();
      final voice = NetworkVoice(
        label: 'blocked',
        fallback: next,
        fetch: (text, v) async => null,
      );

      await voice.speak('You never told me this was serious.', voice: 'Leda');

      expect(next.spoken, ['You never told me this was serious.']);
      expect(next.voices, ['Leda'],
          reason: 'the character must not change on the way down the chain');
    });

    test('a thrown request also hands off rather than failing the turn',
        () async {
      final next = _RecordingFallback();
      final voice = NetworkVoice(
        label: 'exploding',
        fallback: next,
        fetch: (text, v) async => throw Exception('network down'),
      );

      await voice.speak('hello');

      expect(next.spoken, ['hello']);
    });

    test('three layers chain all the way down', () async {
      final device = _RecordingFallback();
      final gemini = NetworkVoice(
        label: 'gemini-tts',
        fallback: device,
        fetch: (text, v) async => null,
      );
      final elevenLabs = NetworkVoice(
        label: 'elevenlabs',
        fallback: gemini,
        fetch: (text, v) async => null,
      );

      await elevenLabs.speak('a line', voice: 'Puck');

      expect(device.spoken, ['a line'],
          reason: 'both network layers declined, so the device speaks');
    });

    test('a cancelled turn does not reach the fallback', () async {
      final next = _RecordingFallback();
      final voice = NetworkVoice(
        label: 'slow',
        fallback: next,
        fetch: (text, v) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return null;
        },
      );

      final speaking = voice.speak('abandoned');
      await voice.stop();
      await speaking;

      expect(next.spoken, isEmpty,
          reason:
              'the user ended the session; nothing should still be talking');
    });

    test('empty text is not spoken by anyone', () async {
      final next = _RecordingFallback();
      final voice = NetworkVoice(
        label: 'x',
        fallback: next,
        fetch: (text, v) async => null,
      );

      await voice.speak('   ');

      expect(next.spoken, isEmpty);
    });
  });
}

class _RecordingFallback implements VoiceSynthesizer {
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
