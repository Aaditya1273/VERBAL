// ignore_for_file: avoid_print — this is a CLI; stdout is the whole point.

// Checks every external service VERBAL claims to use, against the real thing.
//
//   set -a && . ./.env.local && set +a
//   dart run tool/integration_check.dart
//
// Each service reports one of:
//   PASS   exercised against the live API and it worked
//   FAIL   exercised and it did not work — details follow
//   SKIP   no key configured; the app's documented fallback applies
//   LOCAL  only the key shape could be checked here; see the note
//
// LOCAL is not a pass. A purchase flow cannot be exercised without a device and
// a store account, and saying otherwise would be the kind of claim this repo
// exists not to make.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:verbal/core/config.dart';
import 'package:verbal/core/elevenlabs_request.dart';
import 'package:verbal/core/gemini_tts_request.dart';
import 'package:verbal/core/failures.dart';
import 'package:verbal/data/remote/actor_service.dart';
import 'package:verbal/domain/actor_prompt.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/domain/session.dart';

enum Verdict { pass, fail, skip, local }

class Check {
  Check(this.service, this.verdict, this.detail, {this.note});

  final String service;
  final Verdict verdict;
  final String detail;
  final String? note;
}

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final config = AppConfig(
    geminiApiKey: _arg(args, 'gemini') ?? env['GEMINI_API_KEY'] ?? '',
    elevenLabsApiKey: env['ELEVENLABS_API_KEY'] ?? '',
    elevenLabsVoiceId: env['ELEVENLABS_VOICE_ID'] ?? '21m00Tcm4TlvDq8ikWAM',
    revenueCatAndroidKey: env['REVENUECAT_ANDROID_KEY'] ?? '',
    revenueCatIosKey: env['REVENUECAT_IOS_KEY'] ?? '',
    oneSignalAppId: env['ONESIGNAL_APP_ID'] ?? '',
  );

  final model = _arg(args, 'model') ?? GeminiActorService.defaultModel;

  print('VERBAL integration check');
  print('${DateTime.now().toIso8601String()}\n');

  final checks = <Check>[
    await _gemini(config, model),
    await _elevenLabsAccount(config),
    await _elevenLabsVoice(config),
    await _elevenLabsSynthesis(config),
    await _geminiTts(config),
    await _revenueCat(config),
    _oneSignal(config),
  ];

  print('\n${'=' * 72}');
  for (final c in checks) {
    print('${_tag(c.verdict)}  ${c.service.padRight(26)} ${c.detail}');
    if (c.note != null) print('      ${' ' * 26} ${c.note}');
  }

  final remedies = checks
      .where((c) => c.verdict == Verdict.fail)
      .map(_remedy)
      .whereType<String>()
      .toSet();
  if (remedies.isNotEmpty) {
    print('\nTo fix:');
    for (final r in remedies) {
      print('  - $r');
    }
  }

  final failed = checks.where((c) => c.verdict == Verdict.fail).length;
  final passed = checks.where((c) => c.verdict == Verdict.pass).length;
  print('=' * 72);
  print('$passed exercised live, $failed failed, '
      '${checks.length - passed - failed} not exercised here.');

  exit(failed == 0 ? 0 : 1);
}

/// The shortest path from a failure to a working integration.
String? _remedy(Check c) {
  if (!c.service.startsWith('ElevenLabs')) return null;
  return 'ElevenLabs free plans cannot use library voices through the API. '
      'This is not blocking: the app falls through to Gemini TTS, which needs '
      'no second account. Only worth fixing if you want ElevenLabs specifically '
      '— add voices_read to the key and use a voice you generated yourself.';
}

String _tag(Verdict v) => switch (v) {
      Verdict.pass => 'PASS ',
      Verdict.fail => 'FAIL ',
      Verdict.skip => 'SKIP ',
      Verdict.local => 'LOCAL',
    };

/// Retries the transient failures any live check will hit — 429 rate limits and
/// 503s say nothing about whether the integration works. A content block or an
/// auth error is a real finding and is not retried.
Future<T> _withRetry<T>(Future<T> Function() call, {int attempts = 3}) async {
  var delay = const Duration(seconds: 5);
  for (var i = 1;; i++) {
    try {
      return await call();
    } on Failure catch (f) {
      final cause = f.cause?.toString() ?? '';
      final transient = cause.contains('503') || cause.contains('UNAVAILABLE');
      if (!transient || i >= attempts) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
}

/// One real actor turn, through the same service the app uses.
Future<Check> _gemini(AppConfig config, String model) async {
  if (!config.hasAi) {
    return Check('Gemini (actor)', Verdict.skip, 'no key — scripted actor');
  }

  const scenario = ScenarioLibrary.difficultFeedback;
  final engine =
      ConversationEngine(scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

  final watch = Stopwatch()..start();
  try {
    final reply = await _withRetry(
      () => GeminiActorService(config: config, model: model).respond(
        scenario: scenario,
        directive: engine.peekDirective(),
        history: [
          Turn(
              speaker: Speaker.actor,
              text: scenario.openingLine!,
              at: DateTime.now()),
          Turn(
            speaker: Speaker.user,
            text: 'The Aldridge deadline slipped by four days. '
                'This is a performance concern.',
            at: DateTime.now(),
          ),
        ],
        systemPrompt: ActorPrompt.system(
            scenario: scenario, difficulty: Difficulty.moderate),
      ),
    );
    watch.stop();

    final structured = reply.signal.evidence != null;
    return Check(
      'Gemini (actor)',
      structured ? Verdict.pass : Verdict.fail,
      '$model · ${watch.elapsedMilliseconds} ms · '
          '${reply.text.trim().split(RegExp(r"\s+")).length} words',
      note: structured
          ? null
          : 'replied, but returned no structured evidence — schema not honoured',
    );
  } on Failure catch (f) {
    watch.stop();
    return Check('Gemini (actor)', Verdict.fail,
        'failed after ${watch.elapsedMilliseconds} ms',
        note: '${f.message}${f.cause == null ? '' : ' [${f.cause}]'}');
  } on Object catch (e) {
    watch.stop();
    return Check('Gemini (actor)', Verdict.fail,
        'failed after ${watch.elapsedMilliseconds} ms',
        note: '$e');
  }
}

Future<Check> _elevenLabsAccount(AppConfig config) async {
  if (!config.hasPremiumVoice) {
    return Check(
        'ElevenLabs (account)', Verdict.skip, 'no key — device voice used');
  }
  try {
    final r = await http.get(
      Uri.parse('https://api.elevenlabs.io/v1/user/subscription'),
      headers: {'xi-api-key': config.elevenLabsApiKey},
    ).timeout(const Duration(seconds: 15));

    if (r.statusCode != 200) {
      return Check('ElevenLabs (account)', Verdict.fail, 'HTTP ${r.statusCode}',
          note: 'key rejected');
    }
    final used = RegExp(r'"character_count":\s*(\d+)').firstMatch(r.body)?[1];
    final limit = RegExp(r'"character_limit":\s*(\d+)').firstMatch(r.body)?[1];
    final tier = RegExp(r'"tier":\s*"([^"]+)"').firstMatch(r.body)?[1];
    return Check('ElevenLabs (account)', Verdict.pass,
        'tier $tier · $used/$limit characters used');
  } on Object catch (e) {
    return Check('ElevenLabs (account)', Verdict.fail, 'unreachable',
        note: '$e');
  }
}

/// The configured voice id must actually exist on this account.
Future<Check> _elevenLabsVoice(AppConfig config) async {
  if (!config.hasPremiumVoice) {
    return Check('ElevenLabs (voice id)', Verdict.skip, 'no key');
  }
  try {
    final r = await http.get(
      Uri.parse(
          'https://api.elevenlabs.io/v1/voices/${config.elevenLabsVoiceId}'),
      headers: {'xi-api-key': config.elevenLabsApiKey},
    ).timeout(const Duration(seconds: 15));

    if (r.statusCode != 200) {
      return Check('ElevenLabs (voice id)', Verdict.fail,
          'HTTP ${r.statusCode} for ${config.elevenLabsVoiceId}',
          note: _elevenLabsDetail(r.body) ??
              'the actor would fall back to the device voice every turn');
    }
    final name = RegExp(r'"name":\s*"([^"]+)"').firstMatch(r.body)?[1];
    return Check('ElevenLabs (voice id)', Verdict.pass,
        '${config.elevenLabsVoiceId} = "$name"');
  } on Object catch (e) {
    return Check('ElevenLabs (voice id)', Verdict.fail, 'unreachable',
        note: '$e');
  }
}

/// Real synthesis, using the app's own request shape.
Future<Check> _elevenLabsSynthesis(AppConfig config) async {
  if (!config.hasPremiumVoice) {
    return Check('ElevenLabs (synthesis)', Verdict.skip, 'no key');
  }

  const line = 'You never told me this was serious. I thought we were fine.';
  final watch = Stopwatch()..start();
  try {
    final r = await http
        .post(
          ElevenLabsRequest.uri(config),
          headers: ElevenLabsRequest.headers(config),
          body: ElevenLabsRequest.body(line),
        )
        .timeout(ElevenLabsRequest.timeout);
    watch.stop();

    if (r.statusCode != 200) {
      return Check('ElevenLabs (synthesis)', Verdict.fail,
          'HTTP ${r.statusCode} after ${watch.elapsedMilliseconds} ms',
          note: _elevenLabsDetail(r.body) ??
              'the actor would be silent on ElevenLabs and fall back');
    }
    if (!ElevenLabsRequest.looksLikeMp3(r.bodyBytes)) {
      return Check('ElevenLabs (synthesis)', Verdict.fail,
          '200 but the body is not playable audio (${r.bodyBytes.length} bytes)');
    }

    // Keep the artifact so the audio can be listened to, not just counted.
    final out = File('bench/results/elevenlabs_sample.mp3')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(r.bodyBytes);

    return Check(
      'ElevenLabs (synthesis)',
      Verdict.pass,
      '${watch.elapsedMilliseconds} ms · ${r.bodyBytes.length} bytes '
          '(${ElevenLabsRequest.model})',
      note: 'saved ${out.path} — play it to confirm it sounds right',
    );
  } on Object catch (e) {
    watch.stop();
    return Check('ElevenLabs (synthesis)', Verdict.fail, 'failed', note: '$e');
  }
}

/// Gemini TTS — the voice that needs no second account.
///
/// This is the one that actually has to work: ElevenLabs will not serve a free
/// account, so without this the actor speaks in the device's robotic voice.
Future<Check> _geminiTts(AppConfig config) async {
  if (!config.hasAi) {
    return Check('Gemini TTS (voice)', Verdict.skip, 'no key — device voice');
  }

  const line = 'You never told me this was serious. I thought we were fine.';
  final watch = Stopwatch()..start();

  try {
    final r = await http
        .post(
          GeminiTtsRequest.uri(GeminiTtsRequest.model),
          headers: GeminiTtsRequest.headers(config),
          body: GeminiTtsRequest.body(line, voice: 'Leda'),
        )
        .timeout(GeminiTtsRequest.timeout);
    watch.stop();

    if (r.statusCode != 200) {
      return Check('Gemini TTS (voice)', Verdict.fail,
          'HTTP ${r.statusCode} after ${watch.elapsedMilliseconds} ms');
    }

    final audio = GeminiTtsRequest.audioFrom(r.body);
    if (audio == null || !GeminiTtsRequest.looksLikeWav(audio)) {
      return Check('Gemini TTS (voice)', Verdict.fail,
          '200 but no playable audio returned');
    }

    // 44-byte RIFF header, then 16-bit mono at 24 kHz.
    final seconds = ((audio.length - 44) / (24000 * 2)).toStringAsFixed(1);
    final out = File('bench/results/gemini_tts_sample.wav')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(audio);

    return Check(
      'Gemini TTS (voice)',
      Verdict.pass,
      '${watch.elapsedMilliseconds} ms · ${seconds}s of audio · '
          '${GeminiTtsRequest.model}',
      note: 'saved ${out.path} — play it to hear the actor',
    );
  } on Object catch (e) {
    watch.stop();
    return Check('Gemini TTS (voice)', Verdict.fail, 'failed', note: '$e');
  }
}

/// RevenueCat, exercised for real against its REST API.
///
/// A public SDK key authenticates `/v1/subscribers`, so the key, the project
/// and the configured offerings can all be verified from here. What still
/// cannot be proven without a device is the purchase itself — the SDK talks to
/// the store, not to this endpoint.
Future<Check> _revenueCat(AppConfig config) async {
  final key = config.revenueCatAndroidKey.isNotEmpty
      ? config.revenueCatAndroidKey
      : config.revenueCatIosKey;

  if (key.isEmpty) {
    return Check('RevenueCat', Verdict.skip, 'no key — free tier only');
  }

  final testStore = AppConfig.isTestStoreKey(key);
  const user = 'verbal_integration_check';

  try {
    final headers = {
      'Authorization': 'Bearer $key',
      'X-Platform': 'android',
    };

    final subscriber = await http
        .get(Uri.parse('https://api.revenuecat.com/v1/subscribers/$user'),
            headers: headers)
        .timeout(const Duration(seconds: 15));

    if (subscriber.statusCode != 200 && subscriber.statusCode != 201) {
      return Check('RevenueCat', Verdict.fail,
          'HTTP ${subscriber.statusCode} authenticating the key',
          note: 'the SDK would fail to configure on device');
    }

    final offerings = await http
        .get(
            Uri.parse(
                'https://api.revenuecat.com/v1/subscribers/$user/offerings'),
            headers: headers)
        .timeout(const Duration(seconds: 15));

    if (offerings.statusCode != 200) {
      return Check('RevenueCat', Verdict.fail,
          'key works but offerings returned HTTP ${offerings.statusCode}');
    }

    final current = RegExp(r'"current_offering_id":\s*"([^"]+)"')
        .firstMatch(offerings.body)?[1];
    final packages = RegExp(r'"identifier":\s*"(\$rc_[^"]+)"')
        .allMatches(offerings.body)
        .map((m) => m[1]!)
        .toSet();

    if (current == null || packages.isEmpty) {
      return Check('RevenueCat', Verdict.fail, 'no offering is configured',
          note: 'the paywall would render with nothing to buy');
    }

    return Check(
      'RevenueCat',
      Verdict.pass,
      '${testStore ? "Test Store" : "production"} key · offering "$current" · '
          '${packages.length} packages (${packages.join(", ")})',
      note: testStore
          ? 'Test Store: purchases work in debug builds with no Play Console. '
              'A RELEASE build with this key is refused at startup — RevenueCat '
              'crashes on one, so billing.dart disables itself instead.'
          : 'a real purchase still needs a device and a store account',
    );
  } on Object catch (e) {
    return Check('RevenueCat', Verdict.fail, 'unreachable', note: '$e');
  }
}

Check _oneSignal(AppConfig config) {
  if (!config.hasPush) {
    return Check('OneSignal', Verdict.skip, 'no app id');
  }
  final ok =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(config.oneSignalAppId);
  return Check(
    'OneSignal',
    ok ? Verdict.local : Verdict.fail,
    ok ? 'app id is a well-formed UUID' : 'app id is not a UUID',
    note: 'no push SDK is wired into this build, so nothing sends regardless',
  );
}

/// ElevenLabs puts the actionable part in `detail.message`. Surfacing it is the
/// difference between "HTTP 402" and knowing exactly which setting to change.
String? _elevenLabsDetail(String body) =>
    RegExp(r'"message":\s*"([^"]+)"').firstMatch(body)?[1];

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}
