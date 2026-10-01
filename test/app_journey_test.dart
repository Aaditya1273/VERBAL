import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/app/app.dart';
import 'package:verbal/app/providers.dart';
import 'package:verbal/core/analytics.dart';
import 'package:verbal/core/billing.dart';
import 'package:verbal/core/config.dart';
import 'package:verbal/core/experiments.dart';
import 'package:verbal/data/local/memory_repositories.dart';
import 'package:verbal/data/remote/actor_service.dart';
import 'package:verbal/data/repositories.dart';
import 'package:verbal/domain/conversation_engine.dart';
import 'package:verbal/domain/scenario.dart';
import 'package:verbal/domain/scenario_library.dart';
import 'package:verbal/domain/session.dart';

import 'practice_loop_test.dart' show FakeRecognizer, RecordingVoice;

/// Drives the real [VerbalApp] — real router, real screens, real providers —
/// through the whole product loop.
///
/// This is the closest thing to a device run available without an emulator. It
/// exercises navigation, redirects, provider invalidation and persistence for
/// real, and catches broken routes or stale caches that unit tests cannot.

const _config = AppConfig(
  geminiApiKey: '',
  elevenLabsApiKey: '',
  elevenLabsVoiceId: 'v',
  revenueCatAndroidKey: '',
  revenueCatIosKey: '',
  oneSignalAppId: '',
);

const _analysisJson = '''
{"summary":"You named the problem and held it.","objectiveMet":true,
 "scores":[{"skill":"clarity","score":81,"note":"You named the missed deadline."},
           {"skill":"empathy","score":58,"note":"You moved past her reaction."}],
 "worked":[{"quote":"The deadline slipped four days.","why":"Concrete."}],
 "weakened":[{"quote":"It is not a big deal.","why":"Undercut the message."}],
 "betterAlternative":{"quote":"This is a performance concern.","why":"States the stakes."},
 "nextSkill":"empathy",
 "playbookCandidates":[{"kind":"winningLine","title":"Name the gap",
   "body":"The deadline slipped by four days.","whyItWorks":"Specific and checkable.",
   "skill":"specificity"}]}
''';

/// An actor that always answers, so the journey runs to completion.
class JourneyActor implements ActorService {
  int replies = 0;

  @override
  Future<ActorReply> respond({
    required Scenario scenario,
    required TurnDirective directive,
    required List<Turn> history,
    required String systemPrompt,
  }) async {
    replies++;
    return const ActorReply(
      text: 'You never told me this was serious.',
      signal: TurnSignal(),
    );
  }

  @override
  Future<String> analyse(String prompt) async => _analysisJson;
}

Widget buildApp({ProfileRepository? profile, RecordingAnalyticsSink? sink}) {
  final analytics = Analytics(sink ?? RecordingAnalyticsSink());

  return ProviderScope(
    overrides: [
      configProvider.overrideWithValue(_config),
      analyticsProvider.overrideWithValue(analytics),
      sessionRepositoryProvider.overrideWithValue(MemorySessionRepository()),
      playbookRepositoryProvider.overrideWithValue(MemoryPlaybookRepository()),
      profileRepositoryProvider
          .overrideWithValue(profile ?? MemoryProfileRepository()),
      billingProvider.overrideWithValue(UnconfiguredBilling()),
      actorServiceProvider.overrideWithValue(JourneyActor()),
      speechRecognizerProvider.overrideWithValue(FakeRecognizer()),
      voiceSynthesizerProvider.overrideWithValue(RecordingVoice()),
      experimentServiceProvider
          .overrideWithValue(ExperimentService(analytics, userId: 'u')),
    ],
    child: const _NoAnimations(child: VerbalApp()),
  );
}

/// The orb's idle animation never stops, so `pumpAndSettle` would hang. Disabling
/// animations is the same path the system's reduce-motion setting takes, and
/// the widget honours it.
class _NoAnimations extends StatelessWidget {
  const _NoAnimations({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child,
      );
}

/// Run the journey at a real phone size (360x780 logical, 3x) rather than the
/// 800x600 test default, so layout and scrolling behave the way they will on a
/// device.
void usePhoneViewport(WidgetTester t) {
  t.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
}

/// Scroll a widget into view inside the nearest scrollable, then tap it.
/// Falls back to a plain tap when the screen does not scroll.
Future<void> scrollAndTap(WidgetTester t, Finder target) async {
  // Scroll the enclosing list until the target exists, then make sure it is
  // actually on screen before tapping it.
  for (var i = 0; i < 25 && target.evaluate().isEmpty; i++) {
    final scrollables = find.byType(Scrollable).evaluate();
    if (scrollables.isEmpty) break;
    await t.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await t.pumpAndSettle();
  }

  expect(target, findsWidgets,
      reason: 'could not scroll the target into existence');

  if (find.byType(Scrollable).evaluate().isNotEmpty) {
    await t.ensureVisible(target.first);
    await t.pumpAndSettle();
  }
  await t.tap(target.first);
  await t.pumpAndSettle();
}

Future<MemoryProfileRepository> onboarded(String interest) async {
  final profile = MemoryProfileRepository();
  await profile.completeOnboarding(interest);
  return profile;
}

/// Type a turn through the practice screen's keyboard fallback.
Future<void> speak(WidgetTester t, String text) async {
  await t.tap(find.byIcon(Icons.keyboard_outlined));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField), text);
  await t.tap(find.widgetWithText(FilledButton, 'Say it'));
  await t.pumpAndSettle();
}

Future<void> endSession(WidgetTester t) async {
  await t.tap(find.widgetWithText(TextButton, 'End'));
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton, 'End and analyse'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a first-time user lands in onboarding, not the app', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp());
    await t.pumpAndSettle();

    expect(find.text('Practice difficult conversations before you have them.'),
        findsOneWidget);
    // The tab bar must not be reachable before onboarding completes.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('completing onboarding routes into the app shell', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp());
    await t.pumpAndSettle();

    await scrollAndTap(t, find.text('Giving feedback'));
    await t.tap(find.text('Choose your first conversation'));
    await t.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Ready for your next conversation?'), findsOneWidget);
  });

  testWidgets('a returning user skips onboarding entirely', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp(profile: await onboarded('managing')));
    await t.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Choose your first conversation'), findsNothing);
  });

  testWidgets('every tab opens without error', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp(profile: await onboarded('managing')));
    await t.pumpAndSettle();

    for (final tab in ['Scenarios', 'Playbook', 'You']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: tab);
    }

    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('Ready for your next conversation?'), findsOneWidget);
  });

  testWidgets('the full loop: brief, practice, analysis, playbook', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp(profile: await onboarded('feedback')));
    await t.pumpAndSettle();

    await t.tap(find.text('Scenarios'));
    await t.pumpAndSettle();
    await t.tap(find.text(ScenarioLibrary.difficultFeedback.title));
    await t.pumpAndSettle();

    // The brief is shown before any practice begins.
    expect(find.text('THE SITUATION'), findsOneWidget);

    await scrollAndTap(
        t, find.widgetWithText(FilledButton, 'Start the conversation'));

    // The practice cockpit is live and the actor has opened.
    expect(find.text('HOLD TO SPEAK'), findsOneWidget);
    expect(find.textContaining('you wanted to talk'), findsOneWidget);

    await speak(t, 'Two deadlines slipped last month.');
    expect(
        find.textContaining('never told me this was serious'), findsOneWidget);

    await endSession(t);

    expect(find.text('Session review'), findsOneWidget);
    expect(find.text('81'), findsOneWidget, reason: 'clarity score rendered');

    await scrollAndTap(
        t, find.widgetWithText(OutlinedButton, 'Save to Playbook'));
    expect(find.text('In your Playbook'), findsOneWidget);

    await t.tap(find.widgetWithText(TextButton, 'Done'));
    await t.pumpAndSettle();
    await t.tap(find.text('Playbook'));
    await t.pumpAndSettle();

    expect(find.textContaining('slipped by four days'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a finished session shows up in progress', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp(profile: await onboarded('feedback')));
    await t.pumpAndSettle();

    // The mascot sits above the headline, so the button can start below
    // the fold on a phone.
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Practise now'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Practise now'));
    await t.pumpAndSettle();

    await speak(t, 'This is a performance concern.');
    await endSession(t);
    await t.tap(find.widgetWithText(TextButton, 'Done'));
    await t.pumpAndSettle();

    await t.tap(find.text('You'));
    await t.pumpAndSettle();

    expect(find.text('CONFIDENCE'), findsOneWidget);
    expect(find.text('SKILLS'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the paywall is reachable and dismissible', (t) async {
    usePhoneViewport(t);
    await t.pumpWidget(buildApp(profile: await onboarded('managing')));
    await t.pumpAndSettle();

    await t.tap(find.text('You'));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('Free'));
    await t.pumpAndSettle();

    expect(find.text('VERBAL PRO'), findsOneWidget);

    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();

    expect(find.text('VERBAL PRO'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
