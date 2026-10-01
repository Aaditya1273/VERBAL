import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/difficulty.dart';
import '../../domain/progress.dart';
import '../../domain/scenario.dart';
import '../../domain/scenario_library.dart';
import '../../domain/session.dart';
import '../../shared/widgets.dart';

/// Skills, mastery and the observed pattern — all derived from real sessions.
class ProgressView extends ConsumerWidget {
  const ProgressView({super.key, required this.onPractise});

  final VoidCallback onPractise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final sessions = ref.watch(sessionsProvider).valueOrNull ?? const [];

    return profile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load progress. $e')),
      data: (p) {
        if (p.isEmpty) {
          return EmptyState(
            icon: Icons.insights_outlined,
            title: 'No results yet',
            body: 'Your communication profile is built from real sessions, '
                'so it stays empty until you finish one.',
            action: FilledButton(
                onPressed: onPractise, child: const Text('Practise now')),
          );
        }

        return PageBody(
          children: [
            const SectionLabel('Confidence'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${p.confidence}',
                    style: context.t.displaySmall?.copyWith(fontSize: 46)),
                const SizedBox(width: VerbalTokens.sm),
                // Expanded, or a large session count overflows a narrow phone.
                Expanded(
                  child: Text('across ${p.totalSessions} sessions',
                      style: context.t.bodySmall),
                ),
              ],
            ),
            const SizedBox(height: VerbalTokens.xl),
            const SectionLabel('Skills'),
            VerbalCard(
              child: Column(
                children: [
                  for (final s in p.standings)
                    SkillBar(
                      skill: s.skill,
                      score: s.score,
                      delta: s.isReliable ? s.delta : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: VerbalTokens.xl),
            if (p.observedPattern != null) ...[
              const SectionLabel('Observed pattern'),
              VerbalCard(
                accent: true,
                child: Text(p.observedPattern!, style: context.t.bodyLarge),
              ),
              const SizedBox(height: VerbalTokens.xl),
            ],
            const SectionLabel('Your profile'),
            VerbalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.strengths.isNotEmpty) ...[
                    Text('Strengths', style: context.t.titleSmall),
                    const SizedBox(height: VerbalTokens.xs),
                    for (final s in p.strengths)
                      Text('• ${s.skill.label} (${s.score})',
                          style: context.t.bodySmall),
                    const SizedBox(height: VerbalTokens.md),
                  ],
                  Text('Focus areas', style: context.t.titleSmall),
                  const SizedBox(height: VerbalTokens.xs),
                  for (final s in p.focusAreas)
                    Text('• ${s.skill.label} (${s.score})',
                        style: context.t.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: VerbalTokens.xl),
            const SectionLabel('Scenario mastery'),
            for (final m in p.mastery) ...[
              _MasteryRow(mastery: m),
              const SizedBox(height: VerbalTokens.sm),
            ],
            const SizedBox(height: VerbalTokens.xl),
            const SectionLabel('Recent sessions'),
            for (final s in sessions.take(8)) _SessionRow(session: s),
          ],
        );
      },
    );
  }
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({required this.mastery});

  final ScenarioMastery mastery;

  @override
  Widget build(BuildContext context) {
    final scenario = ScenarioLibrary.byId(mastery.scenarioId);
    return VerbalCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scenario?.title ?? mastery.scenarioId,
                    style: context.t.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${mastery.sessions} session${mastery.sessions == 1 ? '' : 's'} · best ${mastery.bestOverall}',
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
          if (mastery.highestCleared != null)
            Pill(mastery.highestCleared!.label, tone: context.c.accent),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final PracticeSession session;

  @override
  Widget build(BuildContext context) {
    final overall = session.analysis?.overall ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.scenarioTitle, style: context.t.bodyMedium),
                Text(
                  '${session.difficulty.label} · ${session.userTurnCount} turns',
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
          Text(overall > 0 ? '$overall' : '—', style: context.t.titleSmall),
        ],
      ),
    );
  }
}
