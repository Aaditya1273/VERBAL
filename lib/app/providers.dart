import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../core/billing.dart';
import '../core/config.dart';
import '../core/experiments.dart';
import '../core/voice.dart';
import '../data/local/memory_repositories.dart';
import '../data/remote/actor_service.dart';
import '../data/repositories.dart';
import '../domain/playbook.dart';
import '../domain/progress.dart';
import '../domain/recommendation.dart';
import '../domain/scenario.dart';
import '../domain/scenario_library.dart';
import '../domain/session.dart';

/// Providers that must be overridden in [bootstrap] before the app runs.
/// Throwing here means a missing override fails loudly at startup rather than
/// silently using a stub in production.
Never _mustOverride(String name) =>
    throw StateError('$name was not overridden in bootstrap()');

final configProvider = Provider<AppConfig>((ref) => _mustOverride('config'));

final analyticsProvider =
    Provider<Analytics>((ref) => _mustOverride('analytics'));

final sessionRepositoryProvider =
    Provider<SessionRepository>((ref) => MemorySessionRepository());

final playbookRepositoryProvider =
    Provider<PlaybookRepository>((ref) => MemoryPlaybookRepository());

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => MemoryProfileRepository());

final billingProvider =
    Provider<BillingService>((ref) => _mustOverride('billing'));

final actorServiceProvider =
    Provider<ActorService>((ref) => _mustOverride('actorService'));

final speechRecognizerProvider = Provider<SpeechRecognizer>((ref) {
  final recognizer = DeviceSpeechRecognizer();
  ref.onDispose(recognizer.dispose);
  return recognizer;
});

/// Picks the best voice this configuration can actually produce.
///
/// ElevenLabs first when configured, then Gemini TTS — which needs no second
/// account, because the actor's key already works for speech — and the device
/// voice underneath both. Each layer falls through to the next at runtime, so a
/// provider being blocked costs quality and nothing else.
final voiceSynthesizerProvider = Provider<VoiceSynthesizer>((ref) {
  final config = ref.watch(configProvider);

  // Built inside out, so each layer falls through to the next at runtime
  // rather than dead-ending. A blocked ElevenLabs account lands on Gemini,
  // not on the device's robotic voice.
  VoiceSynthesizer synth = DeviceVoice();

  if (config.hasAi) {
    synth = NetworkVoice.gemini(config: config, fallback: synth);
  }
  if (config.hasPremiumVoice) {
    synth = NetworkVoice.elevenLabs(config: config, fallback: synth);
  }

  ref.onDispose(synth.dispose);
  return synth;
});

final experimentServiceProvider =
    Provider<ExperimentService>((ref) => _mustOverride('experiments'));

/// The scenario catalogue. Authored content, read directly.
final scenariosProvider =
    Provider<List<Scenario>>((ref) => ScenarioLibrary.all);

/// Live entitlement, so every Pro gate reads from one place.
final entitlementProvider = StreamProvider<Entitlement>((ref) {
  final billing = ref.watch(billingProvider);
  return billing.entitlements;
});

final hasProProvider = Provider<bool>((ref) {
  final billing = ref.watch(billingProvider);
  return ref.watch(entitlementProvider).maybeWhen(
        data: (e) => e.isPro,
        orElse: () => billing.current.isPro,
      );
});

// ---------------------------------------------------------------------------
// Derived product state
// ---------------------------------------------------------------------------

final sessionsProvider = FutureProvider<List<PracticeSession>>(
    (ref) => ref.watch(sessionRepositoryProvider).all());

final playbookProvider = FutureProvider<List<PlaybookEntry>>(
    (ref) => ref.watch(playbookRepositoryProvider).all());

final profileProvider = FutureProvider<CommunicationProfile>((ref) async {
  final sessions = await ref.watch(sessionsProvider.future);
  return ProgressCalculator.build(sessions);
});

final interestProvider = FutureProvider<String?>(
    (ref) => ref.watch(profileRepositoryProvider).interest());

/// What the user should practise next, and why.
final nextPracticeProvider = FutureProvider<NextPractice>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final sessions = await ref.watch(sessionsProvider.future);
  final interest = await ref.watch(interestProvider.future);

  return Recommender.next(
    profile: profile,
    history: sessions,
    library: ref.watch(scenariosProvider),
    interest: interest,
  );
});

/// Free-tier budget for the current week.
final allowanceProvider = FutureProvider<PracticeAllowance>((ref) async {
  final used = await ref.watch(profileRepositoryProvider).sessionsThisWeek();
  return PracticeAllowance(
    used: used,
    limit: PracticeAllowance.freeSessionsPerWeek,
    isPro: ref.watch(hasProProvider),
  );
});

/// Playbook entries worth surfacing before a given scenario.
final relevantPlaybookProvider =
    FutureProvider.family<List<PlaybookEntry>, String>((ref, scenarioId) async {
  final scenario = ScenarioLibrary.byId(scenarioId);
  if (scenario == null) return const [];
  final entries = await ref.watch(playbookProvider.future);
  return PlaybookMatcher.relevantFor(scenario, entries);
});

/// Refreshes everything derived from stored data after a session or a save.
void invalidateUserData(WidgetRef ref) {
  ref
    ..invalidate(sessionsProvider)
    ..invalidate(playbookProvider)
    ..invalidate(profileProvider)
    ..invalidate(nextPracticeProvider)
    ..invalidate(allowanceProvider);
}
