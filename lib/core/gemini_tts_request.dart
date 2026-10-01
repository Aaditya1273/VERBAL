import 'dart:convert';

import 'config.dart';

/// Speech from Gemini, using the key VERBAL already has for the actor.
///
/// This exists because ElevenLabs will not serve library voices to a free
/// account (HTTP 402), which leaves a voice-first product with a robotic device
/// voice. Gemini's TTS models need no second account, no second key and no new
/// dependency — and they return ready-to-play WAV rather than raw PCM.
///
/// Pure Dart so `tool/integration_check.dart` can exercise the real request.
class GeminiTtsRequest {
  const GeminiTtsRequest._();

  /// Lite tier: this is on the critical path of a spoken conversation.
  static const model = 'gemini-3.8-flash-lite-tts';

  static const timeout = Duration(seconds: 20);

  /// A sensible default when a scenario has not chosen a voice.
  static const defaultVoice = 'Kore';

  static Uri uri(String model) => Uri.https('generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent');

  static Map<String, String> headers(AppConfig config) => {
        // Header, never a query parameter — keeps the key out of proxy logs.
        'x-goog-api-key': config.geminiApiKey,
        'Content-Type': 'application/json',
      };

  static String body(String text, {String voice = defaultVoice}) => jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': text}
            ]
          }
        ],
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voice},
            },
          },
        },
      });

  /// Pulls the audio out of a Gemini response.
  ///
  /// Returns null rather than throwing: a refusal, a safety block or a quota
  /// error all arrive as a 200 with no audio part, and the caller's job is to
  /// fall back rather than to crash.
  static List<int>? audioFrom(String responseBody) {
    try {
      final body = jsonDecode(responseBody);
      if (body is! Map) return null;

      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;

      final parts = (candidates.first as Map)['content']?['parts'];
      if (parts is! List || parts.isEmpty) return null;

      for (final part in parts.whereType<Map>()) {
        // The REST API has used both spellings over time.
        final inline = part['inlineData'] ?? part['inline_data'];
        if (inline is Map && inline['data'] is String) {
          return base64Decode(inline['data'] as String);
        }
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// True when the bytes are a RIFF/WAVE container the player can handle.
  static bool looksLikeWav(List<int> bytes) =>
      bytes.length > 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x41 && // A
      bytes[10] == 0x56 && // V
      bytes[11] == 0x45; // E
}
