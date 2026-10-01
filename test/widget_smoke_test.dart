import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/app/providers.dart';
import 'package:verbal/app/theme.dart';
import 'package:verbal/core/analytics.dart';
import 'package:verbal/core/billing.dart';
import 'package:verbal/core/config.dart';
import 'package:verbal/core/experiments.dart';
import 'package:verbal/data/local/memory_repositories.dart';
import 'package:verbal/data/remote/actor_service.dart';
import 'package:verbal/domain/analysis.dart';
import 'package:verbal/domain/playbook.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/features/home/home_screen.dart';
import 'package:verbal/features/onboarding/onboarding_screen.dart';
import 'package:verbal/features/paywall/paywall_screen.dart';
import 'package:verbal/features/playbook/playbook_screen.dart';
import 'package:verbal/features/scenarios/scenarios_screen.dart';

const _config = AppConfig(
  geminiApiKey: '',
  elevenLabsApiKey: '',
  elevenLabsVoiceId: 'v',
  revenueCatAndroidKey: '',
  revenueCatIosKey: '',
  oneSignalAppId: '',
);

PlaybookEntry _entry() => PlaybookEntry(
      id: 'p1',
      kind: PlaybookKind.framework,
      title: 'Acknowledge then hold',
      body:
          'I want to acknowledge what you said before I explain the decision.',
      whyItWorks: 'Acknowledges emotion without abandoning the objective.',
      skill: Skill.empathy,
      sourceScenarioId: 'termination',
      createdAt: DateTime(2026, 5, 1),
      timesUsed: 3,
    );

Widget host(
  Widget child, {
  MemoryPlaybookRepository? playbook,
  MemoryProfileRepository? profile,
}) {
  final sink = RecordingAnalyticsSink();
  return ProviderScope(
    overrides: [
      configProvider.overrideWithValue(_config),
      analyticsProvider.overrideWithValue(Analytics(sink)),
      sessionRepositoryProvider.overrideWithValue(MemorySessionRepository()),
      playbookRepositoryProvider
          .overrideWithValue(playbook ?? MemoryPlaybookRepository()),
      profileRepositoryProvider
          .overrideWithValue(profile ?? MemoryProfileRepository()),
      billingProvider.overrideWithValue(UnconfiguredBilling()),
      actorServiceProvider.overrideWithValue(const ScriptedActorService()),
      experimentServiceProvider
          .overrideWithValue(ExperimentService(Analytics(sink), userId: 'u')),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // The orb's idle animation never stops, so pumpAndSettle would hang.
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: c ?? const SizedBox.shrink(),
      ),
      home: child,
    ),
  );
}

void main() {
  testWidgets('onboarding asks one question and gates the button', (t) async {
    await t.pumpWidget(host(OnboardingScreen(onDone: () {})));
    await t.pumpAndSettle();

    expect(find.text('Practice difficult conversations before you have them.'),
        findsOneWidget);
    // The statement type is large now, so the question starts below the fold.
    await t.scrollUntilVisible(
        find.text('What do you want to get better at?'.toUpperCase()), 120);
    expect(find.text('What do you want to get better at?'.toUpperCase()),
        findsOneWidget);

    final button =
        find.widgetWithText(FilledButton, 'Choose your first conversation');
    expect(t.widget<FilledButton>(button).onPressed, isNull,
        reason: 'disabled until an interest is chosen');

    // The orb now sits above the options, so the choice can start below the fold.
    await t.ensureVisible(find.text('Managing people'));
    await t.pumpAndSettle();
    await t.tap(find.text('Managing people'));
    await t.pump();

    expect(t.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('home renders a real recommendation for a new user', (t) async {
    await t.pumpWidget(host(HomeScreen(
      onPractise: (_, __) {},
      onOpenPlaybook: () {},
      onOpenScenarios: () {},
      onOpenPaywall: () {},
    )));
    await t.pumpAndSettle();

    expect(find.text('Ready for your next conversation?'), findsOneWidget);
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Practise now'), findsOneWidget);
    // A first-time user has no progress, so nothing is fabricated.
    expect(find.text('YOUR PROGRESS'), findsNothing);
  });

  testWidgets('scenarios list shows every authored scenario', (t) async {
    await t.pumpWidget(host(ScenariosScreen(onOpen: (_) {})));
    await t.pumpAndSettle();

    // The list scrolls, so each title is scrolled into view rather than
    // assumed to be in the first viewport.
    for (final scenario in ScenarioLibrary.all) {
      final title = find.text(scenario.title);
      await t.scrollUntilVisible(title, 200,
          scrollable: find.byType(Scrollable).first);
      expect(title, findsOneWidget, reason: scenario.id);
    }
  });

  testWidgets('Pro scenarios are locked without an entitlement', (t) async {
    await t.pumpWidget(host(ScenariosScreen(onOpen: (_) {})));
    await t.pumpAndSettle();

    final proCount = ScenarioLibrary.all.where((s) => s.isPro).length;
    expect(proCount, greaterThan(0), reason: 'the library must gate something');

    var locks = 0;
    for (final scenario in ScenarioLibrary.all) {
      await t.scrollUntilVisible(find.text(scenario.title), 200,
          scrollable: find.byType(Scrollable).first);
      if (scenario.isPro &&
          find.byIcon(Icons.lock_outline).evaluate().isNotEmpty) {
        locks++;
      }
    }
    expect(locks, proCount);
  });

  testWidgets('an empty playbook explains what will fill it', (t) async {
    await t.pumpWidget(host(PlaybookScreen(onPractise: () {})));
    await t.pumpAndSettle();

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start a conversation'),
        findsOneWidget);
  });

  testWidgets('a saved playbook entry shows its reuse count', (t) async {
    final repo = MemoryPlaybookRepository();
    await repo.add(_entry());

    await t.pumpWidget(host(PlaybookScreen(onPractise: () {}), playbook: repo));
    await t.pumpAndSettle();

    expect(find.textContaining('acknowledge what you said'), findsOneWidget);
    expect(find.text('Used in 3 sessions'), findsOneWidget);
    expect(find.text('Framework'), findsOneWidget);
  });

  testWidgets('the paywall is honest when no store products exist', (t) async {
    await t.pumpWidget(host(PaywallScreen(onClose: () {})));
    await t.pumpAndSettle();

    expect(find.text('Practise until it is automatic.'), findsOneWidget);
    expect(find.text('Purchasing is not available in this build.'),
        findsOneWidget);
    // No fabricated prices anywhere on the screen.
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('both themes build without overflow', (t) async {
    for (final brightness in Brightness.values) {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWithValue(_config),
            analyticsProvider
                .overrideWithValue(Analytics(RecordingAnalyticsSink())),
            sessionRepositoryProvider
                .overrideWithValue(MemorySessionRepository()),
            playbookRepositoryProvider
                .overrideWithValue(MemoryPlaybookRepository()),
            profileRepositoryProvider
                .overrideWithValue(MemoryProfileRepository()),
            billingProvider.overrideWithValue(UnconfiguredBilling()),
            actorServiceProvider
                .overrideWithValue(const ScriptedActorService()),
            experimentServiceProvider.overrideWithValue(ExperimentService(
                Analytics(RecordingAnalyticsSink()),
                userId: 'u')),
          ],
          child: MaterialApp(
            theme: buildTheme(brightness),
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: c ?? const SizedBox.shrink(),
            ),
            home: ScenariosScreen(onOpen: (_) {}),
          ),
        ),
      );
      await t.pumpAndSettle();

      // pumpAndSettle surfaces layout overflows as exceptions; takeException
      // returns null only if the frame rendered cleanly.
      expect(t.takeException(), isNull, reason: brightness.name);

      final first = find.text(ScenarioLibrary.all.first.title);
      expect(first, findsOneWidget, reason: brightness.name);

      // The theme extension must resolve, or every colour call would throw.
      expect(t.element(first).c.accent, isNotNull, reason: brightness.name);
    }
  });
}
