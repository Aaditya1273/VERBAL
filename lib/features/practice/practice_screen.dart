import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/failures.dart';
import '../../domain/analysis.dart';
import '../../domain/conversation_engine.dart';
import '../../domain/difficulty.dart';
import '../../domain/pitfall.dart';
import '../../domain/playbook.dart';
import '../../domain/scenario.dart';
import '../../domain/session.dart';
import '../../shared/presence.dart';
import '../../shared/widgets.dart';
import 'practice_controller.dart';

/// The live conversation.
///
/// Deliberately not a chat UI: one large line from the other person, a clear
/// system state, a waveform, and one control. The transcript is available but
/// secondary — the user should be listening, not reading.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({
    super.key,
    required this.scenarioId,
    required this.difficulty,
    required this.onFinished,
  });

  final String scenarioId;
  final Difficulty difficulty;
  final void Function(String sessionId) onFinished;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late final PracticeArgs _args = PracticeArgs(
      scenarioId: widget.scenarioId, difficulty: widget.difficulty);

  bool _showTranscript = false;
  bool _opened = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_opened) return;
    _opened = true;
    await ref.read(practiceControllerProvider(_args).notifier).open();
  }

  PracticeController get _controller =>
      ref.read(practiceControllerProvider(_args).notifier);

  Future<void> _end() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this conversation?'),
        content: const Text(
            'We will analyse what you have said so far and save it to your history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep going')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End and analyse')),
        ],
      ),
    );
    if (confirmed != true) return;

    final id = await _controller.finish(EndReason.userEnded);
    if (id != null && mounted) _goToAnalysis(id);
  }

  /// Analysis is reachable from two paths — guard against navigating twice.
  void _goToAnalysis(String sessionId) {
    if (_navigated || !mounted) return;
    _navigated = true;
    widget.onFinished(sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(practiceControllerProvider(_args));
    final c = context.c;

    // When the engine closes the conversation itself, move straight to analysis.
    // The engine can close the conversation on its own; this catches that case.
    ref.listen(practiceControllerProvider(_args), (prev, next) {
      if (next.isFinished && !next.analysing && next.sessionId != null) {
        _goToAnalysis(next.sessionId!);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _end();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: VerbalTokens.lg,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Long scenario titles must not push the actions off a phone.
              Text(
                state.scenario.title.toUpperCase(),
                style: context.t.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                state.scenario.actor.name,
                style: context.t.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            _Progress(
              handled: _controller.engine.handledObjectionIds.length,
              total: _controller.engine.scheduledObjections.length,
            ),
            const SizedBox(width: VerbalTokens.md),
            _PressureMeter(pressure: state.pressure),
            const SizedBox(width: VerbalTokens.sm),
            TextButton(onPressed: _end, child: const Text('End')),
            const SizedBox(width: VerbalTokens.sm),
          ],
        ),
        body: SafeArea(
          child: state.analysing
              ? const _Analysing()
              : Column(
                  children: [
                    Expanded(
                      child: _showTranscript
                          ? _Transcript(turns: state.turns)
                          : _ActorStage(state: state),
                    ),
                    if (state.lastPitfall != null)
                      _PitfallFlash(pitfall: state.lastPitfall!),
                    _StatusRow(state: state),
                    Waveform(
                      levels: state.levels,
                      active: state.phase == VoicePhase.listening,
                    ),
                    if (state.partial.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: VerbalTokens.lg,
                            vertical: VerbalTokens.sm),
                        child: Text(
                          state.partial,
                          textAlign: TextAlign.center,
                          style: context.t.bodyMedium?.copyWith(color: c.muted),
                        ),
                      ),
                    if (state.failure != null)
                      _InlineFailure(
                        failure: state.failure!,
                        onType: _openTypeSheet,
                        onRetry: _controller.retryLastTurn,
                        canRetry: state.canRetry,
                      ),
                    _Controls(
                      state: state,
                      onPressStart: () {
                        HapticFeedback.mediumImpact();
                        _controller.listen();
                      },
                      onPressEnd: _controller.stopListening,
                      onType: _openTypeSheet,
                      onToggleTranscript: () =>
                          setState(() => _showTranscript = !_showTranscript),
                      transcriptOpen: _showTranscript,
                    ),
                    const SizedBox(height: VerbalTokens.md),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openTypeSheet() async {
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: VerbalTokens.lg,
          right: VerbalTokens.lg,
          top: VerbalTokens.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + VerbalTokens.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Type your turn'),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What do you say?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: VerbalTokens.md),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Say it'),
            ),
          ],
        ),
      ),
    );

    if (text != null && text.trim().isNotEmpty) {
      await _controller.submitTyped(text);
    }
  }
}

/// The other person's current line, given the whole stage.
class _ActorStage extends StatelessWidget {
  const _ActorStage({required this.state});

  final PracticeState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VerbalTokens.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The orb reads the engine, not the script: heat is pressure.
          Presence(
            size: 150,
            heat: state.pressure,
            speaking: state.phase == VoicePhase.speaking,
            listening: state.phase == VoicePhase.listening,
          ),
          const SizedBox(height: VerbalTokens.md),
          Pill(
            state.emotion.label,
            icon: Icons.psychology_outlined,
            tone: state.pressure > 0.6 ? c.signal : c.muted,
          ),
          const SizedBox(height: VerbalTokens.lg),
          AnimatedSwitcher(
            duration: context.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 320),
            child: Text(
              state.currentLine.isEmpty ? '…' : '“${state.currentLine}”',
              key: ValueKey(state.currentLine),
              textAlign: TextAlign.center,
              style: context.t.headlineSmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.turns});

  final List<Turn> turns;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (turns.isEmpty) {
      return const Center(child: Text('The conversation has not started.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(VerbalTokens.lg),
      reverse: true,
      itemCount: turns.length,
      separatorBuilder: (_, __) => const SizedBox(height: VerbalTokens.md),
      itemBuilder: (context, i) {
        final turn = turns[turns.length - 1 - i];
        final isUser = turn.speaker == Speaker.user;
        return Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(isUser ? 'YOU' : 'THEM', style: context.t.labelMedium),
            const SizedBox(height: 2),
            Text(
              turn.text,
              textAlign: isUser ? TextAlign.right : TextAlign.left,
              style: context.t.bodyMedium
                  ?.copyWith(color: isUser ? c.ink : c.muted),
            ),
          ],
        );
      },
    );
  }
}

/// Named the moment it happens.
///
/// This is the trigger turn made visible: the user sees what they just did at
/// the same instant the other person reacts to it. Deliberately quiet — a
/// label, not an alarm — because the reaction in the conversation is the real
/// feedback, and this only names it.
class _PitfallFlash extends StatelessWidget {
  const _PitfallFlash({required this.pitfall});

  final Pitfall pitfall;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      label: 'You just ${pitfall.name.toLowerCase()}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            VerbalTokens.lg, 0, VerbalTokens.lg, VerbalTokens.sm),
        child: AnimatedSwitcher(
          duration: context.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          child: Row(
            key: ValueKey(pitfall.id),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 14, color: c.signal),
              const SizedBox(width: VerbalTokens.sm),
              Flexible(
                child: Text(
                  pitfall.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelSmall?.copyWith(color: c.signal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// LISTENING / THINKING / SPEAKING — the system state, always visible.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state});

  final PracticeState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isLive = state.phase == VoicePhase.listening;
    final color = switch (state.phase) {
      VoicePhase.listening => c.signal,
      VoicePhase.error => c.signal,
      VoicePhase.speaking => c.accent,
      _ => c.muted,
    };

    return Semantics(
      liveRegion: true,
      label: 'Status: ${state.phase.label.toLowerCase()}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Dot(color: color, pulsing: isLive),
            const SizedBox(width: VerbalTokens.sm),
            Text(
              state.phase.label,
              style: context.t.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.pulsing && !context.reduceMotion) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// How far through the conversation's resistance the user has got.
///
/// One dot per objection this difficulty will use — filled once handled. It
/// answers "how long is this going to go on for", which is otherwise invisible.
class _Progress extends StatelessWidget {
  const _Progress({required this.handled, required this.total});

  final int handled;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final c = context.c;

    return Semantics(
      label: '$handled of $total objections handled',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < handled ? c.accent : c.line,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How much heat the other person is bringing, right now.
class _PressureMeter extends StatelessWidget {
  const _PressureMeter({required this.pressure});

  final double pressure;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: 'Pressure ${(pressure * 100).round()} percent',
      child: SizedBox(
        width: 54,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: pressure.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 600),
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: c.line,
              valueColor:
                  AlwaysStoppedAnimation(value > 0.6 ? c.signal : c.muted),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onType,
    required this.onToggleTranscript,
    required this.transcriptOpen,
  });

  final PracticeState state;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final VoidCallback onType;
  final VoidCallback onToggleTranscript;
  final bool transcriptOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final listening = state.phase == VoicePhase.listening;
    final busy = state.phase.isBusy;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VerbalTokens.lg),
      child: Row(
        children: [
          IconButton(
            onPressed: onToggleTranscript,
            tooltip: transcriptOpen ? 'Hide transcript' : 'Show transcript',
            icon: Icon(transcriptOpen
                ? Icons.visibility_off_outlined
                : Icons.article_outlined),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: listening
                  ? 'Release to send your turn'
                  : 'Hold to speak your turn',
              child: GestureDetector(
                onTapDown: busy ? null : (_) => onPressStart(),
                onTapUp: (_) => onPressEnd(),
                onTapCancel: onPressEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: VerbalTokens.tap + 12,
                  decoration: BoxDecoration(
                    color: listening ? c.signal : (busy ? c.raised : c.accent),
                    borderRadius: BorderRadius.circular(VerbalTokens.radius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    listening
                        ? 'RELEASE TO SEND'
                        : (busy ? state.phase.label : 'HOLD TO SPEAK'),
                    style: context.t.labelLarge?.copyWith(
                      color: busy ? c.muted : Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: busy ? null : onType,
            tooltip: 'Type instead',
            icon: const Icon(Icons.keyboard_outlined),
          ),
        ],
      ),
    );
  }
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({
    required this.failure,
    required this.onType,
    required this.onRetry,
    required this.canRetry,
  });

  final Failure failure;
  final VoidCallback onType;
  final VoidCallback onRetry;
  final bool canRetry;

  bool get _needsSettings =>
      failure is MicrophonePermissionFailure &&
      (failure as MicrophonePermissionFailure).permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VerbalTokens.lg, 0, VerbalTokens.lg, VerbalTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: c.signal),
              const SizedBox(width: VerbalTokens.sm),
              Expanded(
                child: Text(failure.message,
                    style: context.t.bodySmall?.copyWith(color: c.signal)),
              ),
            ],
          ),
          const SizedBox(height: VerbalTokens.sm),
          Row(
            children: [
              if (canRetry)
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Send that again'),
                ),
              if (_needsSettings)
                const OutlinedButton(
                  onPressed: openAppSettings,
                  child: Text('Open Settings'),
                ),
              const Spacer(),
              TextButton(onPressed: onType, child: const Text('Type instead')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Analysing extends StatelessWidget {
  const _Analysing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: VerbalTokens.lg),
          Text('Reviewing the conversation', style: context.t.titleMedium),
          const SizedBox(height: VerbalTokens.xs),
          Text('Scoring what you actually said.', style: context.t.bodySmall),
        ],
      ),
    );
  }
}

/// Shown before a session when the Playbook has something relevant. This is the
/// reuse half of the loop — saved lines come back when they are useful.
class PlaybookPrimer extends ConsumerWidget {
  const PlaybookPrimer({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(relevantPlaybookProvider(scenarioId));

    return entries.maybeWhen(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _Primer(entries: list, scenarioId: scenarioId);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _Primer extends ConsumerStatefulWidget {
  const _Primer({required this.entries, required this.scenarioId});

  final List<PlaybookEntry> entries;
  final String scenarioId;

  @override
  ConsumerState<_Primer> createState() => _PrimerState();
}

class _PrimerState extends ConsumerState<_Primer> {
  @override
  void initState() {
    super.initState();
    // Surfacing is the usage event — record it once, when it is actually shown.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = ref.read(playbookRepositoryProvider);
      for (final e in widget.entries) {
        await repo.markUsed(e.id);
      }
      ref.read(analyticsProvider).track(AnalyticsEvent.playbookReused, {
        'count': widget.entries.length,
        'scenario': widget.scenarioId,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('From your playbook'),
        for (final e in widget.entries) ...[
          VerbalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill(e.kind.label, tone: context.c.accent),
                const SizedBox(height: VerbalTokens.sm),
                Text('“${e.body}”', style: context.t.bodyMedium),
                const SizedBox(height: VerbalTokens.xs),
                Text(e.whyItWorks, style: context.t.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: VerbalTokens.sm),
        ],
      ],
    );
  }
}
