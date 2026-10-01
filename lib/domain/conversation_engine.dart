import 'difficulty.dart';
import 'pitfall.dart';
import 'scenario.dart';

/// Status of a practice conversation.
enum EngineStatus { notStarted, running, closing, complete }

/// Why the conversation ended. Used by analysis and progress.
enum EndReason { resolved, turnLimit, userEnded, abandoned }

/// What the AI actor must do on this turn.
///
/// The engine — not the model — decides emotion, escalation and whether the
/// actor is allowed to concede. The model only chooses the words. This is the
/// deterministic frame around a probabilistic responder.
class TurnDirective {
  const TurnDirective({
    required this.turnIndex,
    required this.emotion,
    required this.stage,
    required this.pressure,
    required this.mayConcede,
    required this.shouldClose,
    required this.maxWords,
    this.raiseObjection,
    this.contingentReaction,
    this.unresolvedObjection,
    this.layer = IrpLayer.rights,
  });

  final int turnIndex;
  final Emotion emotion;
  final EscalationStage stage;

  /// 0..1 — how much heat the actor brings to this turn.
  final double pressure;

  /// The actor is permitted to soften or accept the user's position.
  final bool mayConcede;

  /// The actor should bring the conversation to a close this turn.
  final bool shouldClose;

  final int maxWords;

  /// If set, the actor must raise this objection now.
  final Objection? raiseObjection;

  /// The layer of the conflict the actor should argue from this turn.
  final IrpLayer layer;

  /// An objection already raised that the user has still not resolved. The
  /// actor should keep it on the table even when no new objection is due.
  final Objection? unresolvedObjection;

  /// Set when the user committed a pitfall on the previous turn. The actor's
  /// reply this turn MUST carry out its `requiredReaction` — this is the
  /// contingent adaptation at the trigger turn, and the benchmark checks it.
  final Pitfall? contingentReaction;
}

/// What the actor observed about the user's turn. Returned as structured data
/// alongside the actor's reply so the engine can advance on evidence rather
/// than on the model's mood.
class TurnSignal {
  const TurnSignal({
    this.objectionAddressedId,
    this.acknowledgedEmotion = false,
    this.heldPosition = false,
    this.gaveSpecificExample = false,
    this.evidence,
    this.pitfallId,
  });

  final String? objectionAddressedId;
  final bool acknowledgedEmotion;
  final bool heldPosition;
  final bool gaveSpecificExample;

  /// One observation about what the user just did, captured while the turn is
  /// fresh. Collected across the session and handed to the analyser, which
  /// otherwise has to re-derive everything from a bare transcript.
  final String? evidence;

  /// The communication pitfall the user committed on this turn, if any.
  ///
  /// The model only *reports* it. The engine decides what happens next — see
  /// [ConversationEngine.peekDirective] and [TurnDirective.contingentReaction].
  final String? pitfallId;

  /// A neutral signal, used when the model returns nothing parseable.
  static const empty = TurnSignal();

  factory TurnSignal.fromJson(Map<String, dynamic> json) {
    final raw = json['objectionAddressed'];
    final id = (raw is String && raw.trim().isNotEmpty && raw != 'null')
        ? raw.trim()
        : null;
    final evidence = json['evidence'];
    final pitfall = json['pitfallId'];
    return TurnSignal(
      objectionAddressedId: id,
      acknowledgedEmotion: json['acknowledgedEmotion'] == true,
      heldPosition: json['heldPosition'] == true,
      gaveSpecificExample: json['gaveSpecificExample'] == true,
      evidence: (evidence is String && evidence.trim().isNotEmpty)
          ? evidence.trim()
          : null,
      pitfallId: (pitfall is String &&
              pitfall.trim().isNotEmpty &&
              pitfall.trim() != 'null')
          ? pitfall.trim()
          : null,
    );
  }
}

/// Deterministic state machine driving a practice conversation.
///
/// Pure Dart, no I/O — this is the piece that must stay predictable, so it is
/// the piece that is unit tested.
class ConversationEngine {
  ConversationEngine({required this.scenario, required this.difficulty})
      : _profile = difficulty.profile,
        _emotion = scenario.actor.initialEmotion;

  final Scenario scenario;
  final Difficulty difficulty;
  final DifficultyProfile _profile;

  EngineStatus _status = EngineStatus.notStarted;
  Emotion _emotion;
  int _stageIndex = 0;
  int _userTurns = 0;
  int _poorStreak = 0;
  int _wellHandled = 0;
  EndReason? _endReason;

  final List<String> _raised = [];
  final Set<String> _handled = {};
  final List<String> _committedPitfalls = [];

  /// The pitfall committed on the most recent user turn, awaiting delivery of
  /// its contingent reaction. Cleared once the directive carrying it is
  /// committed, so each trigger turn is answered exactly once.
  Pitfall? _pendingContingency;

  EngineStatus get status => _status;
  Emotion get emotion => _emotion;
  int get userTurns => _userTurns;
  int get wellHandledCount => _wellHandled;

  /// Consecutive user turns that left an objection unanswered. Drives the
  /// actor's willingness to interrupt.
  int get poorStreak => _poorStreak;
  EndReason? get endReason => _endReason;
  List<String> get raisedObjectionIds => List.unmodifiable(_raised);
  Set<String> get handledObjectionIds => Set.unmodifiable(_handled);

  /// Every pitfall the user has committed, in order. Feeds the session review.
  List<String> get committedPitfalls => List.unmodifiable(_committedPitfalls);

  /// The pitfall the actor still owes a reaction to, if any.
  Pitfall? get pendingContingency => _pendingContingency;

  /// The pitfalls that can fire in this scenario.
  List<Pitfall> get eligiblePitfalls => PitfallLibrary.forScenario(scenario);

  /// The layer of the conflict the actor is currently arguing on.
  ///
  /// Follows the objection on the table. Because objections are authored and
  /// scheduled in order, this tracks the Interests-Rights-Power escalation
  /// naturally rather than needing a second state machine.
  IrpLayer get currentLayer {
    // The most recently raised objection, not the oldest unresolved one: the
    // actor argues from where the conversation is now, and an old point left
    // hanging should not pin the whole conflict to one layer.
    final onTable = _lastRaised ?? pendingObjection;
    if (onTable != null) return onTable.layer;
    final scheduled = scheduledObjections;
    return scheduled.isEmpty ? IrpLayer.interest : scheduled.first.layer;
  }

  Objection? get _lastRaised {
    if (_raised.isEmpty) return null;
    final id = _raised.last;
    return scheduledObjections.where((o) => o.id == id).firstOrNull;
  }

  /// Objections this difficulty will actually use, in order.
  List<Objection> get scheduledObjections => scenario.objections
      .take(_profile.objectionCount.clamp(0, scenario.objections.length))
      .toList();

  /// The objection raised but not yet handled, if any.
  Objection? get pendingObjection {
    for (final id in _raised) {
      if (!_handled.contains(id)) {
        return scheduledObjections.firstWhere((o) => o.id == id);
      }
    }
    return null;
  }

  /// 0..1 composite of emotional state, unhandled resistance and difficulty.
  double get pressure {
    final emotional = _emotion.index / (Emotion.values.length - 1);
    final unhandled = scheduledObjections.isEmpty
        ? 0.0
        : (_raised.length - _handled.length) / scheduledObjections.length;
    final streak = (_poorStreak / 3).clamp(0.0, 1.0);
    final raw = (emotional * 0.4) +
        (unhandled.clamp(0.0, 1.0) * 0.25) +
        (_profile.resistance * 0.2) +
        (streak * 0.15);
    return raw.clamp(0.0, 1.0);
  }

  EscalationStage get currentStage {
    final stages = scenario.escalationStages;
    if (stages.isEmpty) {
      return EscalationStage(
          index: 0, emotion: _emotion, behaviour: 'Respond in character.');
    }
    return stages[_stageIndex.clamp(0, stages.length - 1)];
  }

  void start() {
    if (_status == EngineStatus.notStarted) _status = EngineStatus.running;
  }

  /// What the actor should do next, **without** advancing any state.
  ///
  /// Use this when the directive might not be delivered — the AI call can fail,
  /// time out or be cancelled. Committing an objection that was never spoken
  /// silently skips it for the rest of the session.
  TurnDirective peekDirective() {
    final objection = _selectObjectionToRaise();
    final mayConcede = _mayConcede();
    final shouldClose = _shouldClose(mayConcede);

    // More volatile actors talk in shorter, sharper bursts.
    final maxWords = (55 - (_profile.volatility * 25) - (pressure * 10))
        .round()
        .clamp(18, 55);

    return TurnDirective(
      turnIndex: _userTurns,
      emotion: _emotion,
      stage: currentStage,
      pressure: pressure,
      mayConcede: mayConcede,
      shouldClose: shouldClose,
      maxWords: maxWords,
      raiseObjection: objection,
      contingentReaction: _pendingContingency,
      unresolvedObjection: pendingObjection,
      layer: currentLayer,
    );
  }

  /// Record that [directive] was actually delivered to the user.
  ///
  /// Only now is the objection marked as raised. Call this after the actor's
  /// line has been produced, never before.
  void commitDirective(TurnDirective directive) {
    if (_status == EngineStatus.complete) return;

    final objection = directive.raiseObjection;
    if (objection != null && !_raised.contains(objection.id)) {
      _raised.add(objection.id);
    }
    // The contingent reaction has now been delivered; it is not owed twice.
    if (directive.contingentReaction != null &&
        directive.contingentReaction == _pendingContingency) {
      _pendingContingency = null;
    }
    if (directive.shouldClose) _status = EngineStatus.closing;
  }

  /// Peek and commit in one step. Convenient when delivery cannot fail —
  /// the scripted actor, and tests.
  TurnDirective nextDirective() {
    final directive = peekDirective();
    commitDirective(directive);
    return directive;
  }

  /// Advance the state machine using evidence from the user's turn, scored
  /// against whatever objection was open at the time.
  void recordUserTurn(TurnSignal signal) =>
      recordUserTurnAgainst(signal, pendingObjection?.id);

  /// Same, but explicit about which objection the user was answering.
  ///
  /// A live turn is evaluated and replied to in one model call, so by the time
  /// the evidence arrives the actor may already have raised a *new* objection.
  /// Scoring against that one would punish the user for not answering something
  /// they had not yet heard — so the caller passes the objection that was open
  /// when the user actually spoke.
  void recordUserTurnAgainst(TurnSignal signal, String? openObjectionId) {
    if (_status == EngineStatus.complete) return;
    _userTurns++;

    final pending = openObjectionId == null ||
            _handled.contains(openObjectionId)
        ? null
        : scheduledObjections.where((o) => o.id == openObjectionId).firstOrNull;
    final addressed = signal.objectionAddressedId != null &&
        signal.objectionAddressedId == pending?.id;

    // An objection counts as handled only if the user engaged with it rather
    // than restating their position: they acknowledged the feeling or brought
    // something concrete.
    final handledWell =
        addressed && (signal.acknowledgedEmotion || signal.gaveSpecificExample);

    // A pitfall only counts if it is one this scenario can actually produce.
    // The model reports; the engine decides whether to believe it.
    final pitfall = _eligiblePitfall(signal.pitfallId);
    if (pitfall != null) {
      _committedPitfalls.add(pitfall.id);
      _pendingContingency = pitfall;
    }

    // Objection credit is independent of the emotional response below: a user
    // can answer the objection well and still commit a pitfall doing it.
    if (handledWell) {
      _handled.add(pending!.id);
      _wellHandled++;
      if (_stageIndex > 0) _stageIndex--;
    }

    if (pitfall != null) {
      // A trigger turn always costs something, however well the objection went.
      _poorStreak++;
      _escalate();
    } else if (handledWell) {
      _poorStreak = 0;
      _emotion = _emotion.soften(1);
    } else if (pending != null) {
      _poorStreak++;
      _escalate();
    } else if (signal.heldPosition) {
      // Holding the line with no objection on the table keeps things steady.
      _poorStreak = 0;
    }
  }

  void _escalate() {
    if (_profile.escalationSpeed == 0) return;
    _emotion = _emotion.escalate(_profile.escalationSpeed);
    _stageIndex = (_stageIndex + 1)
        .clamp(0, (scenario.escalationStages.length - 1).clamp(0, 99));
  }

  /// Resolves a reported pitfall id, rejecting anything not valid for this
  /// scenario. Guards against the model inventing an id.
  Pitfall? _eligiblePitfall(String? id) {
    final pitfall = PitfallLibrary.byId(id);
    if (pitfall == null) return null;
    return pitfall.appliesToScenario(scenario.id) ? pitfall : null;
  }

  void endSession(EndReason reason) {
    _status = EngineStatus.complete;
    _endReason = reason;
  }

  /// Whether the conversation has run its course.
  bool get isFinished => _status == EngineStatus.complete;

  /// Called after the actor's closing turn has been delivered.
  void completeNaturally() {
    if (_status == EngineStatus.complete) return;
    _status = EngineStatus.complete;
    _endReason = _userTurns >= _profile.maxTurns
        ? EndReason.turnLimit
        : EndReason.resolved;
  }

  Objection? _selectObjectionToRaise() {
    final scheduled = scheduledObjections;
    if (_raised.length >= scheduled.length) return null;

    // First objection lands on the opening exchange; the rest follow the
    // difficulty's cadence.
    if (_raised.isEmpty) return scheduled.first;

    final due = _userTurns >= _raised.length * _profile.objectionCadence;
    if (!due) return null;

    // Don't stack a second objection on top of an unanswered one unless the
    // difficulty is high enough to run competing objections.
    if (pendingObjection != null && _profile.objectionCadence > 1) return null;

    return scheduled[_raised.length];
  }

  bool _mayConcede() {
    if (_userTurns < _profile.minTurns && !_profile.allowsEarlyResolution) {
      return false;
    }
    return _wellHandled >= _profile.wellHandledToConcede;
  }

  bool _shouldClose(bool mayConcede) {
    if (_userTurns >= _profile.maxTurns) return true;
    if (!mayConcede) return false;
    if (_userTurns < _profile.minTurns) return false;
    return _raised.length >= scheduledObjections.length &&
        pendingObjection == null;
  }

  /// Snapshot for analysis and persistence.
  Map<String, dynamic> toOutcome() => {
        'scenarioId': scenario.id,
        'difficulty': difficulty.name,
        'userTurns': _userTurns,
        'objectionsRaised': _raised.length,
        'objectionsHandled': _handled.length,
        'pitfallsCommitted': _committedPitfalls,
        'finalEmotion': _emotion.name,
        'finalLayer': currentLayer.name,
        'endReason': (_endReason ?? EndReason.abandoned).name,
        'peakPressure': pressure,
      };
}
