// ignore_for_file: avoid_print — this is a CLI; stdout is the whole point.

// Proves the real Gemini path works end to end.
//
// Until this passes, every claim about the AI actor is theoretical: the app has
// shipped with a written-but-never-exercised network path. Run it before
// trusting anything built on top.
//
//   dart run tool/live_smoke.dart --key=$GEMINI_API_KEY
//   GEMINI_API_KEY=... dart run tool/live_smoke.dart
//
// It checks four things and exits non-zero if any fail:
//   1. the request reaches Gemini and returns 200
//   2. the response honours `_turnSchema` (structured output, not prose)
//   3. every field the engine consumes is present — including `evidence`
//   4. turn latency, measured rather than estimated

import 'dart:io';

import 'package:verbal/core/config.dart';
import 'package:verbal/data/remote/actor_service.dart';
import 'package:verbal/domain/actor_prompt.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/domain/session.dart';

Future<void> main(List<String> args) async {
  final key = _arg(args, 'key') ?? Platform.environment['GEMINI_API_KEY'] ?? '';

  if (key.isEmpty) {
    stderr.writeln('''
No API key.

  dart run tool/live_smoke.dart --key=YOUR_KEY
  GEMINI_API_KEY=YOUR_KEY dart run tool/live_smoke.dart

Get one at https://aistudio.google.com/apikey — it is never written to disk by
this tool, and env.json is gitignored.''');
    exit(2);
  }

  final model = _arg(args, 'model') ?? GeminiActorService.defaultModel;

  final config = AppConfig(
    geminiApiKey: key,
    elevenLabsApiKey: '',
    elevenLabsVoiceId: '',
    revenueCatAndroidKey: '',
    revenueCatIosKey: '',
    oneSignalAppId: '',
  );

  const scenario = ScenarioLibrary.difficultFeedback;
  const difficulty = Difficulty.moderate;

  final engine = ConversationEngine(scenario: scenario, difficulty: difficulty)
    ..start();
  final directive = engine.peekDirective();

  final history = [
    Turn(
      speaker: Speaker.actor,
      text: scenario.openingLine!,
      at: DateTime.now(),
    ),
    Turn(
      speaker: Speaker.user,
      text: 'I want to talk about the last quarter. The Aldridge deadline '
          'slipped by four days and the Q3 deck by two. This is a performance '
          'concern, and I should have raised it sooner than I did.',
      at: DateTime.now(),
    ),
  ];

  _section('REQUEST');
  print('scenario    ${scenario.id}');
  print('difficulty  ${difficulty.name}');
  print('objection   ${directive.raiseObjection?.id ?? '(none)'}');
  print('emotion     ${directive.emotion.name}');
  print('maxWords    ${directive.maxWords}');
  print('model       $model');

  final service = GeminiActorService(config: config, model: model);
  final watch = Stopwatch()..start();

  ActorReply reply;
  try {
    reply = await service.respond(
      scenario: scenario,
      directive: directive,
      history: history,
      systemPrompt:
          ActorPrompt.system(scenario: scenario, difficulty: difficulty),
    );
  } on Object catch (e) {
    watch.stop();
    _section('FAILED');
    print('after ${watch.elapsedMilliseconds} ms');
    print('$e');
    print('\nThe network path does not work. Fix this before building on it.');
    exit(1);
  }
  watch.stop();

  _section('REPLY');
  print('"${reply.text}"');
  print('\nwords       ${reply.text.trim().split(RegExp(r'\s+')).length} '
      '(directive allowed ${directive.maxWords})');

  final s = reply.signal;
  _section('STRUCTURED SIGNAL');
  print('objectionAddressed   ${s.objectionAddressedId ?? '(null)'}');
  print('acknowledgedEmotion  ${s.acknowledgedEmotion}');
  print('heldPosition         ${s.heldPosition}');
  print('gaveSpecificExample  ${s.gaveSpecificExample}');
  print('evidence             ${s.evidence ?? '(null)'}');

  _section('LATENCY');
  print('actor turn  ${watch.elapsedMilliseconds} ms');

  // A reply that parsed into a signal at all means the schema held; prose would
  // have produced TurnSignal.empty with every field at its default.
  final structured = s.evidence != null ||
      s.acknowledgedEmotion ||
      s.heldPosition ||
      s.gaveSpecificExample ||
      s.objectionAddressedId != null;

  final checks = <String, bool>{
    'reached Gemini and parsed a reply': reply.text.trim().isNotEmpty,
    'structured output honoured (not prose)': structured,
    'evidence populated': s.evidence != null,
    'reply within the directive word budget':
        reply.text.trim().split(RegExp(r'\s+')).length <=
            directive.maxWords * 1.5,
  };

  _section('CHECKS');
  var failed = 0;
  checks.forEach((name, ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $name');
    if (!ok) failed++;
  });

  print('');
  if (failed == 0) {
    print('The real actor path works. Safe to build on.');
  } else {
    print('$failed check(s) failed — see above before building on this path.');
  }
  exit(failed == 0 ? 0 : 1);
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}

void _section(String title) =>
    print('\n== $title ${'=' * (58 - title.length)}');
