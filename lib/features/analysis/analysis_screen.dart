import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/experiments.dart';
import '../../domain/analysis.dart';
import '../../domain/difficulty.dart';
import '../../domain/pitfall.dart';
import '../../domain/playbook.dart';
import '../../domain/scenario.dart';
import '../../domain/session.dart';
import '../../shared/widgets.dart';

/// Post-session feedback, then the Playbook, then the next practice.
///
/// The order is the retention loop: the user sees what happened, keeps
/// something reusable, and is handed a reason to come back.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.sessionId,
    required this.onPractiseNext,
    required this.onDone,
  });

  final String sessionId;
  final void Function(String scenarioId, Difficulty difficulty) onPractiseNext;
  final VoidCallback onDone;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  final _saved = <String>{};

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvent.analysisViewed);
    // Exposure is recorded where the experiment surface actually appears.
    ref
        .read(experimentServiceProvider)
        .trackExposure(Experiment.playbookAfterFirstSession);
  }

  Future<void> _save(PlaybookCandidate candidate, String scenarioId) async {
    final entry = PlaybookEntry.fromCandidate(
      candidate,
      id: 'p_${DateTime.now().microsecondsSinceEpoch}',
      scenarioId: scenarioId,
      createdAt: DateTime.now(),
    );

    await ref.read(playbookRepositoryProvider).add(entry);
    ref.read(analyticsProvider).track(AnalyticsEvent.playbookCreated, {
      'kind': candidate.kind.name,
      'skill': candidate.skill.name,
      'scenario': scenarioId,
    });

    if (!mounted) return;
    setState(() => _saved.add(candidate.body));
    ref.invalidate(playbookProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved to your Playbook.')));
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Session review'),
        actions: [
          TextButton(onPressed: widget.onDone, child: const Text('Done')),
          const SizedBox(width: VerbalTokens.sm),
        ],
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the session. $e')),
        data: (list) {
          final session =
              list.where((s) => s.id == widget.sessionId).firstOrNull;
          if (session == null) {
            return const EmptyState(
              title: 'Session not found',
              body: 'It may have been deleted.',
            );
          }
          return _Analysis(
            session: session,
            saved: _saved,
            onSave: (c) => _save(c, session.scenarioId),
            onPractiseNext: widget.onPractiseNext,
          );
        },
      ),
    );
  }
}

class _Analysis extends ConsumerWidget {
  const _Analysis({
    required this.session,
    required this.saved,
    required this.onSave,
    required this.onPractiseNext,
  });

  final PracticeSession session;
  final Set<String> saved;
  final void Function(PlaybookCandidate) onSave;
  final void Function(String scenarioId, Difficulty difficulty) onPractiseNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = session.analysis;
    final c = context.c;

    if (a == null) {
      return const EmptyState(
        title: 'Not analysed yet',
        body: 'This session was saved but has not been reviewed.',
      );
    }

    final analysed = a.overall > 0;
    final next = ref.watch(nextPracticeProvider).valueOrNull;

    return PageBody(
      children: [
        Text(session.scenarioTitle.toUpperCase(), style: context.t.labelMedium),
        const SizedBox(height: VerbalTokens.sm),
        if (analysed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _ScoreReveal(score: a.overall),
              const SizedBox(width: VerbalTokens.sm),
              Expanded(child: Text('overall', style: context.t.bodySmall)),
              Pill(
                a.objectiveMet ? 'Objective met' : 'Objective missed',
                icon: a.objectiveMet ? Icons.check : Icons.remove,
                tone: a.objectiveMet ? c.accent : c.signal,
              ),
            ],
          ),
          const SizedBox(height: VerbalTokens.md),
        ],
        Text(a.summary, style: context.t.bodyLarge),
        const SizedBox(height: VerbalTokens.md),
        // Wrap, not Row: three pills do not fit on a 360dp phone.
        Wrap(
          spacing: VerbalTokens.sm,
          runSpacing: VerbalTokens.sm,
          children: [
            Pill(session.difficulty.label, icon: Icons.speed_outlined),
            Pill('${session.userTurnCount} turns', icon: Icons.forum_outlined),
            Pill(
                '${session.objectionsHandled}/${session.objectionsRaised} handled',
                icon: Icons.shield_outlined),
          ],
        ),
        const SizedBox(height: VerbalTokens.xl),
        if (analysed) ...[
          const SectionLabel('Skills'),
          VerbalCard(
            child: Column(
              children: [
                for (final s in a.scores)
                  SkillBar(skill: s.skill, score: s.score),
              ],
            ),
          ),
          const SizedBox(height: VerbalTokens.xl),
        ],
        if (a.dearMan.isNotEmpty) ...[
          SectionLabel(
            'DEAR MAN',
            trailing: Text('DBT rubric', style: context.t.labelSmall),
          ),
          VerbalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Whether the ask itself was built properly, scored separately '
                  'from how the conversation felt.',
                  style: context.t.bodySmall,
                ),
                const SizedBox(height: VerbalTokens.sm),
                for (final d in a.dearMan) _DearManRow(score: d),
              ],
            ),
          ),
          const SizedBox(height: VerbalTokens.xl),
        ],

        if (a.worked.isNotEmpty) ...[
          const SectionLabel('What worked'),
          for (final m in a.worked) _MomentCard(moment: m, positive: true),
          const SizedBox(height: VerbalTokens.xl),
        ],
        if (a.weakened.isNotEmpty) ...[
          const SectionLabel('What weakened the conversation'),
          for (final m in a.weakened) _MomentCard(moment: m, positive: false),
          const SizedBox(height: VerbalTokens.xl),
        ],
        if (a.committedPitfalls.isNotEmpty) ...[
          const SectionLabel('What tripped you up'),
          for (final id in a.committedPitfalls.toSet())
            if (PitfallLibrary.byId(id) case final p?)
              _PitfallCard(
                pitfall: p,
                times: a.committedPitfalls.where((x) => x == id).length,
              ),
          const SizedBox(height: VerbalTokens.xl),
        ],

        if (a.betterAlternative.quote.isNotEmpty) ...[
          const SectionLabel('Better alternative'),
          VerbalCard(
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('“${a.betterAlternative.quote}”',
                    style: context.t.bodyLarge),
                const SizedBox(height: VerbalTokens.sm),
                Text(a.betterAlternative.why, style: context.t.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: VerbalTokens.xl),
        ],
        if (a.playbookCandidates.isNotEmpty) ...[
          const SectionLabel('Keep these'),
          for (final candidate in a.playbookCandidates) ...[
            _CandidateCard(
              candidate: candidate,
              saved: saved.contains(candidate.body),
              onSave: () => onSave(candidate),
            ),
            const SizedBox(height: VerbalTokens.sm),
          ],
          const SizedBox(height: VerbalTokens.xl),
        ],
        const SectionLabel('Practise next'),
        VerbalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Focus on ${a.nextSkill.label.toLowerCase()}',
                  style: context.t.titleMedium),
              const SizedBox(height: VerbalTokens.xs),
              Text(a.nextSkill.description, style: context.t.bodySmall),
              if (next != null) ...[
                const SizedBox(height: VerbalTokens.md),
                FilledButton(
                  onPressed: () =>
                      onPractiseNext(next.scenario.id, next.difficulty),
                  child:
                      Text('${next.scenario.title} · ${next.difficulty.label}'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: VerbalTokens.lg),
        ExpansionTile(
          title: Text('Full transcript', style: context.t.titleSmall),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: VerbalTokens.md),
          children: [
            for (final turn in session.turns)
              Padding(
                padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(turn.speaker == Speaker.user ? 'YOU' : 'THEM',
                        style: context.t.labelMedium),
                    Text(turn.text, style: context.t.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The headline number, counted up once so the result feels earned.
class _ScoreReveal extends StatelessWidget {
  const _ScoreReveal({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final duration = context.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 900);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(
        '${value.round()}',
        style: context.t.displaySmall?.copyWith(fontSize: 46),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment, required this.positive});

  final Moment moment;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
      child: VerbalCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(positive ? Icons.add : Icons.remove,
                    size: 15, color: positive ? c.accent : c.signal),
                const SizedBox(width: VerbalTokens.sm),
                Expanded(
                  child: Text('“${moment.quote}”', style: context.t.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: VerbalTokens.sm),
            Padding(
              padding: const EdgeInsets.only(left: 23),
              child: Text(moment.why, style: context.t.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// One DEAR MAN component. Reuses the score bar's visual language without
/// pretending it is one of the six skills.
class _DearManRow extends StatelessWidget {
  const _DearManRow({required this.score});

  final DearManScore score;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final value = (score.score / 100).clamp(0.0, 1.0);

    return Semantics(
      label: '${score.component.label}: ${score.score} out of 100',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VerbalTokens.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text(score.component.label, style: context.t.bodyMedium),
                ),
                Text('${score.score}', style: context.t.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: context.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: c.line,
                  valueColor: AlwaysStoppedAnimation(
                    score.score >= 70
                        ? c.accent
                        : (score.score >= 45 ? c.muted : c.signal),
                  ),
                ),
              ),
            ),
            if (score.note.isNotEmpty) ...[
              const SizedBox(height: VerbalTokens.xs),
              Text(score.note, style: context.t.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// A pitfall that actually fired, with the move that would have avoided it.
class _PitfallCard extends StatelessWidget {
  const _PitfallCard({required this.pitfall, required this.times});

  final Pitfall pitfall;
  final int times;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
      child: VerbalCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 15, color: c.signal),
                const SizedBox(width: VerbalTokens.sm),
                Expanded(
                  child: Text(pitfall.name, style: context.t.titleSmall),
                ),
                if (times > 1) Pill('${times}x', tone: c.signal),
              ],
            ),
            const SizedBox(height: VerbalTokens.sm),
            Padding(
              padding: const EdgeInsets.only(left: 23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Do this instead', style: context.t.labelMedium),
                  const SizedBox(height: 2),
                  Text(pitfall.skilledAlternative, style: context.t.bodySmall),
                  const SizedBox(height: VerbalTokens.sm),
                  Pill(pitfall.coreSkill.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.saved,
    required this.onSave,
  });

  final PlaybookCandidate candidate;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return VerbalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: VerbalTokens.sm,
            runSpacing: VerbalTokens.sm,
            children: [
              Pill(candidate.kind.label, tone: context.c.accent),
              Pill(candidate.skill.label),
            ],
          ),
          const SizedBox(height: VerbalTokens.sm),
          Text('“${candidate.body}”', style: context.t.bodyLarge),
          const SizedBox(height: VerbalTokens.xs),
          Text(candidate.whyItWorks, style: context.t.bodySmall),
          const SizedBox(height: VerbalTokens.md),
          saved
              ? Row(
                  children: [
                    Icon(Icons.check, size: 16, color: context.c.accent),
                    const SizedBox(width: VerbalTokens.sm),
                    Text('In your Playbook', style: context.t.bodySmall),
                  ],
                )
              : OutlinedButton(
                  onPressed: onSave,
                  child: const Text('Save to Playbook'),
                ),
        ],
      ),
    );
  }
}
