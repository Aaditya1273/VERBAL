import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../domain/difficulty.dart';
import '../../domain/progress.dart';
import '../../domain/scenario.dart';
import '../../shared/widgets.dart';

class ScenariosScreen extends ConsumerWidget {
  const ScenariosScreen({super.key, required this.onOpen});

  final void Function(String scenarioId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenarios = ref.watch(scenariosProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final hasPro = ref.watch(hasProProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scenarios')),
      body: PageBody(
        children: [
          Text(
            'Fewer conversations, built properly. Each one is designed to stress a '
            'specific set of skills.',
            style: context.t.bodySmall,
          ),
          const SizedBox(height: VerbalTokens.lg),
          for (final s in scenarios) ...[
            _ScenarioCard(
              scenario: s,
              mastery: _masteryFor(profile, s.id),
              locked: s.isPro && !hasPro,
              onTap: () {
                ref
                    .read(analyticsProvider)
                    .track(AnalyticsEvent.scenarioViewed, {'scenario': s.id});
                onOpen(s.id);
              },
            ),
            const SizedBox(height: VerbalTokens.md),
          ],
        ],
      ),
    );
  }

  ScenarioMastery? _masteryFor(CommunicationProfile? p, String id) {
    if (p == null) return null;
    for (final m in p.mastery) {
      if (m.scenarioId == id) return m;
    }
    return null;
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.mastery,
    required this.locked,
    required this.onTap,
  });

  final Scenario scenario;
  final ScenarioMastery? mastery;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return VerbalCard(
      onTap: onTap,
      padding: const EdgeInsets.all(VerbalTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(scenario.category.label.toUpperCase(),
                    style: context.t.labelMedium),
              ),
              if (locked) Icon(Icons.lock_outline, size: 15, color: c.muted),
            ],
          ),
          const SizedBox(height: VerbalTokens.sm),
          Text(scenario.title, style: context.t.headlineSmall),
          const SizedBox(height: VerbalTokens.sm),
          Text(scenario.shortDescription,
              style: context.t.bodySmall, maxLines: 3),
          const SizedBox(height: VerbalTokens.md),
          Wrap(
            spacing: VerbalTokens.sm,
            runSpacing: VerbalTokens.sm,
            children: [
              Pill('${scenario.estimatedMinutes} min',
                  icon: Icons.schedule_outlined),
              for (final skill in scenario.rubricFocus) Pill(skill.label),
              if (mastery != null)
                Pill(
                  mastery!.highestCleared == null
                      ? '${mastery!.sessions} attempted'
                      : 'Cleared ${mastery!.highestCleared!.label}',
                  icon: Icons.military_tech_outlined,
                  tone: c.accent,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
