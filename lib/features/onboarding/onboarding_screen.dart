import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../shared/widgets.dart';

/// One question, then straight into a conversation.
///
/// Anything longer delays the only thing that actually sells the product —
/// feeling the pressure of a real exchange.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  /// The interests offered on screen. Public so the test asserts against the
  /// real list — an earlier test checked a hand-copied duplicate and passed
  /// while the UI was missing an option.
  static const interests = [
    (key: 'managing', label: 'Managing people', icon: Icons.groups_outlined),
    (key: 'negotiating', label: 'Negotiating', icon: Icons.balance_outlined),
    (key: 'conflict', label: 'Handling conflict', icon: Icons.bolt_outlined),
    (
      key: 'boundaries',
      label: 'Setting boundaries',
      icon: Icons.shield_outlined
    ),
    (
      key: 'feedback',
      label: 'Giving feedback',
      icon: Icons.rate_review_outlined
    ),
  ];

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvent.onboardingStarted);
  }

  Future<void> _continue() async {
    if (_selected == null || _saving) return;
    setState(() => _saving = true);

    await ref.read(profileRepositoryProvider).completeOnboarding(_selected!);
    ref
        .read(analyticsProvider)
        .track(AnalyticsEvent.onboardingCompleted, {'interest': _selected});

    if (!mounted) return;
    // The router's redirect reads onboardedProvider. Without invalidating it the
    // redirect still sees "not onboarded" and sends the user straight back here.
    ref
      ..invalidate(onboardedProvider)
      ..invalidate(interestProvider)
      ..invalidate(nextPracticeProvider);

    // Wait for the redirect's source of truth to actually be true before
    // navigating, otherwise go('/') races the refreshed provider.
    await ref.read(onboardedProvider.future);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageBody(
                children: [
                  const SizedBox(height: VerbalTokens.xl),
                  Text('VERBAL', style: context.t.labelMedium),
                  const SizedBox(height: VerbalTokens.sm),
                  Text(
                    'Practice difficult conversations before you have them.',
                    style: context.t.displaySmall,
                  ),
                  const SizedBox(height: VerbalTokens.md),
                  Text(
                    'You will speak out loud. The other person will push back. '
                    'Afterwards you will get specific feedback and keep the lines that worked.',
                    style: context.t.bodyMedium?.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: VerbalTokens.xxl),
                  const SectionLabel('What do you want to get better at?'),
                  for (final i in OnboardingScreen.interests) ...[
                    _Choice(
                      label: i.label,
                      icon: i.icon,
                      selected: _selected == i.key,
                      onTap: () => setState(() => _selected = i.key),
                    ),
                    const SizedBox(height: VerbalTokens.sm),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(VerbalTokens.lg),
              child: FilledButton(
                onPressed: _selected == null || _saving ? null : _continue,
                child: Text(
                    _saving ? 'Setting up…' : 'Choose your first conversation'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      button: true,
      child: VerbalCard(
        onTap: onTap,
        accent: selected,
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? c.accent : c.muted),
            const SizedBox(width: VerbalTokens.md),
            Expanded(child: Text(label, style: context.t.titleSmall)),
            if (selected) Icon(Icons.check, size: 18, color: c.accent),
          ],
        ),
      ),
    );
  }
}
