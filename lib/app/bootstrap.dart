import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../core/analytics.dart';
import '../core/billing.dart';
import '../core/config.dart';
import '../core/experiments.dart';
import '../core/logger.dart';
import '../data/local/database.dart';
import '../data/local/memory_repositories.dart';
import '../data/remote/actor_service.dart';
import '../data/repositories.dart';
import 'providers.dart';

/// Wires up the app and returns the overrides the widget tree needs.
///
/// Anything that can fail on a real device — the database, the store SDK — is
/// caught here and degraded, so a broken dependency never blocks launch.
Future<List<Override>> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  Log.d('config: ${config.diagnostics}');

  final analytics = Analytics(const DebugAnalyticsSink());

  // --- persistence -----------------------------------------------------
  SessionRepository sessions;
  PlaybookRepository playbook;
  ProfileRepository profile;

  Database? db;
  try {
    db = await VerbalDatabase.open();
    sessions = SqliteSessionRepository(db);
    playbook = SqlitePlaybookRepository(db);
  } on Object catch (e, s) {
    Log.e('database unavailable; running in memory for this session', e, s);
    sessions = MemorySessionRepository();
    playbook = MemoryPlaybookRepository();
  }

  try {
    profile = PrefsProfileRepository(await SharedPreferences.getInstance());
  } on Object catch (e, s) {
    Log.e('preferences unavailable; running in memory', e, s);
    profile = MemoryProfileRepository();
  }

  final userId = await profile.userId();

  // --- billing ---------------------------------------------------------
  final BillingService billing = config.hasBilling
      ? RevenueCatBilling(config: config, analytics: analytics)
      : UnconfiguredBilling();
  await billing.init();
  await billing.identify(userId);

  // --- AI --------------------------------------------------------------
  // No key means a scripted rehearsal rather than a dead app.
  final actor = config.hasAi
      ? GeminiActorService(config: config)
      : const ScriptedActorService();

  analytics.track(AnalyticsEvent.appOpened, config.diagnostics);

  return [
    configProvider.overrideWithValue(config),
    analyticsProvider.overrideWithValue(analytics),
    sessionRepositoryProvider.overrideWithValue(sessions),
    playbookRepositoryProvider.overrideWithValue(playbook),
    profileRepositoryProvider.overrideWithValue(profile),
    billingProvider.overrideWithValue(billing),
    actorServiceProvider.overrideWithValue(actor),
    experimentServiceProvider
        .overrideWithValue(ExperimentService(analytics, userId: userId)),
  ];
}
