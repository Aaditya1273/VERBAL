import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'analytics.dart';
import 'config.dart';
import 'failures.dart';
import 'logger.dart';

/// The entitlement identifier configured in the RevenueCat dashboard.
const kProEntitlement = 'pro';

/// What the app is allowed to do, as far as the store is concerned.
class Entitlement {
  const Entitlement({
    required this.isPro,
    this.productId,
    this.expiresAt,
    this.willRenew = false,
    this.isTrial = false,
  });

  final bool isPro;
  final String? productId;
  final DateTime? expiresAt;
  final bool willRenew;
  final bool isTrial;

  static const free = Entitlement(isPro: false);

  factory Entitlement.fromCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active[kProEntitlement];
    if (active == null) return free;
    return Entitlement(
      isPro: true,
      productId: active.productIdentifier,
      expiresAt: DateTime.tryParse(active.expirationDate ?? ''),
      willRenew: active.willRenew,
      isTrial: active.periodType == PeriodType.trial,
    );
  }
}

/// A purchasable plan, flattened so the UI never touches RevenueCat types.
class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.priceString,
    required this.period,
    this.isAnnual = false,
    this.trialDays,
  });

  final String id;
  final String title;
  final String priceString;
  final String period;
  final bool isAnnual;
  final int? trialDays;
}

/// The app's only view of purchasing.
///
/// The UI asks `hasProAccess` — it never imports RevenueCat. That keeps the
/// store SDK in one file and makes the free/unconfigured path a first-class
/// implementation rather than a special case.
abstract class BillingService {
  /// Current entitlement, updated as the store reports changes.
  Stream<Entitlement> get entitlements;

  Entitlement get current;

  bool get hasProAccess => current.isPro;

  Future<void> init();

  /// Associate purchases with the signed-in user.
  Future<void> identify(String userId);

  Future<List<Plan>> offerings();

  /// Throws a [BillingFailure] on failure; never crashes the app.
  Future<Entitlement> purchase(String planId);

  Future<Entitlement> restore();

  Future<void> dispose();
}

/// RevenueCat-backed implementation.
class RevenueCatBilling implements BillingService {
  RevenueCatBilling({required this.config, required Analytics analytics})
      : _analytics = analytics;

  final AppConfig config;
  final Analytics _analytics;

  final _controller = StreamController<Entitlement>.broadcast();
  Entitlement _current = Entitlement.free;
  List<Package> _packages = const [];
  bool _ready = false;

  @override
  Stream<Entitlement> get entitlements => _controller.stream;

  @override
  Entitlement get current => _current;

  @override
  bool get hasProAccess => _current.isPro;

  @override
  Future<void> init() async {
    final key = _apiKey();
    if (key.isEmpty) {
      Log.w('RevenueCat key missing; billing runs in unconfigured mode.');
      return;
    }

    // RevenueCat deliberately CRASHES a release build that configures with a
    // Test Store key, to stop test purchases leaking into production. Crashing
    // on launch is the worst possible outcome for the user, so refuse to
    // configure and fall back to the free tier instead.
    if (kReleaseMode && AppConfig.isTestStoreKey(key)) {
      Log.w('Refusing a Test Store key in a release build — billing disabled. '
          'Ship a goog_/appl_ key to enable purchases.');
      return;
    }

    try {
      await Purchases.setLogLevel(LogLevel.error);
      await Purchases.configure(PurchasesConfiguration(key));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _onCustomerInfo(await Purchases.getCustomerInfo());
      _ready = true;
    } on Object catch (e, s) {
      // A store outage must never take the app down with it.
      Log.e('RevenueCat init failed', e, s);
    }
  }

  String _apiKey() {
    // Chosen at runtime so one build can target either store.
    return defaultTargetPlatform == TargetPlatform.iOS
        ? config.revenueCatIosKey
        : config.revenueCatAndroidKey;
  }

  void _onCustomerInfo(CustomerInfo info) {
    _current = Entitlement.fromCustomerInfo(info);
    _controller.add(_current);
  }

  @override
  Future<void> identify(String userId) async {
    if (!_ready) return;
    try {
      final result = await Purchases.logIn(userId);
      _onCustomerInfo(result.customerInfo);
    } on Object catch (e, s) {
      Log.e('RevenueCat identify failed', e, s);
    }
  }

  @override
  Future<List<Plan>> offerings() async {
    if (!_ready) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return const [];

      _packages = current.availablePackages;
      return _packages.map(_toPlan).toList();
    } on Object catch (e, s) {
      Log.e('Fetching offerings failed', e, s);
      throw BillingFailure.unavailable;
    }
  }

  Plan _toPlan(Package p) {
    final product = p.storeProduct;
    final isAnnual = p.packageType == PackageType.annual;
    return Plan(
      id: p.identifier,
      title: product.title,
      priceString: product.priceString,
      period: _periodLabel(p.packageType),
      isAnnual: isAnnual,
      trialDays: _trialDays(product),
    );
  }

  /// A lifetime package is not "per month". Offerings routinely contain
  /// lifetime and weekly packages, and mislabelling the period on a paywall is
  /// the kind of thing that gets a store listing rejected.
  static String _periodLabel(PackageType type) => switch (type) {
        PackageType.annual => 'per year',
        PackageType.sixMonth => 'per six months',
        PackageType.threeMonth => 'per quarter',
        PackageType.twoMonth => 'per two months',
        PackageType.monthly => 'per month',
        PackageType.weekly => 'per week',
        PackageType.lifetime => 'one-off',
        _ => '',
      };

  int? _trialDays(StoreProduct product) {
    final period = product.introductoryPrice?.periodNumberOfUnits;
    final unit = product.introductoryPrice?.periodUnit;
    if (period == null || unit == null) return null;
    return switch (unit) {
      PeriodUnit.day => period,
      PeriodUnit.week => period * 7,
      PeriodUnit.month => period * 30,
      PeriodUnit.year => period * 365,
      PeriodUnit.unknown => null,
    };
  }

  @override
  Future<Entitlement> purchase(String planId) async {
    if (!_ready) throw BillingFailure.unavailable;

    Package? package;
    for (final p in _packages) {
      if (p.identifier == planId) package = p;
    }
    if (package == null) throw BillingFailure.unavailable;

    _analytics.track(AnalyticsEvent.purchaseStarted, {'plan': planId});

    try {
      _onCustomerInfo(await Purchases.purchasePackage(package));
      _analytics.track(AnalyticsEvent.purchaseCompleted, {
        'plan': planId,
        'trial': _current.isTrial,
      });
      return _current;
    } on PlatformException catch (e, s) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        _analytics
            .track(AnalyticsEvent.purchaseFailed, {'reason': 'cancelled'});
        throw BillingFailure.cancelled;
      }
      Log.e('Purchase failed', e, s);
      _analytics.track(AnalyticsEvent.purchaseFailed, {'reason': code.name});
      throw BillingFailure(
          'That purchase did not go through. ${e.message ?? ''}'.trim());
    } on Object catch (e, s) {
      Log.e('Purchase failed', e, s);
      _analytics.track(AnalyticsEvent.purchaseFailed, {'reason': 'unknown'});
      throw BillingFailure.unavailable;
    }
  }

  @override
  Future<Entitlement> restore() async {
    if (!_ready) throw BillingFailure.unavailable;
    try {
      _onCustomerInfo(await Purchases.restorePurchases());
      _analytics.track(AnalyticsEvent.restoreCompleted, {
        'restoredPro': _current.isPro,
      });
      return _current;
    } on Object catch (e, s) {
      Log.e('Restore failed', e, s);
      throw const BillingFailure('Could not restore purchases. Try again.');
    }
  }

  @override
  Future<void> dispose() async => _controller.close();
}

/// Used when no RevenueCat key is configured, and in tests.
///
/// Everything free-tier still works; Pro surfaces explain that purchasing is
/// unavailable rather than failing silently or pretending to succeed.
class UnconfiguredBilling implements BillingService {
  final _controller = StreamController<Entitlement>.broadcast();

  @override
  Stream<Entitlement> get entitlements => _controller.stream;

  @override
  Entitlement get current => Entitlement.free;

  @override
  bool get hasProAccess => false;

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
  Future<Entitlement> restore() async => throw BillingFailure.unavailable;

  @override
  Future<void> dispose() async => _controller.close();
}

/// Free-tier practice budget.
///
/// This is a product convenience, not a security boundary — a determined user
/// can reset it by reinstalling. Real entitlement always comes from the store
/// via [Entitlement], which is receipt-verified by RevenueCat.
class PracticeAllowance {
  const PracticeAllowance({
    required this.used,
    required this.limit,
    required this.isPro,
  });

  final int used;
  final int limit;
  final bool isPro;

  static const freeSessionsPerWeek = 3;

  bool get canPractise => isPro || used < limit;

  int get remaining => isPro ? -1 : (limit - used).clamp(0, limit);
}
