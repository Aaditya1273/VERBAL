import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/failures.dart';
import '../../core/logger.dart';
import '../../domain/actor_prompt.dart';
import '../../domain/conversation_engine.dart';
import '../../domain/scenario.dart';
import '../../domain/session.dart';

/// One reply from the AI actor, plus what it observed about the user's turn.
class ActorReply {
  const ActorReply({required this.text, required this.signal});

  final String text;
  final TurnSignal signal;
}

/// Generates the other side of the conversation.
abstract class ActorService {
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  });

  /// Post-session analysis. Returns the raw model text for [AnalysisParser].
  Future<String> analyse(String prompt);
}

/// Gemini-backed actor.
class GeminiActorService implements ActorService {
  GeminiActorService({
    required this.config,
    http.Client? client,
    String? model,
  })  : _client = client ?? http.Client(),
        _model = model ?? defaultModel;

  final AppConfig config;
  final http.Client _client;

  /// Which model to call. Overridable because a hardcoded one has already gone
  /// stale once: `gemini-2.5-flash` was retired for new API keys and started
  /// returning 404 in production.
  final String _model;

  static const _host = 'generativelanguage.googleapis.com';

  /// Forces the actor's reply into the shape the engine consumes. Without this
  /// the model drifts into prose whenever the conversation gets emotional,
  /// which is exactly when the evidence matters most.
  static const _turnSchema = {
    'type': 'OBJECT',
    'properties': {
      'reply': {
        'type': 'STRING',
        'description': 'What the character says out loud. No narration.',
      },
      'objectionAddressed': {
        'type': 'STRING',
        'description':
            'Id of the objection the user genuinely engaged with, or an empty '
                'string if none.',
      },
      'acknowledgedEmotion': {'type': 'BOOLEAN'},
      'heldPosition': {'type': 'BOOLEAN'},
      'gaveSpecificExample': {'type': 'BOOLEAN'},
      'evidence': {
        'type': 'STRING',
        'description':
            'One short factual observation about what the user just did.',
      },
      'pitfallId': {
        'type': 'STRING',
        'description':
            'Id of the communication pitfall the user committed this turn, from '
                'the WATCH FOR THESE list, or an empty string if none applies.',
      },
    },
    'required': [
      'reply',
      'objectionAddressed',
      'acknowledgedEmotion',
      'heldPosition',
      'gaveSpecificExample',
      'evidence',
      'pitfallId',
    ],
  };

  /// Pinned rather than an alias like `gemini-flash-latest`: a drifting alias
  /// would silently change what the Pitfall Bench measured.
  static const defaultModel = 'gemini-3.5-flash';

  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async {
    final contents = [
      for (final t in ActorPrompt.history(history))
        {
          'role': t['role'],
          'parts': [
            {'text': t['text']}
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': ActorPrompt.turn(directive, scenario)}
        ],
      },
    ];

    final raw = await _generate(
      model: _model,
      systemInstruction: systemPrompt,
      contents: contents,
      // High enough to feel human, low enough to stay in character.
      temperature: 0.9,
      timeout: const Duration(seconds: 20),
      schema: _turnSchema,
      // A spoken reply must land fast. Reasoning tokens cost seconds the user
      // hears as dead air, and the engine — not the model — does the thinking
      // that matters here.
      thinkingBudget: 0,
      maxOutputTokens: 500,
    );

    return _parseReply(raw, directive);
  }

  ActorReply _parseReply(String raw, TurnDirective directive) {
    final map = _firstJsonObject(raw);
    if (map == null) {
      // The model answered in prose. Use it as the line rather than failing the
      // turn — a slightly off-protocol reply beats a dead conversation.
      final text = raw.trim();
      if (text.isEmpty) throw const AiUnavailableFailure();
      return ActorReply(text: text, signal: TurnSignal.empty);
    }

    final reply = (map['reply'] as String? ?? '').trim();
    if (reply.isEmpty) throw const AiUnavailableFailure();

    return ActorReply(text: reply, signal: TurnSignal.fromJson(map));
  }

  @override
  Future<String> analyse(String prompt) => _generate(
        model: _model,
        systemInstruction:
            'You are a precise communication coach. Return only valid JSON.',
        contents: [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
        temperature: 0.3,
        timeout: const Duration(seconds: 45),
      );

  Future<String> _generate({
    required String model,
    required String systemInstruction,
    required List<Map<String, Object?>> contents,
    required double temperature,
    required Duration timeout,
    Map<String, Object?>? schema,
    int? thinkingBudget,
    int maxOutputTokens = 1400,
  }) async {
    if (!config.hasAi) throw const AiNotConfiguredFailure();

    final uri = Uri.https(_host, '/v1beta/models/$model:generateContent');

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              // Header, not a query parameter — keeps the key out of URLs,
              // proxy logs and crash reports.
              'x-goog-api-key': config.geminiApiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': systemInstruction}
                ]
              },
              'contents': contents,
              'generationConfig': {
                'temperature': temperature,
                'responseMimeType': 'application/json',
                'maxOutputTokens': maxOutputTokens,
                if (schema != null) 'responseSchema': schema,
                if (thinkingBudget != null)
                  'thinkingConfig': {'thinkingBudget': thinkingBudget},
              },
            }),
          )
          .timeout(timeout);
    } on TimeoutException catch (e) {
      throw AiUnavailableFailure(cause: e);
    } on http.ClientException catch (e) {
      throw NetworkFailure(cause: e);
    } on Object catch (e) {
      throw NetworkFailure(cause: e);
    }

    if (response.statusCode != 200) {
      // The body can echo the prompt, so it is never logged. The status and
      // Google's own `error.status` are safe and are the whole diagnosis.
      final reason = _errorStatus(response);
      Log.w('gemini $model -> ${response.statusCode}'
          '${reason == null ? '' : ' ($reason)'}');
      throw AiUnavailableFailure(
        cause: 'HTTP ${response.statusCode}'
            '${reason == null ? '' : ' $reason'} from $model',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) throw const AiUnavailableFailure();

    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      // A 200 with no candidates is a safety block, not an outage. Worth
      // separating: a termination roleplay can trip content filters, and
      // retrying an outage is sensible where retrying a block is not.
      final blocked = body['promptFeedback']?['blockReason'];
      throw AiUnavailableFailure(
        cause: blocked == null
            ? 'no candidates returned by $model'
            : 'blocked by $model ($blocked)',
      );
    }

    final parts =
        (candidates.first as Map<String, dynamic>)['content']?['parts'];
    if (parts is! List || parts.isEmpty) throw const AiUnavailableFailure();

    return (parts.first as Map<String, dynamic>)['text'] as String? ?? '';
  }

  /// Google's machine-readable error status (`NOT_FOUND`, `PERMISSION_DENIED`,
  /// …). Never the message, which can quote the request.
  static String? _errorStatus(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is Map) {
        return body['error']['status'] as String?;
      }
    } on Object {
      return null;
    }
    return null;
  }

  static Map<String, dynamic>? _firstJsonObject(String raw) {
    final text = raw.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// Runs a coherent rehearsal with no API key and no network.
///
/// This is what makes VERBAL demoable the second it is installed, and what the
/// app degrades to when the AI is unreachable. It reads the scenario's authored
/// objection lines rather than generating anything, so it is honest about being
/// scripted — but the pressure, escalation and pacing are the real engine.
class ScriptedActorService implements ActorService {
  const ScriptedActorService();

  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async {
    // A beat of latency, so the UI's THINKING state is exercised honestly.
    await Future<void>.delayed(const Duration(milliseconds: 550));

    if (directive.raiseObjection != null) {
      return ActorReply(
        text: directive.raiseObjection!.line,
        signal: const TurnSignal(),
      );
    }

    if (directive.shouldClose) {
      return ActorReply(
        text: directive.mayConcede
            ? 'Okay. I hear you. I do not love it, but I understand where you stand.'
            : 'I do not think we are going to agree on this today.',
        signal: const TurnSignal(),
      );
    }

    final lastUser = history.lastWhere(
      (t) => t.speaker == Speaker.user,
      orElse: () => Turn(speaker: Speaker.user, text: '', at: DateTime.now()),
    );

    return ActorReply(
      text: _holdingLine(directive, lastUser.text),
      signal: const TurnSignal(),
    );
  }

  String _holdingLine(TurnDirective d, String lastUserTurn) {
    if (lastUserTurn.trim().length < 15) {
      return 'I am going to need more than that. What are you actually saying?';
    }
    return switch (d.emotion) {
      Emotion.calm => 'Okay. Say more about what you mean by that.',
      Emotion.guarded => 'I am not sure I follow. Where is this coming from?',
      Emotion.defensive =>
        'That is not how I would describe it at all. Have you looked at the whole picture?',
      Emotion.frustrated =>
        'You keep coming back to the same thing. What do you want me to say?',
      Emotion.upset =>
        'This is a lot to take in. I do not think you understand what this means for me.',
      Emotion.angry => 'No. I am not going to just sit here and accept that.',
    };
  }

  @override
  Future<String> analyse(String prompt) async {
    // Deliberately returns nothing parseable: the parser's honest fallback is
    // better than a fabricated score.
    throw const AiNotConfiguredFailure();
  }
}
