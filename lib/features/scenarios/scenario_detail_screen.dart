import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../domain/difficulty.dart';
import '../../domain/scenario.dart';
import '../../domain/scenario_library.dart';
import '../../features/practice/practice_screen.dart';
import '../../shared/widgets.dart';

/// Context, then difficulty, then start. The briefing matters — the user needs
/// to know what they are walking into for the pressure to mean anything.
class ScenarioDetailScreen extends ConsumerStatefulWidget {
  const ScenarioDetailScreen({
    super.key,
    required this.scenarioId,
    required this.onStart,
    required this.onUpgrade,
  });

  final String scenarioId;
  final void Function(String scenarioId, Difficulty difficulty) onStart;
  final VoidCallback onUpgrade;

  @override
  ConsumerState<ScenarioDetailScreen> createState() =>
      _ScenarioDetailScreenState();
}

class _ScenarioDetailScreenState extends ConsumerState<ScenarioDetailScreen> {
  Difficulty _difficulty = Difficulty.moderate;

  @override
  Widget build(BuildContext context) {
    final scenario = ScenarioLibrary.byId(widget.scenarioId);
    if (scenario == null) {
      return const Scaffold(body: Center(child: Text('Scenario not found.')));
    }

    final hasPro = ref.watch(hasProProvider);
    final allowance = ref.watch(allowanceProvider).valueOrNull;
    final locked = scenario.isPro && !hasPro;
    final outOfSessions = allowance != null && !allowance.canPractise;
    final c = context.c;

    return Scaffold(
      appBar: AppBar(title: Text(scenario.category.label)),
      body: PageBody(
        children: [
          Text(scenario.title, style: context.t.displaySmall),
          const SizedBox(height: VerbalTokens.lg),
          const SectionLabel('The situation'),
          Text(scenario.context, style: context.t.bodyMedium),
          const SizedBox(height: VerbalTokens.xl),
          const SectionLabel('Who you are talking to'),
          VerbalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${scenario.actor.name} — ${scenario.actor.role}',
                    style: context.t.titleSmall),
                const SizedBox(height: VerbalTokens.sm),
                Text(scenario.actor.personality, style: context.t.bodySmall),
                const SizedBox(height: VerbalTokens.sm),
                Pill(
                    'Starts ${scenario.actor.initialEmotion.label.toLowerCase()}',
                    icon: Icons.psychology_outlined),
              ],
            ),
          ),
          const SizedBox(height: VerbalTokens.xl),
          const SectionLabel('Your objective'),
          Text(scenario.userObjective, style: context.t.bodyMedium),
          const SizedBox(height: VerbalTokens.md),
          for (final criterion in scenario.successCriteria)
            Padding(
              padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 15, color: c.accent),
                  const SizedBox(width: VerbalTokens.sm),
                  Expanded(child: Text(criterion, style: context.t.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: VerbalTokens.xl),
          PlaybookPrimer(scenarioId: scenario.id),
          const SectionLabel('Difficulty'),
          for (final d in Difficulty.values) ...[
            _DifficultyOption(
              difficulty: d,
              selected: _difficulty == d,
              onTap: () => setState(() => _difficulty = d),
            ),
            const SizedBox(height: VerbalTokens.sm),
          ],
          const SizedBox(height: VerbalTokens.lg),
          if (locked)
            FilledButton(
              onPressed: widget.onUpgrade,
              child: const Text('Unlock with Pro'),
            )
          else if (outOfSessions)
            Column(
              children: [
                Text(
                  'You have used your free sessions for this week.',
                  textAlign: TextAlign.center,
                  style: context.t.bodySmall,
                ),
                const SizedBox(height: VerbalTokens.md),
                FilledButton(
                    onPressed: widget.onUpgrade,
                    child: const Text('Get unlimited practice')),
              ],
            )
          else
            FilledButton(
              onPressed: () {
                ref.read(analyticsProvider).track(
                  AnalyticsEvent.scenarioSelected,
                  {'scenario': scenario.id, 'difficulty': _difficulty.name},
                );
                widget.onStart(scenario.id, _difficulty);
              },
              child: const Text('Start the conversation'),
            ),
          const SizedBox(height: VerbalTokens.md),
          Text(
            'VERBAL is a rehearsal tool. It is not HR, legal or medical advice.',
            textAlign: TextAlign.center,
            style: context.t.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DifficultyOption extends StatelessWidget {
  const _DifficultyOption({
    required this.difficulty,
    required this.selected,
    required this.onTap,
  });

  final Difficulty difficulty;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = difficulty.profile;
    return Semantics(
      selected: selected,
      child: VerbalCard(
        onTap: onTap,
        accent: selected,
        padding: const EdgeInsets.symmetric(
            horizontal: VerbalTokens.md, vertical: VerbalTokens.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(difficulty.label, style: context.t.titleSmall),
                  const SizedBox(height: 2),
                  Text(difficulty.blurb, style: context.t.bodySmall),
                  const SizedBox(height: VerbalTokens.sm),
                  Text(
                    '${p.objectionCount} objections · '
                    '${p.allowsEarlyResolution ? 'can end early' : 'no early exit'} · '
                    'up to ${p.maxTurns} turns',
                    style: context.t.labelSmall,
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: context.c.accent),
          ],
        ),
      ),
    );
  }
}
