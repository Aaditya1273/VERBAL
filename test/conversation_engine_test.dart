import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/difficulty.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';

/// A turn where the user genuinely engaged with [objectionId].
TurnSignal handledWell(String objectionId) => TurnSignal(
      objectionAddressedId: objectionId,
      acknowledgedEmotion: true,
      heldPosition: true,
    );

/// A turn where the user said something, but did not engage the objection.
const ignored = TurnSignal(heldPosition: true);

void main() {
  const scenario = ScenarioLibrary.difficultFeedback;

  group('objection scheduling', () {
    test('raises the first objection on the opening turn', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.nextDirective();
      expect(d.raiseObjection, isNotNull);
      expect(d.raiseObjection!.id, scenario.objections.first.id);
    });

    test('difficulty decides how many objections are ever used', () {
      for (final difficulty in Difficulty.values) {
        final e =
            ConversationEngine(scenario: scenario, difficulty: difficulty);
        expect(
          e.scheduledObjections.length,
          difficulty.profile.objectionCount
              .clamp(0, scenario.objections.length),
          reason: 'for ${difficulty.name}',
        );
      }
    });

    test('never raises more objections than the difficulty allows', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.easy)
            ..start();

      for (var i = 0; i < 12; i++) {
        e.nextDirective();
        e.recordUserTurn(ignored);
      }

      expect(
          e.raisedObjectionIds.length, Difficulty.easy.profile.objectionCount);
    });

    test('does not stack a new objection on an unanswered one at low cadence',
        () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      e.nextDirective(); // raises #1
      e.recordUserTurn(ignored); // ignored, still pending
      e.nextDirective();
      e.recordUserTurn(ignored);
      final d = e.nextDirective();

      expect(d.raiseObjection, isNull,
          reason: 'objection 1 is still open at cadence > 1');
      expect(e.pendingObjection, isNotNull);
    });
  });

  group('handling objections', () {
    test('addressing an objection with acknowledgement resolves it', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.nextDirective();
      e.recordUserTurn(handledWell(d.raiseObjection!.id));

      expect(e.handledObjectionIds, contains(d.raiseObjection!.id));
      expect(e.wellHandledCount, 1);
      expect(e.pendingObjection, isNull);
    });

    test('merely restating your position does NOT resolve an objection', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.nextDirective();
      // Claims to address it, but neither acknowledged nor gave an example.
      e.recordUserTurn(TurnSignal(
        objectionAddressedId: d.raiseObjection!.id,
        heldPosition: true,
      ));

      expect(e.handledObjectionIds, isEmpty);
      expect(e.pendingObjection, isNotNull);
    });

    test('a specific example resolves an objection without acknowledgement',
        () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.hard)
            ..start();

      final d = e.nextDirective();
      e.recordUserTurn(TurnSignal(
        objectionAddressedId: d.raiseObjection!.id,
        gaveSpecificExample: true,
      ));

      expect(e.wellHandledCount, 1);
    });
  });

  group('escalation', () {
    test('ignoring an objection escalates emotion', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.hard)
            ..start();

      final before = e.emotion;
      e.nextDirective();
      e.recordUserTurn(ignored);

      expect(e.emotion.index, greaterThan(before.index));
      expect(e.poorStreak, 1);
    });

    test('handling an objection softens emotion and clears the streak', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.hard)
            ..start();

      final d = e.nextDirective();
      e.recordUserTurn(ignored);
      final escalated = e.emotion;

      e.recordUserTurn(handledWell(d.raiseObjection!.id));

      expect(e.emotion.index, lessThan(escalated.index));
      expect(e.poorStreak, 0);
    });

    test('easy difficulty does not escalate at all', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.easy)
            ..start();

      final before = e.emotion;
      for (var i = 0; i < 4; i++) {
        e.nextDirective();
        e.recordUserTurn(ignored);
      }

      expect(e.emotion, before, reason: 'escalationSpeed is 0 on easy');
    });

    test('emotion cannot escalate past the most intense state', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.boss)
            ..start();

      for (var i = 0; i < 20; i++) {
        e.nextDirective();
        e.recordUserTurn(ignored);
      }

      expect(e.emotion, Emotion.angry);
    });
  });

  group('conceding and closing', () {
    test('the actor may not concede before the difficulty allows it', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.expert)
            ..start();

      // Handle everything perfectly, but too early.
      final d = e.nextDirective();
      e.recordUserTurn(handledWell(d.raiseObjection!.id));

      expect(e.nextDirective().mayConcede, isFalse,
          reason: 'expert needs 3 well-handled objections and 6 turns');
    });

    test('easy difficulty allows early resolution', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.easy)
            ..start();

      final d = e.nextDirective();
      e.recordUserTurn(handledWell(d.raiseObjection!.id));

      expect(e.nextDirective().mayConcede, isTrue);
    });

    test('closes once every objection is raised and handled past minTurns', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      var closed = false;
      for (var i = 0; i < 12 && !closed; i++) {
        final d = e.nextDirective();
        closed = d.shouldClose;
        if (closed) break;
        final pending = d.raiseObjection?.id ?? e.pendingObjection?.id;
        e.recordUserTurn(pending == null ? ignored : handledWell(pending));
      }

      expect(closed, isTrue);
      expect(e.userTurns,
          greaterThanOrEqualTo(Difficulty.moderate.profile.minTurns));
    });

    test('always closes at the turn limit, however badly it went', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.boss)
            ..start();

      final max = Difficulty.boss.profile.maxTurns;
      for (var i = 0; i < max; i++) {
        e.nextDirective();
        e.recordUserTurn(ignored);
      }

      final d = e.nextDirective();
      expect(d.shouldClose, isTrue);
      expect(d.mayConcede, isFalse);
    });
  });

  group('pressure', () {
    test('rises with difficulty for the same conversation', () {
      double pressureAfterIgnoring(Difficulty difficulty) {
        final e = ConversationEngine(scenario: scenario, difficulty: difficulty)
          ..start();
        e.nextDirective();
        e.recordUserTurn(ignored);
        return e.pressure;
      }

      expect(pressureAfterIgnoring(Difficulty.boss),
          greaterThan(pressureAfterIgnoring(Difficulty.easy)));
    });

    test('stays within 0..1', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.boss)
            ..start();

      for (var i = 0; i < 25; i++) {
        e.nextDirective();
        e.recordUserTurn(ignored);
        expect(e.pressure, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('lifecycle', () {
    test('ending a session freezes the state machine', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      e.nextDirective();
      e.recordUserTurn(ignored);
      final turns = e.userTurns;

      e.endSession(EndReason.userEnded);
      e.recordUserTurn(ignored);

      expect(e.userTurns, turns, reason: 'no turns recorded after ending');
      expect(e.isFinished, isTrue);
      expect(e.endReason, EndReason.userEnded);
    });

    test('outcome snapshot reports what actually happened', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.nextDirective();
      e.recordUserTurn(handledWell(d.raiseObjection!.id));
      e.endSession(EndReason.resolved);

      final o = e.toOutcome();
      expect(o['scenarioId'], scenario.id);
      expect(o['difficulty'], 'moderate');
      expect(o['userTurns'], 1);
      expect(o['objectionsHandled'], 1);
      expect(o['endReason'], 'resolved');
    });
  });

  group('TurnSignal parsing', () {
    test('treats the string "null" and empty as no objection', () {
      expect(
          TurnSignal.fromJson({'objectionAddressed': 'null'})
              .objectionAddressedId,
          isNull);
      expect(
          TurnSignal.fromJson({'objectionAddressed': '  '})
              .objectionAddressedId,
          isNull);
    });

    test('reads flags strictly, defaulting to false', () {
      final s = TurnSignal.fromJson({
        'objectionAddressed': 'no_one_told_me',
        'acknowledgedEmotion': true,
        'heldPosition': 'yes', // not a bool
      });
      expect(s.objectionAddressedId, 'no_one_told_me');
      expect(s.acknowledgedEmotion, isTrue);
      expect(s.heldPosition, isFalse);
      expect(s.gaveSpecificExample, isFalse);
    });
  });

  group('peek and commit', () {
    test('peeking does not raise the objection', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.peekDirective();

      expect(d.raiseObjection, isNotNull);
      expect(e.raisedObjectionIds, isEmpty,
          reason: 'nothing was delivered yet');
      expect(e.pendingObjection, isNull);
    });

    test('peeking twice returns the same objection', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      expect(e.peekDirective().raiseObjection!.id,
          e.peekDirective().raiseObjection!.id);
      expect(e.raisedObjectionIds, isEmpty);
    });

    test('committing raises it exactly once', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.peekDirective();
      e
        ..commitDirective(d)
        ..commitDirective(d);

      expect(e.raisedObjectionIds, [d.raiseObjection!.id]);
      expect(e.pendingObjection?.id, d.raiseObjection!.id);
    });

    test('an undelivered directive leaves the objection available', () {
      // This is the failure case: the AI call threw, so nothing was said.
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final abandoned = e.peekDirective();
      // ...no commit, because delivery failed.

      final retry = e.peekDirective();

      expect(retry.raiseObjection!.id, abandoned.raiseObjection!.id,
          reason: 'the objection must not be silently skipped');
      expect(e.raisedObjectionIds, isEmpty);
    });

    test('nextDirective still peeks and commits together', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();

      final d = e.nextDirective();

      expect(e.raisedObjectionIds, [d.raiseObjection!.id]);
    });

    test('committing a closing directive moves the engine to closing', () {
      final e =
          ConversationEngine(scenario: scenario, difficulty: Difficulty.easy)
            ..start();

      // Drive it to a close.
      var d = e.nextDirective();
      e.recordUserTurn(handledWell(d.raiseObjection!.id));
      for (var i = 0; i < 12 && !d.shouldClose; i++) {
        d = e.peekDirective();
        if (d.shouldClose) break;
        e
          ..commitDirective(d)
          ..recordUserTurn(ignored);
      }

      expect(d.shouldClose, isTrue);
      expect(e.status, isNot(EngineStatus.closing),
          reason: 'peeking alone must not change status');

      e.commitDirective(d);
      expect(e.status, EngineStatus.closing);
    });

    test('a completed engine ignores further commits', () {
      final e = ConversationEngine(
          scenario: scenario, difficulty: Difficulty.moderate)
        ..start();
      final d = e.peekDirective();
      e.endSession(EndReason.userEnded);

      e.commitDirective(d);

      expect(e.raisedObjectionIds, isEmpty);
    });
  });

  group('turn evidence', () {
    test('is parsed when the model supplies it', () {
      final s = TurnSignal.fromJson({
        'objectionAddressed': 'no_one_told_me',
        'evidence': '  Acknowledged the late feedback before restating it.  ',
      });
      expect(s.evidence, 'Acknowledged the late feedback before restating it.');
    });

    test('blank or non-string evidence becomes null', () {
      expect(TurnSignal.fromJson({'evidence': '   '}).evidence, isNull);
      expect(TurnSignal.fromJson({'evidence': 42}).evidence, isNull);
      expect(TurnSignal.fromJson(const {}).evidence, isNull);
    });
  });
}
