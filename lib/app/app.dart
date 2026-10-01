import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/presence.dart';
import 'router.dart';
import 'theme.dart';

class VerbalApp extends ConsumerWidget {
  const VerbalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve onboarding state before the first redirect runs, otherwise the
    // router would briefly show Home to a first-time user.
    final onboarded = ref.watch(onboardedProvider);

    return MaterialApp.router(
      title: 'VERBAL',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // The lit ground is a night look; one theme, one product.
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => VerbalBackdrop(
        child: onboarded.isLoading
            ? const _Splash()
            : child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Presence(size: 96),
            const SizedBox(height: VerbalTokens.lg),
            Text('VERBAL', style: context.t.labelMedium),
          ],
        ),
      ),
    );
  }
}
