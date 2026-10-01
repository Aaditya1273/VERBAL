import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/app/providers.dart';
import 'package:verbal/core/config.dart';
import 'package:verbal/core/billing.dart';
import 'package:verbal/core/failures.dart';

void main() {
  group('Entitlement', () {
    test('free is not pro', () {
      expect(Entitlement.free.isPro, isFalse);
      expect(Entitlement.free.isTrial, isFalse);
      expect(Entitlement.free.productId, isNull);
    });
  });

  group('UnconfiguredBilling', () {
    test('reports free access without crashing', () async {
      final billing = UnconfiguredBilling();
      addTearDown(billing.dispose);

      await billing.init();
      await billing.identify('u1');

      expect(billing.hasProAccess, isFalse);
      expect(billing.current.isPro, isFalse);
      expect(await billing.offerings(), isEmpty);
    });

    test('purchasing surfaces a Failure rather than throwing raw errors',
        () async {
      final billing = UnconfiguredBilling();
      addTearDown(billing.dispose);

      await expectLater(
          billing.purchase('monthly'), throwsA(isA<BillingFailure>()));
      await expectLater(billing.restore(), throwsA(isA<BillingFailure>()));
    });
  });

  group('PracticeAllowance', () {
    test('free users are limited', () {
      const a = PracticeAllowance(used: 3, limit: 3, isPro: false);
      expect(a.canPractise, isFalse);
      expect(a.remaining, 0);
    });

    test('free users under the limit can practise', () {
      const a = PracticeAllowance(used: 1, limit: 3, isPro: false);
      expect(a.canPractise, isTrue);
      expect(a.remaining, 2);
    });

    test('pro is never limited, even past the free count', () {
      const a = PracticeAllowance(used: 99, limit: 3, isPro: true);
      expect(a.canPractise, isTrue);
    });

    test('remaining never goes negative', () {
      const a = PracticeAllowance(used: 10, limit: 3, isPro: false);
      expect(a.remaining, 0);
    });
  });

  group('the gate the UI actually reads', () {
    test('hasProProvider is false without an entitlement', () {
      final container = ProviderContainer(overrides: [
        billingProvider.overrideWithValue(UnconfiguredBilling()),
      ]);
      addTearDown(container.dispose);

      expect(container.read(hasProProvider), isFalse);
    });

    test('hasProProvider follows the entitlement stream', () async {
      final billing = FakeBilling();
      final container = ProviderContainer(overrides: [
        billingProvider.overrideWithValue(billing),
      ]);
      addTearDown(() {
        container.dispose();
        billing.dispose();
      });

      // Subscribe so the stream provider is live.
      container.listen(entitlementProvider, (_, __) {}, fireImmediately: true);
      expect(container.read(hasProProvider), isFalse);

      billing.emit(const Entitlement(isPro: true, productId: 'annual'));
      await container.read(entitlementProvider.future);

      expect(container.read(hasProProvider), isTrue);
    });

    test('losing the entitlement closes the gate again', () async {
      final billing = FakeBilling()..emit(const Entitlement(isPro: true));
      final container = ProviderContainer(overrides: [
        billingProvider.overrideWithValue(billing),
      ]);
      addTearDown(() {
        container.dispose();
        billing.dispose();
      });

      container.listen(entitlementProvider, (_, __) {}, fireImmediately: true);
      billing.emit(Entitlement.free);
      await container.read(entitlementProvider.future);

      expect(container.read(hasProProvider), isFalse);
    });

    test('allowance is unlimited for Pro and limited otherwise', () {
      const pro = PracticeAllowance(used: 50, limit: 3, isPro: true);
      const free = PracticeAllowance(used: 3, limit: 3, isPro: false);

      expect(pro.canPractise, isTrue);
      expect(pro.remaining, -1, reason: 'unlimited is signalled, not counted');
      expect(free.canPractise, isFalse);
    });
  });

  group('Test Store keys', () {
    const testStore = AppConfig(
      geminiApiKey: '',
      elevenLabsApiKey: '',
      elevenLabsVoiceId: '',
      revenueCatAndroidKey: 'test_abc123',
      revenueCatIosKey: '',
      oneSignalAppId: '',
    );
    const production = AppConfig(
      geminiApiKey: '',
      elevenLabsApiKey: '',
      elevenLabsVoiceId: '',
      revenueCatAndroidKey: 'goog_abc123',
      revenueCatIosKey: 'appl_abc123',
      oneSignalAppId: '',
    );

    test('a Test Store key still counts as billing being configured', () {
      // Without a paid developer account this is the only way to exercise
      // purchases at all, so it must not be treated as "no billing".
      expect(testStore.hasBilling, isTrue);
      expect(testStore.usesTestStore, isTrue);
    });

    test('production keys are not mistaken for test keys', () {
      expect(production.usesTestStore, isFalse);
      expect(AppConfig.isTestStoreKey('goog_abc'), isFalse);
      expect(AppConfig.isTestStoreKey('appl_abc'), isFalse);
      expect(AppConfig.isTestStoreKey('test_abc'), isTrue);
    });

    test('diagnostics report the store without leaking the key', () {
      final d = testStore.diagnostics;
      expect(d['billing'], isTrue);
      expect(d['testStore'], isTrue);
      expect(d.values.whereType<String>(), isEmpty,
          reason: 'diagnostics must never carry a key value');
    });

    test('an empty key is neither billing nor test store', () {
      const none = AppConfig(
        geminiApiKey: '',
        elevenLabsApiKey: '',
        elevenLabsVoiceId: '',
        revenueCatAndroidKey: '',
        revenueCatIosKey: '',
        oneSignalAppId: '',
      );
      expect(none.hasBilling, isFalse);
      expect(none.usesTestStore, isFalse);
    });
  });
}

/// A billing service the test drives directly. Nothing here fakes a purchase
/// succeeding — it only models entitlement arriving from the store.
class FakeBilling implements BillingService {
  final _controller = StreamController<Entitlement>.broadcast();
  Entitlement _current = Entitlement.free;

  void emit(Entitlement e) {
    _current = e;
    _controller.add(e);
  }

  @override
  Stream<Entitlement> get entitlements => _controller.stream;

  @override
  Entitlement get current => _current;

  @override
  bool get hasProAccess => _current.isPro;

  @override
  Future<void> init() async {}

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<List<Plan>> offerings() async => const [];

  @override
  Future<Entitlement> purchase(String planId) async =>
      throw BillingFailure.unavailable;

  @override
  Future<Entitlement> restore() async => _current;

  @override
  Future<void> dispose() async => _controller.close();
}
