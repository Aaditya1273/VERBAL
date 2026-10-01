import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/actor_prompt.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/pitfall.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';

/// Tier 1 of the Pitfall Bench: the deterministic half.
///
/// These run with no API key and prove the *mechanism* — that a reported
/// pitfall produces a contingent reaction at the next turn, exactly once, and
/// that the engine refuses to believe a pitfall the scenario cannot produce.
/// Tier 2 (`tool/pitfall_bench.dart`) measures whether a real model detects
/// them; that is a separate claim and is reported separately.

TurnSignal committing(String pitfallId) => TurnSignal(pitfallId: pitfallId);

void main() {
  const scenario = ScenarioLibrary.difficultFeedback;

  ConversationEngine engineOn([Difficulty d = Difficulty.moderate]) =>
      ConversationEngine(scenario: scenario, difficulty: d)..start();

  group('detection is the engine\'s decision, not the model\'s', () {
    test('a valid pitfall is accepted and recorded', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.overExplain.id));

      expect(e.committedPitfalls, [PitfallLibrary.overExplain.id]);
      expect(e.pendingContingency, PitfallLibrary.overExplain);
    });

    test('an invented pitfall id is ignored', () {
      final e = engineOn()..recordUserTurn(committing('made_up_by_the_model'));

      expect(e.committedPitfalls, isEmpty);
      expect(e.pendingContingency, isNull);
    });

    test('a pitfall that does not apply to this scenario is rejected', () {
      // negotiate_against_self is scoped to negotiation-shaped scenarios.
      expect(
        PitfallLibrary.negotiateAgainstSelf.appliesToScenario(scenario.id),
        isFalse,
        reason: 'precondition for this test',
      );

      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.negotiateAgainstSelf.id));

      expect(e.committedPitfalls, isEmpty,
          reason: 'the engine must not accept an out-of-scenario pitfall');
    });

    test('an empty or null pitfall id is simply no pitfall', () {
      final e = engineOn()
        ..recordUserTurn(const TurnSignal(pitfallId: ''))
        ..recordUserTurn(const TurnSignal());

      expect(e.committedPitfalls, isEmpty);
      expect(e.pendingContingency, isNull);
    });

    test('pitfalls accumulate in the order they were committed', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.absolutes.id))
        ..recordUserTurn(committing(PitfallLibrary.overExplain.id));

      expect(e.committedPitfalls,
          [PitfallLibrary.absolutes.id, PitfallLibrary.overExplain.id]);
    });
  });

  group('contingent adaptation at the trigger turn', () {
    test('the next directive carries the required reaction', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.buryTheHeadline.id));

      final d = e.peekDirective();

      expect(d.contingentReaction, PitfallLibrary.buryTheHeadline);
      expect(d.contingentReaction!.requiredReaction, isNotEmpty);
    });

    test('peeking does not consume the contingency', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.matchTheHeat.id));

      expect(e.peekDirective().contingentReaction, isNotNull);
      expect(e.peekDirective().contingentReaction, isNotNull);
      expect(e.pendingContingency, PitfallLibrary.matchTheHeat);
    });

    test('committing the directive delivers it exactly once', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.matchTheHeat.id));

      final d = e.peekDirective();
      e.commitDirective(d);

      expect(e.pendingContingency, isNull);
      expect(e.peekDirective().contingentReaction, isNull,
          reason: 'the actor does not owe the same reaction twice');
    });

    test('a later pitfall replaces the one already answered', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.absolutes.id));
      e.commitDirective(e.peekDirective());

      e.recordUserTurn(committing(PitfallLibrary.overExplain.id));

      expect(e.peekDirective().contingentReaction, PitfallLibrary.overExplain);
    });

    test('a clean turn owes no reaction', () {
      final e = engineOn()
        ..recordUserTurn(const TurnSignal(heldPosition: true));

      expect(e.peekDirective().contingentReaction, isNull);
    });
  });

  group('a pitfall costs something', () {
    test('it escalates even when the objection was handled well', () {
      final e = engineOn(Difficulty.hard);
      final d = e.nextDirective();
      final before = e.emotion;

      // Answered the objection properly, but matched the heat doing it.
      e.recordUserTurnAgainst(
        TurnSignal(
          objectionAddressedId: d.raiseObjection!.id,
          acknowledgedEmotion: true,
          pitfallId: PitfallLibrary.matchTheHeat.id,
        ),
        d.raiseObjection!.id,
      );

      expect(e.handledObjectionIds, contains(d.raiseObjection!.id),
          reason: 'the objection was still genuinely handled');
      expect(e.emotion.index, greaterThan(before.index),
          reason: 'but the pitfall still escalates');
      expect(e.poorStreak, 1);
    });

    test('without a pitfall, handling well still softens', () {
      final e = engineOn(Difficulty.hard);
      final d = e.nextDirective();
      e.recordUserTurnAgainst(const TurnSignal(), d.raiseObjection!.id);
      final escalated = e.emotion;

      e.recordUserTurnAgainst(
        TurnSignal(
          objectionAddressedId: d.raiseObjection!.id,
          acknowledgedEmotion: true,
        ),
        d.raiseObjection!.id,
      );

      expect(e.emotion.index, lessThan(escalated.index));
      expect(e.poorStreak, 0);
    });

    test('easy difficulty records the pitfall but does not escalate', () {
      final e = engineOn(Difficulty.easy);
      final before = e.emotion;

      e.recordUserTurn(committing(PitfallLibrary.overExplain.id));

      expect(e.committedPitfalls, hasLength(1),
          reason: 'still worth telling the user about afterwards');
      expect(e.emotion, before,
          reason: 'easy has escalationSpeed 0 — the actor stays calm');
    });

    test('the outcome snapshot reports the pitfalls for the review', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.absolutes.id))
        ..endSession(EndReason.userEnded);

      expect(e.toOutcome()['pitfallsCommitted'], [PitfallLibrary.absolutes.id]);
    });
  });

  group('the prompt actually carries the instruction', () {
    test('a trigger turn renders as a mandatory reaction', () {
      final e = engineOn()
        ..recordUserTurn(committing(PitfallLibrary.vagueWithoutExample.id));

      final text = ActorPrompt.turn(e.peekDirective(), scenario);

      expect(text, contains('REACT TO IT NOW'));
      expect(text, contains('UNFINISHED BUSINESS'),
          reason: 'the reaction lands a turn after the mistake, and the prompt '
              'must say so or it fights the transcript');
      expect(
          text, contains(PitfallLibrary.vagueWithoutExample.requiredReaction));
      expect(text, contains('never name the mistake'),
          reason: 'the actor reacts in character, it does not tutor');
    });

    test('a clean turn renders no reaction block', () {
      final e = engineOn();
      final text = ActorPrompt.turn(e.peekDirective(), scenario);

      expect(text, isNot(contains('REACT TO IT NOW')));
    });

    test('the watchlist reaches the actor, scoped to the scenario', () {
      final text = ActorPrompt.system(
          scenario: scenario, difficulty: Difficulty.moderate);

      expect(text, contains('WATCH FOR THESE'));
      expect(text, contains(PitfallLibrary.defendBeforeAcknowledge.id));
      expect(text, isNot(contains(PitfallLibrary.negotiateAgainstSelf.id)),
          reason: 'out-of-scenario pitfalls must not be offered at all');
      // The audit found difficulty was accepted and never used.
      expect(text, contains(Difficulty.moderate.label));
      // ...and that `evidence` was required by the schema but never explained.
      expect(text, contains('"evidence"'));
      expect(text, contains('"pitfallId"'));
    });

    test('unresolved objections stay on the table', () {
      final e = engineOn();
      final first = e.nextDirective();
      e.recordUserTurnAgainst(const TurnSignal(), first.raiseObjection!.id);

      final text = ActorPrompt.turn(e.peekDirective(), scenario);

      expect(text, contains(first.raiseObjection!.id),
          reason: 'previously the actor forgot anything already asked');
    });
  });

  group('taxonomy integrity', () {
    test('ids are unique', () {
      final ids = PitfallLibrary.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every pitfall is fully authored', () {
      for (final p in PitfallLibrary.all) {
        expect(p.name, isNotEmpty, reason: p.id);
        expect(p.detectionHint, isNotEmpty, reason: p.id);
        expect(p.skilledAlternative, isNotEmpty, reason: p.id);
        expect(p.requiredReaction, isNotEmpty, reason: p.id);
        expect(p.appliesTo, isNotEmpty, reason: p.id);
      }
    });

    test('scoped pitfalls name real scenarios', () {
      final known = ScenarioLibrary.all.map((s) => s.id).toSet();
      for (final p in PitfallLibrary.all) {
        for (final id in p.appliesTo) {
          if (id == 'all') continue;
          expect(known, contains(id), reason: '${p.id} -> $id');
        }
      }
    });

    test('every scenario has enough pitfalls to be worth detecting', () {
      for (final s in ScenarioLibrary.all) {
        expect(PitfallLibrary.forScenario(s).length, greaterThanOrEqualTo(8),
            reason: s.id);
      }
    });

    test('every pitfall maps to a skill the rubric already scores', () {
      for (final p in PitfallLibrary.all) {
        expect(Skill.values, contains(p.coreSkill), reason: p.id);
      }
    });
  });

  group('bench fixtures', () {
    // The benchmark is content, and content rots. These run with no API key so
    // a broken fixture is caught before it wastes a paid run.
    final decoded =
        jsonDecode(File('bench/pitfall_items.json').readAsStringSync())
            as Map<String, dynamic>;
    final items = (decoded['items'] as List).cast<Map<String, dynamic>>();

    test('every item names a real scenario and a real pitfall', () {
      for (final item in items) {
        final id = item['id'] as String;
        final scenarioId = item['scenarioId'] as String;
        final pitfallId = item['pitfallId'] as String;

        expect(ScenarioLibrary.byId(scenarioId), isNotNull,
            reason: '$id has an unknown scenarioId: $scenarioId');
        expect(PitfallLibrary.byId(pitfallId), isNotNull,
            reason: '$id has an unknown pitfallId: $pitfallId');
      }
    });

    test('every pitfall is in scope for the scenario it is tested in', () {
      for (final item in items) {
        final id = item['id'] as String;
        final scenarioId = item['scenarioId'] as String;
        final pitfall = PitfallLibrary.byId(item['pitfallId'] as String)!;

        expect(pitfall.appliesToScenario(scenarioId), isTrue,
            reason: '$id: ${pitfall.id} cannot fire in $scenarioId, '
                'so the item could never pass');
      }
    });

    test('item ids are unique', () {
      final ids = items.map((i) => i['id'] as String).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every item is a genuine pair', () {
      for (final item in items) {
        final id = item['id'] as String;
        final pitfallTurn = item['pitfallTurn'] as String;
        final skilledTurn = item['skilledTurn'] as String;

        expect(pitfallTurn.trim(), isNotEmpty, reason: id);
        expect(skilledTurn.trim(), isNotEmpty, reason: id);
        expect(pitfallTurn, isNot(skilledTurn),
            reason: '$id: the two halves of the pair must differ');
        expect(item['history'], isNotEmpty, reason: id);
      }
    });

    test('named difficulties are real', () {
      final names = Difficulty.values.map((d) => d.name).toSet();
      for (final item in items) {
        final id = item['id'] as String;
        expect(names, contains(item['difficulty'] as String? ?? 'moderate'),
            reason: id);
      }
    });

    test('every pitfall in the taxonomy has coverage', () {
      final covered = items.map((i) => i['pitfallId'] as String).toSet();
      final missing = PitfallLibrary.all
          .map((p) => p.id)
          .where((id) => !covered.contains(id))
          .toList();

      expect(missing, isEmpty,
          reason: 'a pitfall with no bench item cannot be reported on');
    });
  });

  group('IRP layering', () {
    test('every authored objection declares a layer', () {
      for (final s in ScenarioLibrary.all) {
        for (final o in s.objections) {
          expect(IrpLayer.values, contains(o.layer), reason: '${s.id}/${o.id}');
        }
      }
    });

    test('the directive carries the layer of the objection on the table', () {
      final e = engineOn();
      final d = e.nextDirective();

      expect(d.layer, d.raiseObjection!.layer);
    });

    test('the layer follows the objection as the conversation moves', () {
      final e = engineOn(Difficulty.boss);
      final seen = <IrpLayer>[];

      for (var i = 0; i < 12; i++) {
        final d = e.peekDirective();
        seen.add(d.layer);
        e
          ..commitDirective(d)
          ..recordUserTurn(const TurnSignal(heldPosition: true));
      }

      expect(seen.toSet().length, greaterThan(1),
          reason: 'the conflict must move between layers, not sit on one');
    });

    test('the actor is told which layer to argue from', () {
      final e = engineOn();
      final d = e.nextDirective();
      final text = ActorPrompt.turn(d, scenario);

      expect(text, contains(d.layer.label.toLowerCase()));
      expect(text, contains(d.layer.stance.split('.').first));
    });

    test('the power layer never invites a legal claim', () {
      // The safety rules forbid legal assertions; the stance must not undercut
      // them by nudging the actor toward one.
      expect(IrpLayer.power.stance, contains('Never make a legal claim'));
    });

    test('scenarios escalate to power only where it is credible', () {
      // A feedback conversation with a direct report should not end in threats.
      expect(
        ScenarioLibrary.difficultFeedback.objections
            .any((o) => o.layer == IrpLayer.power),
        isFalse,
      );
      expect(
        ScenarioLibrary.negotiatingRaise.objections
            .any((o) => o.layer == IrpLayer.power),
        isTrue,
      );
    });
  });
}
