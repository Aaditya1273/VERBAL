import 'analysis.dart';
import 'conversation_engine.dart';
import 'scenario.dart';
import 'session.dart';

/// Builds the post-session analysis request.
///
/// The instructions are deliberately hostile to generic coaching language —
/// "be more confident" is explicitly banned and every claim must quote the
/// transcript.
class AnalysisPrompt {
  const AnalysisPrompt._();

  static String build({
    required Scenario scenario,
    required PracticeSession session,
    required ConversationEngine engine,
    List<String> turnEvidence = const [],
  }) {
    final outcome = engine.toOutcome();
    final observations = turnEvidence.isEmpty
        ? 'None recorded.'
        : turnEvidence.map((e) => '- $e').join('\n');
    return '''
You are a communication coach reviewing a rehearsal transcript. You are rigorous,
specific and useful. You are not encouraging for its own sake.

THE SCENARIO
${scenario.title} — ${scenario.context}

WHAT THE USER WAS TRYING TO DO
${scenario.userObjective}

WHAT GOOD LOOKS LIKE
${scenario.successCriteria.map((c) => '- $c').join('\n')}

WHAT THE SIMULATION MEASURED
- Difficulty: ${session.difficulty.name}
- User turns: ${outcome['userTurns']}
- Objections raised by the other person: ${outcome['objectionsRaised']}
- Objections the user genuinely handled: ${outcome['objectionsHandled']}
- Their emotional state at the end: ${outcome['finalEmotion']}

WHAT THE OTHER PERSON NOTICED, TURN BY TURN
These were recorded live, during the conversation. Treat them as observations,
not conclusions - the scores are yours to decide.
$observations

TRANSCRIPT
${session.transcript}

RULES FOR YOUR FEEDBACK
- Every observation must quote or closely paraphrase something the user actually said.
- Banned: "be more confident", "great job", "try to be clearer", and any advice that would
  apply equally to any conversation.
- If the user barely spoke, say so plainly and score low. Do not invent performance.
- "betterAlternative" must be a specific line the user could say out loud, rewriting one of
  their actual weaker lines.
- Weight these skills most heavily for this scenario: ${scenario.rubricFocus.map((s) => s.name).join(', ')}.
- Never give HR or legal advice. Coach the communication only.

Also score the seven DEAR MAN moves 0-100 (DBT interpersonal effectiveness).
These describe whether the ask was built properly, separately from how the
conversation felt:
${DearMan.values.map((d) => '- ${d.wireName}: ${d.description}').join('\n')}
If the conversation gave no evidence for a move, score it 50 and say so.

Score each of the six skills 0-100:
${Skill.values.map((s) => '- ${s.name}: ${s.description}').join('\n')}

Return ONLY this JSON:
{
  "summary": "two sentences on how the conversation actually went",
  "objectiveMet": true | false,
  "scores": [{"skill": "clarity", "score": 0-100, "note": "the specific behaviour behind this score, quoting the transcript"}],
  "dearMan": [{"component": "describe|express|assert|reinforce|mindful|confident|negotiate", "score": 0-100, "note": "evidence from the transcript"}],
  "worked": [{"quote": "what they said", "why": "why it landed"}],
  "weakened": [{"quote": "what they said", "why": "what it cost them"}],
  "betterAlternative": {"quote": "the improved line", "why": "why this is stronger"},
  "nextSkill": "${Skill.values.map((s) => s.name).join('|')}",
  "playbookCandidates": [
    {
      "kind": "winningLine|betterAlternative|framework|principle|mistake",
      "title": "short name",
      "body": "the line or framework itself",
      "whyItWorks": "one sentence",
      "skill": "which skill it serves"
    }
  ]
}

Give 1-3 items in "worked", 1-3 in "weakened", and 1-3 playbook candidates.''';
  }
}
