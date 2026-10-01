import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/billing.dart';
import '../../shared/widgets.dart';
import '../progress/progress_screen.dart';

/// Progress and settings. Progress leads, because that is what the user came
/// for; settings sit behind a tab.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({
    super.key,
    required this.onPractise,
    required this.onUpgrade,
  });

  final VoidCallback onPractise;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('You'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Progress'), Tab(text: 'Settings')],
          ),
        ),
        body: TabBarView(
          children: [
            ProgressView(onPractise: onPractise),
            _Settings(onUpgrade: onUpgrade),
          ],
        ),
      ),
    );
  }
}

class _Settings extends ConsumerStatefulWidget {
  const _Settings({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  ConsumerState<_Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<_Settings> {
  bool? _voiceOutput;

  @override
  void initState() {
    super.initState();
    _loadVoicePreference();
  }

  Future<void> _loadVoicePreference() async {
    final enabled =
        await ref.read(profileRepositoryProvider).voiceOutputEnabled();
    if (mounted) setState(() => _voiceOutput = enabled);
  }

  Future<void> _setVoiceOutput(bool value) async {
    setState(() => _voiceOutput = value);
    await ref.read(profileRepositoryProvider).setVoiceOutputEnabled(value);
  }

  Future<void> _deleteEverything() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all practice data?'),
        content: const Text(
          'This permanently removes every transcript, score and Playbook entry '
          'from this device. It cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete everything')),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(sessionRepositoryProvider).deleteAll();
    await ref.read(playbookRepositoryProvider).deleteAll();
    if (!mounted) return;

    invalidateUserData(ref);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All practice data deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final hasPro = ref.watch(hasProProvider);
    final allowance = ref.watch(allowanceProvider).valueOrNull;

    return PageBody(
      children: [
        const SectionLabel('Plan'),
        VerbalCard(
          onTap: hasPro ? null : widget.onUpgrade,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasPro ? 'VERBAL Pro' : 'Free',
                        style: context.t.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      hasPro
                          ? 'Unlimited practice and every scenario.'
                          : allowance == null
                              ? '${PracticeAllowance.freeSessionsPerWeek} sessions a week.'
                              : '${allowance.remaining} of ${allowance.limit} sessions left this week.',
                      style: context.t.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!hasPro) const Icon(Icons.chevron_right),
            ],
          ),
        ),
        const SizedBox(height: VerbalTokens.xl),
        const SectionLabel('Practice'),
        VerbalCard(
          padding: const EdgeInsets.symmetric(horizontal: VerbalTokens.md),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Speak replies out loud', style: context.t.bodyMedium),
            subtitle: Text(
              'Turn off to read the other person\'s lines instead.',
              style: context.t.bodySmall,
            ),
            value: _voiceOutput ?? true,
            onChanged: _voiceOutput == null ? null : _setVoiceOutput,
          ),
        ),
        const SizedBox(height: VerbalTokens.xl),
        const SectionLabel('Your data'),
        VerbalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transcripts, scores and Playbook entries are stored only on this device. '
                'They are never uploaded, and analytics never carries conversation content.',
                style: context.t.bodySmall,
              ),
              const SizedBox(height: VerbalTokens.md),
              OutlinedButton(
                onPressed: _deleteEverything,
                child: const Text('Delete all practice data'),
              ),
            ],
          ),
        ),
        const SizedBox(height: VerbalTokens.xl),
        const SectionLabel('This build'),
        VerbalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ConfigRow(
                label: 'AI conversation engine',
                on: config.hasAi,
                offText: 'scripted rehearsal',
              ),
              _ConfigRow(
                label: 'ElevenLabs voice',
                on: config.hasPremiumVoice,
                offText: 'device voice',
              ),
              _ConfigRow(
                label: 'RevenueCat',
                on: config.hasBilling,
                offText: 'not configured',
              ),
            ],
          ),
        ),
        const SizedBox(height: VerbalTokens.xl),
        Text(
          'VERBAL is a rehearsal tool for practising conversations. It does not give HR, '
          'legal, medical or financial advice, and the people in it are simulated.',
          style: context.t.bodySmall,
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({
    required this.label,
    required this.on,
    required this.offText,
  });

  final String label;
  final bool on;
  final String offText;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VerbalTokens.xs),
      child: Row(
        children: [
          Icon(on ? Icons.check_circle_outline : Icons.remove_circle_outline,
              size: 16, color: on ? c.accent : c.muted),
          const SizedBox(width: VerbalTokens.sm),
          Expanded(child: Text(label, style: context.t.bodyMedium)),
          Text(on ? 'on' : offText, style: context.t.bodySmall),
        ],
      ),
    );
  }
}
