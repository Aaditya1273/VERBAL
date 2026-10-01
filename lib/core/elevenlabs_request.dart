import 'dart:convert';

import 'config.dart';

/// How VERBAL asks ElevenLabs for speech.
///
/// Pure Dart, in its own file, for one reason: `voice.dart` imports
/// `audioplayers` and `flutter_tts`, which drag in `dart:ui` and make the whole
/// integration unreachable from a command-line tool. Keeping the request shape
/// here means `tool/integration_check.dart` exercises the *same* URL, headers
/// and body the app sends, instead of a copy that can drift out of sync.
///
/// Playback is not covered here — that genuinely needs a device.
class ElevenLabsRequest {
  const ElevenLabsRequest._();

  /// Low-latency model. This sits on the critical path of a spoken
  /// conversation, so quality is traded for time on purpose.
  static const model = 'eleven_turbo_v2_5';

  static const timeout = Duration(seconds: 12);

  static Uri uri(AppConfig config) => Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/${config.elevenLabsVoiceId}');

  static Map<String, String> headers(AppConfig config) => {
        'xi-api-key': config.elevenLabsApiKey,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
      };

  static String body(String text) => jsonEncode({
        'text': text,
        'model_id': model,
        'voice_settings': {
          'stability': 0.45,
          'similarity_boost': 0.75,
          'style': 0.35,
        },
      });

  /// True when the bytes returned actually look like playable MP3.
  ///
  /// A 200 with a JSON error body would otherwise be handed to the audio player
  /// as if it were sound.
  static bool looksLikeMp3(List<int> bytes) {
    if (bytes.length < 3) return false;
    // "ID3" tag, or an MPEG frame sync (11 set bits).
    final id3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final frameSync = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
    return id3 || frameSync;
  }
}
