import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/analysis.dart';
import '../../domain/playbook.dart';
import '../../domain/scenario.dart';
import '../../shared/widgets.dart';

/// The user's personal communication library.
///
/// The point of the Playbook is that it compounds: entries arrive from real
/// sessions and come back before the sessions where they are relevant.
class PlaybookScreen extends ConsumerStatefulWidget {
  const PlaybookScreen({super.key, required this.onPractise});

  final VoidCallback onPractise;

  @override
  ConsumerState<PlaybookScreen> createState() => _PlaybookScreenState();
}

class _PlaybookScreenState extends ConsumerState<PlaybookScreen> {
  Skill? _filter;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Matches the line, its title and its reasoning — a saved line is usually
  /// remembered by a phrase inside it, not by the name it was given.
  bool _matches(PlaybookEntry e) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return e.body.toLowerCase().contains(q) ||
        e.title.toLowerCase().contains(q) ||
        e.whyItWorks.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final playbook = ref.watch(playbookProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Playbook')),
      body: playbook.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not open your Playbook. $e')),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Nothing saved yet',
              body: 'Finish a conversation and keep the lines that worked. '
                  'They come back before the sessions where they matter.',
              action: FilledButton(
                onPressed: widget.onPractise,
                child: const Text('Start a conversation'),
              ),
            );
          }

          final entries = all
              .where((e) => _filter == null || e.skill == _filter)
              .where(_matches)
              .toList();

          final skills = all.map((e) => e.skill).toSet().toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(VerbalTokens.lg,
                    VerbalTokens.sm, VerbalTokens.lg, VerbalTokens.sm),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search your lines',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(VerbalTokens.radius),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: VerbalTokens.lg),
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final s in skills)
                      _FilterChip(
                        label: s.label,
                        selected: _filter == s,
                        onTap: () => setState(() => _filter = s),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_outlined,
                        title: 'Nothing matches',
                        body: _query.isEmpty
                            ? 'No saved lines for that skill yet.'
                            : 'No saved line mentions "$_query".',
                      )
                    : PageBody(
                        children: [
                          for (final e in entries) ...[
                            _EntryCard(
                              entry: e,
                              onDelete: () => _delete(e),
                            ),
                            const SizedBox(height: VerbalTokens.md),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(PlaybookEntry entry) async {
    await ref.read(playbookRepositoryProvider).delete(entry.id);
    ref.invalidate(playbookProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Removed.')));
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: VerbalTokens.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onDelete});

  final PlaybookEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return VerbalCard(
      padding: const EdgeInsets.all(VerbalTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.title.toUpperCase(),
                    style: context.t.labelMedium),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Remove from Playbook',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: VerbalTokens.sm),
          Text('“${entry.body}”', style: context.t.bodyLarge),
          const SizedBox(height: VerbalTokens.md),
          Text('Why it works', style: context.t.labelMedium),
          const SizedBox(height: 2),
          Text(entry.whyItWorks, style: context.t.bodySmall),
          const SizedBox(height: VerbalTokens.md),
          Wrap(
            spacing: VerbalTokens.sm,
            runSpacing: VerbalTokens.sm,
            children: [
              Pill(entry.kind.label, tone: c.accent),
              Pill(entry.skill.label),
              if (entry.timesUsed > 0)
                Pill(
                  'Used in ${entry.timesUsed} session${entry.timesUsed == 1 ? '' : 's'}',
                  icon: Icons.replay,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
