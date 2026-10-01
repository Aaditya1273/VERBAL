import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/billing.dart';
import '../../domain/difficulty.dart';
import '../../domain/playbook.dart';
import '../../domain/recommendation.dart';
import '../../domain/session.dart';
import '../../shared/presence.dart';
import '../../shared/widgets.dart';

/// What to practise next, how you are doing, and one strong action.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onPractise,
    required this.onOpenPlaybook,
    required this.onOpenScenarios,
    required this.onOpenPaywall,
  });

  final void Function(String scenarioId, Difficulty difficulty) onPractise;
  final VoidCallback onOpenPlaybook;
  final VoidCallback onOpenScenarios;
  final VoidCallback onOpenPaywall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextPracticeProvider);
    final playbook = ref.watch(playbookProvider);
    final allowance = ref.watch(allowanceProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => invalidateUserData(ref),
          child: PageBody(
            children: [
              const SizedBox(height: VerbalTokens.sm),
              // The other person greets you before any words do.
              const Center(child: Presence(size: 168, expression: Expression.happy)),
              const SizedBox(height: VerbalTokens.sm),
              Text(_greeting(), style: context.t.bodyMedium),
              const SizedBox(height: VerbalTokens.xs),
              Text('Ready for your next conversation?',
                  style: context.t.displaySmall),
              const SizedBox(height: VerbalTokens.lg),
              next.when(
                data: (n) => _NextPractice(
                  key: ValueKey('${n.scenario.id}:${n.difficulty.name}'),
                  next: n,
                  onPractise: () {
                    ref.read(analyticsProvider).track(
                      AnalyticsEvent.nextPracticeSelected,
                      {
                        'scenario': n.scenario.id,
                        'difficulty': n.difficulty.name
                      },
                    );
                    onPractise(n.scenario.id, n.difficulty);
                  },
                ),
                loading: () => const _LoadingCard(),
                error: (e, _) => VerbalCard(
                  child: Text('Could not load a recommendation.',
                      style: context.t.bodyMedium),
                ),
              ),
              allowance.maybeWhen(
                data: (a) => a.isPro || a.canPractise
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: VerbalTokens.md),
                        child: _LimitBanner(onUpgrade: onOpenPaywall),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: VerbalTokens.xl),
              playbook.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? _PlaybookTeaser(onOpen: onOpenScenarios)
                    : _RecentInsight(
                        entry: entries.first, onOpen: onOpenPlaybook),
                orElse: () => const SizedBox.shrink(),
              ),
              ref.watch(sessionsProvider).maybeWhen(
                    data: (list) => list.isEmpty
                        ? const SizedBox.shrink()
                        : _RecentSessions(sessions: list),
                    orElse: () => const SizedBox.shrink(),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning.';
    if (hour < 18) return 'Good afternoon.';
    return 'Good evening.';
  }
}

/// Records that a recommendation was actually put in front of the user, which
/// is what makes the selection rate meaningful.
class _NextPractice extends ConsumerStatefulWidget {
  const _NextPractice({
    super.key,
    required this.next,
    required this.onPractise,
  });

  final NextPractice next;
  final VoidCallback onPractise;

  @override
  ConsumerState<_NextPractice> createState() => _NextPracticeState();
}

class _NextPracticeState extends ConsumerState<_NextPractice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsProvider).track(AnalyticsEvent.recommendationShown, {
        'scenario': widget.next.scenario.id,
        'difficulty': widget.next.difficulty.name,
        'targetSkill': widget.next.targetSkill.name,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.next;
    final onPractise = widget.onPractise;
    final c = context.c;
    return VerbalCard(
      accent: true,
      padding: const EdgeInsets.all(VerbalTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Recommended'),
          Text(next.scenario.title, style: context.t.headlineSmall),
          const SizedBox(height: VerbalTokens.sm),
          Text(next.reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: VerbalTokens.md),
          Wrap(
            spacing: VerbalTokens.sm,
            runSpacing: VerbalTokens.sm,
            children: [
              Pill(next.difficulty.label, icon: Icons.speed_outlined),
              Pill('${next.scenario.estimatedMinutes} min',
                  icon: Icons.schedule_outlined),
            ],
          ),
          const SizedBox(height: VerbalTokens.lg),
          FilledButton(
              onPressed: onPractise, child: const Text('Practise now')),
        ],
      ),
    );
  }
}

class _RecentInsight extends StatelessWidget {
  const _RecentInsight({required this.entry, required this.onOpen});

  final PlaybookEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Recent playbook insight',
          trailing: TextButton(onPressed: onOpen, child: const Text('Open')),
        ),
        VerbalCard(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('“${entry.body}”', style: context.t.bodyLarge),
              const SizedBox(height: VerbalTokens.sm),
              Text(entry.whyItWorks, style: context.t.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaybookTeaser extends StatelessWidget {
  const _PlaybookTeaser({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Your playbook'),
        VerbalCard(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Empty until your first session.',
                  style: context.t.bodyMedium),
              const SizedBox(height: VerbalTokens.xs),
              Text(
                'Every conversation you finish leaves behind the lines and frameworks that worked, '
                'and brings them back when they are useful.',
                style: context.t.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The last few conversations, so returning users land on their own history
/// rather than a blank slate.
class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.sessions});

  final List<PracticeSession> sessions;

  @override
  Widget build(BuildContext context) {
    final recent = sessions.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: VerbalTokens.xl),
        const SectionLabel('Recent sessions'),
        for (final s in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: VerbalTokens.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.scenarioTitle, style: context.t.bodyMedium),
                      Text(
                        '${s.difficulty.label} - ${s.userTurnCount} turns',
                        style: context.t.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  (s.analysis?.overall ?? 0) > 0
                      ? '${s.analysis!.overall}'
                      : '-',
                  style: context.t.titleSmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LimitBanner extends StatelessWidget {
  const _LimitBanner({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return VerbalCard(
      onTap: onUpgrade,
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: context.c.muted),
          const SizedBox(width: VerbalTokens.md),
          Expanded(
            child: Text(
              'You have used all ${PracticeAllowance.freeSessionsPerWeek} free sessions this week.',
              style: context.t.bodySmall,
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const VerbalCard(
        padding: EdgeInsets.all(VerbalTokens.xl),
        child: Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}
