import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/failures.dart';
import '../domain/scenario.dart';

/// Small uppercase section label. Used instead of heavy card headers.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VerbalTokens.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: context.t.labelMedium,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The standard surface. One border, no shadow, no glass.
class VerbalCard extends StatelessWidget {
  const VerbalCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(VerbalTokens.md),
    this.accent = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  /// Draws the card in the accent colour, for the single primary action.
  final bool accent;

  @override
  Widget build(BuildContext context) => GlassPanel(
        onTap: onTap,
        padding: padding,
        accent: accent,
        child: child,
      );
}

/// A small piece of metadata: difficulty, duration, category.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.tone});

  final String text;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = tone ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: VerbalTokens.sm + 2, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: context.t.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// A single skill score with its bar. Animates on first build so the score
/// reveal reads as a result rather than a static number.
class SkillBar extends StatelessWidget {
  const SkillBar({
    super.key,
    required this.skill,
    required this.score,
    this.delta,
    this.animate = true,
  });

  final Skill skill;
  final int score;
  final int? delta;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final showDelta = delta != null && delta != 0;
    final duration = (animate && !context.reduceMotion)
        ? const Duration(milliseconds: 700)
        : Duration.zero;

    return Semantics(
      label: '${skill.label}: $score out of 100'
          '${showDelta ? ', ${delta! > 0 ? 'up' : 'down'} ${delta!.abs()}' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VerbalTokens.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(skill.label, style: context.t.bodyMedium)),
                if (showDelta) ...[
                  Icon(
                    delta! > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: delta! > 0 ? c.accent : c.signal,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${delta!.abs()}',
                    style: context.t.labelSmall?.copyWith(
                      color: delta! > 0 ? c.accent : c.signal,
                    ),
                  ),
                  const SizedBox(width: VerbalTokens.sm),
                ],
                SizedBox(
                  width: 30,
                  child: Text(
                    '$score',
                    textAlign: TextAlign.right,
                    style: context.t.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: c.ink.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(
                    score >= 70 ? c.accent : (score >= 45 ? c.muted : c.signal),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A live input-level waveform. Symmetric bars driven by recent mic levels.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.levels,
    required this.active,
    this.color,
  });

  /// Most recent first, 0..1.
  final List<double> levels;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (active ? context.c.signal : context.c.muted);
    return SizedBox(
      height: 56,
      child: CustomPaint(
        painter: _WaveformPainter(levels: levels, color: c, active: active),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.color,
    required this.active,
  });

  final List<double> levels;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    // Nothing to say when nobody is talking: an idle row of dots is noise.
    if (!active) return;
    const barWidth = 3.0;
    const gap = 4.0;
    final count = (size.width / (barWidth + gap)).floor();
    final mid = size.height / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final level = i < levels.length ? levels[i] : 0.0;
      // A visible floor keeps the idle state looking alive but calm.
      final amplitude = active ? math.max(0.06, level) * mid : 0.05 * mid;
      final x = size.width - (i * (barWidth + gap)) - barWidth;
      canvas.drawLine(
        Offset(x, mid - amplitude),
        Offset(x, mid + amplitude),
        paint
          ..color =
              color.withValues(alpha: active ? 1.0 - (i / count) * 0.75 : 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.levels != levels || old.active != active || old.color != color;
}

/// Shown when something went wrong. Always names a way forward.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VerbalTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: c.signal, size: 28),
            const SizedBox(height: VerbalTokens.md),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: context.t.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: VerbalTokens.lg),
              OutlinedButton(
                  onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty states say what will fill them, not just that they are empty.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VerbalTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: context.c.muted),
            const SizedBox(height: VerbalTokens.md),
            Text(title, style: context.t.titleMedium),
            const SizedBox(height: VerbalTokens.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: context.t.bodySmall,
            ),
            if (action != null) ...[
              const SizedBox(height: VerbalTokens.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard page padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
          VerbalTokens.lg, VerbalTokens.sm, VerbalTokens.lg, VerbalTokens.xxl),
      children: children,
    );
  }
}
