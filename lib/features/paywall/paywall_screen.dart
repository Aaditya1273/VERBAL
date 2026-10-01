import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/analytics.dart';
import '../../core/billing.dart';
import '../../core/failures.dart';
import '../../shared/widgets.dart';

/// Pro. Sold on what practice actually unlocks, not on urgency tricks.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late Future<List<Plan>> _plans;
  String? _busyPlan;
  Failure? _failure;

  static const _proFeatures = [
    (
      Icons.all_inclusive,
      'Unlimited practice',
      'No weekly limit. Rehearse the same conversation until it lands.'
    ),
    (
      Icons.lock_open_outlined,
      'Every scenario',
      'Including the hardest ones, like the termination conversation.'
    ),
    (
      Icons.insights_outlined,
      'Full analysis',
      'Every skill scored, with the evidence from your transcript.'
    ),
    (
      Icons.menu_book_outlined,
      'Unlimited Playbook',
      'Keep every line and framework, and have them resurface when relevant.'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _plans = ref.read(billingProvider).offerings();
    ref.read(analyticsProvider).track(AnalyticsEvent.paywallViewed);
  }

  Future<void> _purchase(Plan plan) async {
    setState(() {
      _busyPlan = plan.id;
      _failure = null;
    });

    try {
      await ref.read(billingProvider).purchase(plan.id);
      if (!mounted) return;
      widget.onClose();
    } on Failure catch (f) {
      if (mounted) setState(() => _failure = f);
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  Future<void> _restore() async {
    setState(() => _failure = null);
    try {
      final entitlement = await ref.read(billingProvider).restore();
      if (!mounted) return;
      if (entitlement.isPro) {
        widget.onClose();
      } else {
        setState(() => _failure = const BillingFailure(
            'No previous purchase found on this account.'));
      }
    } on Failure catch (f) {
      if (mounted) setState(() => _failure = f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: widget.onClose, icon: const Icon(Icons.close)),
        actions: [
          TextButton(onPressed: _restore, child: const Text('Restore')),
          const SizedBox(width: VerbalTokens.sm),
        ],
      ),
      body: PageBody(
        children: [
          Text('VERBAL PRO', style: context.t.labelMedium),
          const SizedBox(height: VerbalTokens.sm),
          Text('Practise until it is automatic.',
              style: context.t.displaySmall),
          const SizedBox(height: VerbalTokens.xl),
          for (final f in _proFeatures) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(f.$1, size: 19, color: c.accent),
                const SizedBox(width: VerbalTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.$2, style: context.t.titleSmall),
                      const SizedBox(height: 2),
                      Text(f.$3, style: context.t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: VerbalTokens.lg),
          ],
          const SizedBox(height: VerbalTokens.md),
          FutureBuilder<List<Plan>>(
            future: _plans,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(VerbalTokens.lg),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final plans = snapshot.data ?? const <Plan>[];
              if (plans.isEmpty) {
                // Honest about the real state rather than showing fake prices.
                return VerbalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Purchasing is not available in this build.',
                          style: context.t.titleSmall),
                      const SizedBox(height: VerbalTokens.xs),
                      Text(
                        'No store products were returned. Configure RevenueCat and run on a '
                        'device signed into a store account to purchase.',
                        style: context.t.bodySmall,
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (final plan in plans) ...[
                    _PlanCard(
                      plan: plan,
                      busy: _busyPlan == plan.id,
                      onTap: () => _purchase(plan),
                    ),
                    const SizedBox(height: VerbalTokens.sm),
                  ],
                ],
              );
            },
          ),
          if (_failure != null) ...[
            const SizedBox(height: VerbalTokens.md),
            Text(
              _failure!.message,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(color: c.signal),
            ),
          ],
          const SizedBox(height: VerbalTokens.lg),
          Text(
            'Subscriptions renew automatically until cancelled. Manage or cancel in your '
            'store account settings.',
            textAlign: TextAlign.center,
            style: context.t.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.busy,
    required this.onTap,
  });

  final Plan plan;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VerbalCard(
      onTap: busy ? null : onTap,
      accent: plan.isAnnual,
      padding: const EdgeInsets.all(VerbalTokens.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.title, style: context.t.titleMedium),
                const SizedBox(height: 2),
                Text('${plan.priceString} ${plan.period}',
                    style: context.t.bodySmall),
                if (plan.trialDays != null) ...[
                  const SizedBox(height: VerbalTokens.sm),
                  Pill('${plan.trialDays} day free trial',
                      tone: context.c.accent),
                ],
              ],
            ),
          ),
          if (busy)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
