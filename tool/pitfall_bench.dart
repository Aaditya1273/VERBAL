// ignore_for_file: avoid_print — this is a CLI; stdout is the whole point.

// VERBAL Pitfall Bench — tier 2.
//
// Tier 1 (`test/pitfall_engine_test.dart`) proves the *mechanism*: a recorded
// pitfall produces a contingent reaction, deterministically, with no model
// involved. That half is guaranteed.
//
// This is the other half, and it is the half that can fail: does a real model
// (a) notice the pitfall, (b) leave a skilled turn alone, and (c) actually do
// what the contingent instruction told it to?
//
//   dart run tool/pitfall_bench.dart --key=$GEMINI_API_KEY
//   dart run tool/pitfall_bench.dart --key=... --pitfall=match_the_heat
//   dart run tool/pitfall_bench.dart --key=... --limit=4
//
// Design follows PitfallBench (arXiv:2608.29481): paired items, identical
// history, one turn committing the pitfall and one taking the skilled
// alternative, scored against an explicit acceptance rule. The rule for each
// pitfall is its `requiredReaction`, written in `lib/domain/pitfall.dart` and
// auditable there — not invented by the judge.
//
// Report whatever number comes out. A measured 70% with a stated method is
// worth more than a claimed 95%.

import 'dart:convert';
import 'dart:io';

import 'package:verbal/core/config.dart';
import 'package:verbal/core/failures.dart';
import 'package:verbal/data/remote/actor_service.dart';
import 'package:verbal/domain/actor_prompt.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/pitfall.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/domain/session.dart';

/// One paired item: same history, two candidate user turns.
class BenchItem {
  BenchItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        scenarioId = j['scenarioId'] as String,
        difficultyName = j['difficulty'] as String? ?? 'moderate',
        pitfallId = j['pitfallId'] as String,
        history = (j['history'] as List)
            .cast<Map<String, dynamic>>()
            .map((t) => Turn(
                  speaker:
                      t['speaker'] == 'user' ? Speaker.user : Speaker.actor,
                  text: t['text'] as String,
                  at: DateTime.now(),
                ))
            .toList(),
        pitfallTurn = j['pitfallTurn'] as String,
        skilledTurn = j['skilledTurn'] as String;

  final String id;
  final String scenarioId;
  final String difficultyName;
  final String pitfallId;
  final List<Turn> history;
  final String pitfallTurn;
  final String skilledTurn;

  Scenario get scenario => ScenarioLibrary.byId(scenarioId)!;

  Difficulty get difficulty =>
      Difficulty.values.firstWhere((d) => d.name == difficultyName,
          orElse: () => Difficulty.moderate);

  Pitfall get pitfall => PitfallLibrary.byId(pitfallId)!;
}

class ItemResult {
  ItemResult(this.item);

  final BenchItem item;

  /// The pitfall turn was correctly identified.
  bool detected = false;

  /// What the model reported instead, when it got it wrong.
  String? reportedInstead;

  /// The skilled turn was correctly left alone.
  bool cleanOnSkilled = false;
  String? falsePositive;

  /// The actor carried out the required reaction on the following turn.
  bool contingent = false;
  String? contingentWhy;

  String? error;

  Map<String, Object?> toJson() => {
        'id': item.id,
        'scenario': item.scenarioId,
        'pitfall': item.pitfallId,
        'detected': detected,
        'reportedInstead': reportedInstead,
        'cleanOnSkilled': cleanOnSkilled,
        'falsePositive': falsePositive,
        'contingent': contingent,
        'contingentWhy': contingentWhy,
        'error': error,
      };
}

Future<void> main(List<String> args) async {
  final key = _arg(args, 'key') ?? Platform.environment['GEMINI_API_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('No API key. Pass --key=... or set GEMINI_API_KEY.\n'
        'Tier 1 runs without one: flutter test test/pitfall_engine_test.dart');
    exit(2);
  }

  final path = _arg(args, 'items') ?? 'bench/pitfall_items.json';
  final onlyPitfall = _arg(args, 'pitfall');
  final limit = int.tryParse(_arg(args, 'limit') ?? '');

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('No items at $path');
    exit(2);
  }

  final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  var items = (raw['items'] as List)
      .cast<Map<String, dynamic>>()
      .map(BenchItem.fromJson)
      .toList();

  if (onlyPitfall != null) {
    items = items.where((i) => i.pitfallId == onlyPitfall).toList();
  }
  if (limit != null && limit < items.length) {
    items = items.take(limit).toList();
  }

  if (items.isEmpty) {
    stderr.writeln('No items matched.');
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
  final service = GeminiActorService(config: config, model: model);

  print('VERBAL Pitfall Bench');
  print('model: $model');
  print('${items.length} paired items · 3 model calls each\n');

  final results = <ItemResult>[];
  final started = DateTime.now();

  for (final item in items) {
    stdout.write('  ${item.id.padRight(24)} ');
    final result = await _run(service, item);
    results.add(result);
    print(_mark(result));
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  final elapsed = DateTime.now().difference(started);
  _report(results, elapsed);
  await _save(results, elapsed, model);
}

/// Retries the transient failures a benchmark run will definitely hit.
///
/// A free-tier key rate-limits (429) and the service occasionally returns 503.
/// Neither says anything about the simulator, so neither should pollute the
/// score — but a content block (which is a real finding) is not retried.
Future<T> _withRetry<T>(Future<T> Function() call, {int attempts = 4}) async {
  var delay = const Duration(seconds: 4);
  for (var i = 1;; i++) {
    try {
      return await call();
    } on Failure catch (f) {
      final cause = f.cause?.toString() ?? '';
      final transient = cause.contains('429') ||
          cause.contains('503') ||
          cause.contains('RESOURCE_EXHAUSTED') ||
          cause.contains('UNAVAILABLE');
      if (!transient || i >= attempts) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
}

/// Three calls: detect on the pitfall turn, detect on the skilled turn, and
/// then whether the actor obeys the contingent instruction on the next turn.
Future<ItemResult> _run(ActorService service, BenchItem item) async {
  final result = ItemResult(item);
  final system =
      ActorPrompt.system(scenario: item.scenario, difficulty: item.difficulty);

  try {
    // --- 1. the pitfall turn: is it noticed? -------------------------------
    final engine =
        ConversationEngine(scenario: item.scenario, difficulty: item.difficulty)
          ..start();
    final d1 = engine.peekDirective();
    final pitfallHistory = [
      ...item.history,
      Turn(speaker: Speaker.user, text: item.pitfallTurn, at: DateTime.now()),
    ];

    final r1 = await _withRetry(() => service.respond(
          scenario: item.scenario,
          directive: d1,
          history: pitfallHistory,
          systemPrompt: system,
        ));

    result.detected = r1.signal.pitfallId == item.pitfallId;
    if (!result.detected) {
      result.reportedInstead =
          r1.signal.pitfallId?.isEmpty ?? true ? '(none)' : r1.signal.pitfallId;
    }

    // --- 2. the skilled turn: is it left alone? ----------------------------
    final clean =
        ConversationEngine(scenario: item.scenario, difficulty: item.difficulty)
          ..start();
    final r2 = await _withRetry(() => service.respond(
          scenario: item.scenario,
          directive: clean.peekDirective(),
          history: [
            ...item.history,
            Turn(
                speaker: Speaker.user,
                text: item.skilledTurn,
                at: DateTime.now()),
          ],
          systemPrompt: system,
        ));

    final reportedOnSkilled = r2.signal.pitfallId ?? '';
    result.cleanOnSkilled = reportedOnSkilled != item.pitfallId;
    if (!result.cleanOnSkilled) result.falsePositive = reportedOnSkilled;

    // --- 3. does the actor actually obey the contingent instruction? -------
    // Feed the engine the pitfall so the next directive carries the required
    // reaction, exactly as it would in a live session.
    engine
      ..commitDirective(d1)
      ..recordUserTurn(TurnSignal(pitfallId: item.pitfallId));

    final d2 = engine.peekDirective();
    if (d2.contingentReaction == null) {
      result.contingentWhy =
          'engine did not schedule a reaction (not eligible)';
    } else {
      final r3 = await _withRetry(() => service.respond(
            scenario: item.scenario,
            directive: d2,
            history: [
              ...pitfallHistory,
              Turn(speaker: Speaker.actor, text: r1.text, at: DateTime.now()),
              Turn(
                speaker: Speaker.user,
                text: 'Okay. Where does that leave us?',
                at: DateTime.now(),
              ),
            ],
            systemPrompt: system,
          ));

      final verdict = await _judge(service, item.pitfall, r3.text);
      result.contingent = verdict.$1;
      result.contingentWhy = verdict.$2;
    }
  } on Failure catch (f) {
    // Failure.toString() drops `cause`, which is where the HTTP status lives.
    result.error = '${f.message}${f.cause == null ? '' : ' [${f.cause}]'}';
  } on Object catch (e) {
    result.error = e.toString();
  }

  return result;
}

/// Judges compliance against the pitfall's own `requiredReaction`.
///
/// The rule is not invented here — it is the same string the actor was
/// instructed with, which is what makes the score auditable.
Future<(bool, String)> _judge(
    ActorService service, Pitfall pitfall, String reply) async {
  final prompt = '''
You are grading whether a simulated person's reply followed a specific instruction.

THE INSTRUCTION THEY WERE GIVEN
${pitfall.requiredReaction}

THEIR REPLY
"$reply"

Did the reply carry out that instruction? Judge only the behaviour described in
the instruction. Do not reward a reply for being well written, realistic, or
emotionally appropriate if it did not do the specific thing asked.

Return only JSON: {"followed": true|false, "why": "one short sentence"}''';

  try {
    final raw = await _withRetry(() => service.analyse(prompt));
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end <= start) return (false, 'unparseable verdict');

    final map =
        jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    return (map['followed'] == true, map['why'] as String? ?? '');
  } on Object catch (e) {
    return (false, 'judge failed: $e');
  }
}

String _mark(ItemResult r) {
  if (r.error != null) return 'ERROR  ${r.error}';
  final d = r.detected ? 'detect' : 'DETECT';
  final c = r.cleanOnSkilled ? 'clean' : 'CLEAN';
  final g = r.contingent ? 'react' : 'REACT';
  return '$d  $c  $g'
      '${r.reportedInstead != null ? '   (saw ${r.reportedInstead})' : ''}';
}

void _report(List<ItemResult> results, Duration elapsed) {
  final ok = results.where((r) => r.error == null).toList();

  print('\n${'=' * 68}');
  print('RESULTS  (lowercase = pass, UPPERCASE = fail)\n');

  final byPitfall = <String, List<ItemResult>>{};
  for (final r in ok) {
    byPitfall.putIfAbsent(r.item.pitfallId, () => []).add(r);
  }

  print('${'pitfall'.padRight(30)} ${'n'.padLeft(3)}  '
      '${'detect'.padLeft(7)} ${'clean'.padLeft(7)} ${'react'.padLeft(7)}');
  print('-' * 68);

  final ids = byPitfall.keys.toList()..sort();
  for (final id in ids) {
    final rs = byPitfall[id]!;
    print('${id.padRight(30)} ${rs.length.toString().padLeft(3)}  '
        '${_pct(rs.where((r) => r.detected).length, rs.length).padLeft(7)} '
        '${_pct(rs.where((r) => r.cleanOnSkilled).length, rs.length).padLeft(7)} '
        '${_pct(rs.where((r) => r.contingent).length, rs.length).padLeft(7)}');
  }

  print('-' * 68);
  print('${'OVERALL'.padRight(30)} ${ok.length.toString().padLeft(3)}  '
      '${_pct(ok.where((r) => r.detected).length, ok.length).padLeft(7)} '
      '${_pct(ok.where((r) => r.cleanOnSkilled).length, ok.length).padLeft(7)} '
      '${_pct(ok.where((r) => r.contingent).length, ok.length).padLeft(7)}');

  final errors = results.where((r) => r.error != null).length;
  if (errors > 0) print('\n$errors item(s) errored and are excluded above.');

  print('\ndetect  the pitfall turn was correctly identified');
  print('clean   the skilled turn was NOT flagged as that pitfall');
  print('react   the actor then carried out the required reaction');
  print('\nran in ${elapsed.inSeconds}s');
}

String _pct(int n, int total) =>
    total == 0 ? '-' : '${((n / total) * 100).round()}%';

Future<void> _save(
    List<ItemResult> results, Duration elapsed, String model) async {
  final dir = Directory('bench/results')..createSync(recursive: true);
  final stamp =
      DateTime.now().toIso8601String().split('.').first.replaceAll(':', '-');
  final file = File('${dir.path}/$stamp.json');

  final ok = results.where((r) => r.error == null).toList();
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'ranAt': DateTime.now().toIso8601String(),
    'model': model,
    'elapsedSeconds': elapsed.inSeconds,
    'items': results.length,
    'scored': ok.length,
    'summary': {
      'detect': _pct(ok.where((r) => r.detected).length, ok.length),
      'clean': _pct(ok.where((r) => r.cleanOnSkilled).length, ok.length),
      'react': _pct(ok.where((r) => r.contingent).length, ok.length),
    },
    'results': results.map((r) => r.toJson()).toList(),
  }));

  print('written to ${file.path}');
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}
