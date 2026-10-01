import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/difficulty.dart';
import '../features/analysis/analysis_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/playbook/playbook_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/scenarios/scenario_detail_screen.dart';
import '../features/scenarios/scenarios_screen.dart';
import 'providers.dart';
import 'shell.dart';

/// Whether onboarding has been completed. Drives the initial redirect.
final onboardedProvider = FutureProvider<bool>(
    (ref) => ref.watch(profileRepositoryProvider).hasOnboarded());

final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>();
  final shellKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = ref.read(onboardedProvider).valueOrNull;
      if (onboarded == null) return null; // still loading
      if (!onboarded && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      if (onboarded && state.matchedLocation == '/onboarding') return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) =>
            OnboardingScreen(onDone: () => context.go('/')),
      ),

      // Full-screen routes, outside the tab shell.
      GoRoute(
        path: '/practice/:scenarioId',
        parentNavigatorKey: rootKey,
        builder: (context, state) {
          final difficulty = Difficulty.values.firstWhere(
            (d) => d.name == state.uri.queryParameters['difficulty'],
            orElse: () => Difficulty.moderate,
          );
          return PracticeScreen(
            scenarioId: state.pathParameters['scenarioId']!,
            difficulty: difficulty,
            onFinished: (sessionId) =>
                context.pushReplacement('/analysis/$sessionId'),
          );
        },
      ),
      GoRoute(
        path: '/analysis/:sessionId',
        parentNavigatorKey: rootKey,
        builder: (context, state) => AnalysisScreen(
          sessionId: state.pathParameters['sessionId']!,
          onPractiseNext: (scenarioId, difficulty) => context.pushReplacement(
              '/practice/$scenarioId?difficulty=${difficulty.name}'),
          onDone: () => context.go('/'),
        ),
      ),
      GoRoute(
        path: '/paywall',
        parentNavigatorKey: rootKey,
        builder: (context, state) => PaywallScreen(
          onClose: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      GoRoute(
        path: '/scenarios/:scenarioId',
        parentNavigatorKey: rootKey,
        builder: (context, state) => ScenarioDetailScreen(
          scenarioId: state.pathParameters['scenarioId']!,
          onStart: (scenarioId, difficulty) => context
              .push('/practice/$scenarioId?difficulty=${difficulty.name}'),
          onUpgrade: () => context.push('/paywall'),
        ),
      ),

      // Tab shell.
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootKey,
        builder: (context, state, navigationShell) =>
            VerbalShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: shellKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => HomeScreen(
                  onPractise: (scenarioId, difficulty) => context.push(
                      '/practice/$scenarioId?difficulty=${difficulty.name}'),
                  onOpenPlaybook: () => context.go('/playbook'),
                  onOpenScenarios: () => context.go('/scenarios'),
                  onOpenPaywall: () => context.push('/paywall'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/scenarios',
                builder: (context, state) => ScenariosScreen(
                  onOpen: (id) => context.push('/scenarios/$id'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/playbook',
                builder: (context, state) => PlaybookScreen(
                  onPractise: () => context.go('/scenarios'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => ProfileScreen(
                  onPractise: () => context.go('/scenarios'),
                  onUpgrade: () => context.push('/paywall'),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
