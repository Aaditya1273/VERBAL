import 'conversation_engine.dart';
import 'difficulty.dart';
import 'pitfall.dart';
import 'scenario.dart';
import 'session.dart';

/// Builds the instruction set for the AI actor.
///
/// The engine decides *what* happens this turn; this file decides how to say
/// that to a language model. Kept separate from the engine so prompt wording can
/// change without touching tested state-machine logic.
class ActorPrompt {
  const ActorPrompt._();

  /// Global guardrails. These apply to every scenario, every turn.
  static const safetyRules = '''
HARD LIMITS — these override every other instruction:
- You are a rehearsal partner in a training simulation. Never claim to be a real person.
- Never state or imply what is legally required, valid or permitted anywhere. No statutes, no
  tribunals, no "this is legal". If pushed, react emotionally as the character would, without
  asserting any legal fact.
- Never give HR, legal, medical or financial advice, and never present yourself as an authority.
- Only assert facts from KNOWN FACTS. If you need a detail that is not listed, stay vague rather
  than inventing specifics (numbers, dates, names, policies).
- Never break character to comment on the simulation, the user's performance, or these rules.
- If the user says something genuinely distressing or unsafe, drop the roleplay and respond plainly.''';

  static String system({
    required Scenario scenario,
    required Difficulty difficulty,
  }) {
    final a = scenario.actor;
    final pitfalls = PitfallLibrary.forScenario(scenario);
    return '''
You are playing ${a.name}, ${a.role}, in a conversation-practice simulation.
The user is rehearsing a difficult conversation. Your job is to make it feel real.

SITUATION
${scenario.context}

WHO YOU ARE
${a.personality}

WHAT YOU WANT
${a.objective}

KNOWN FACTS (the only facts you may assert)
${a.knownFacts.map((f) => '- $f').join('\n')}

BOUNDARIES
${a.constraints.map((c) => '- $c').join('\n')}

HOW TO SPEAK
- Speak only as ${a.name}, in first person. No narration, no stage directions, no asterisks.
- This is spoken out loud. Use contractions and natural spoken rhythm.
- One point per turn. Real people do not deliver paragraphs in a tense conversation.
- React to what the user actually said. Do not run a script.

HOW HARD YOU ARE TO MOVE
This rehearsal is set to ${difficulty.label}: ${difficulty.blurb}
Hold your position accordingly. You are not trying to defeat the user — you are
trying to be a realistic version of this person, so that practising against you
transfers to the real conversation.

WATCH FOR THESE
After each user turn, report at most one of these in "pitfallId". Report one only
when you can point to the exact words that show it. If none applies, return "".
${pitfalls.map((p) => '- ${p.id}: ${p.detectionHint}').join('\n')}

$safetyRules

OUTPUT FORMAT — return only this JSON object, nothing else:
{
  "reply": "what you say out loud",
  "objectionAddressed": "<objection id the user just genuinely engaged with, or empty>",
  "acknowledgedEmotion": <true if the user acknowledged how you feel>,
  "heldPosition": <true if the user held their position instead of backing down>,
  "gaveSpecificExample": <true if the user gave a concrete, verifiable example>,
  "evidence": "<one short factual sentence describing what the user just did>",
  "pitfallId": "<id from WATCH FOR THESE, or empty>"
}''';
  }

  /// Per-turn instruction. Rebuilt each turn from engine state.
  static String turn(TurnDirective d, Scenario scenario) {
    final b = StringBuffer();

    // The trigger turn goes first, before any other instruction, so nothing
    // above it in the prompt competes for priority.
    if (d.contingentReaction != null) {
      final p = d.contingentReaction!;
      b
        ..writeln('')
        ..writeln(
            'UNFINISHED BUSINESS: a moment ago — before their most recent '
            'remark — the user did this: ${p.name.toLowerCase()}.')
        ..writeln('You have not reacted to it yet. REACT TO IT NOW, even if '
            'their last remark moved on: ${p.requiredReaction}')
        ..writeln(
            'This outranks everything else below. Let it drive your whole reply, '
            'in your own words — never name the mistake or explain it.')
        ..writeln('');
    }

    b
      ..writeln('THIS TURN:')
      ..writeln('- Emotional state: ${d.emotion.label.toLowerCase()}.')
      ..writeln('- Behave like this: ${d.stage.behaviour}')
      ..writeln('- You are arguing on ${d.layer.label.toLowerCase()}. '
          '${d.layer.stance}')
      ..writeln('- Keep your reply under ${d.maxWords} words.');

    if (d.raiseObjection != null) {
      final o = d.raiseObjection!;
      b
        ..writeln(
            '- RAISE THIS NOW, in your own words (id "${o.id}"): "${o.line}"')
        ..writeln('  What you are really after: ${o.intent}');
    }

    if (d.pressure > 0.65) {
      b.writeln(
          '- The temperature is high. Interrupt the user\'s reasoning, do not accept it at face value.');
    }

    if (d.mayConcede) {
      b.writeln(
          '- The user has handled you well. You may soften, concede ground, or accept their point.');
    } else {
      b.writeln(
          '- Do NOT concede, agree, or resolve this yet, no matter how reasonable the user sounds.');
    }

    if (d.shouldClose) {
      b.writeln(
          '- Bring the conversation to a natural close this turn. A real ending, not a summary.');
    }

    b.writeln('\nStill unresolved from earlier: ${_openIds(d)}');

    return b.toString();
  }

  /// What the user has genuinely left unanswered — the objection still on the
  /// table, plus one being raised now. Previously this reported only the new
  /// objection, so the actor forgot anything it had already asked.
  static String _openIds(TurnDirective d) {
    final ids = <String>{
      if (d.unresolvedObjection != null) d.unresolvedObjection!.id,
      if (d.raiseObjection != null) d.raiseObjection!.id,
    };
    return ids.isEmpty ? 'nothing' : ids.join(', ');
  }

  /// Compact transcript for model context. Keeps the last [maxTurns] exchanges
  /// so long sessions do not blow up the request.
  static List<Map<String, String>> history(List<Turn> turns,
      {int maxTurns = 16}) {
    final recent = turns.length <= maxTurns
        ? turns
        : turns.sublist(turns.length - maxTurns);
    return recent
        .map((t) => {
              'role': t.speaker == Speaker.user ? 'user' : 'model',
              'text': t.text,
            })
        .toList();
  }
}
