/// Runtime configuration.
///
/// Every secret arrives via `--dart-define` (or a `--dart-define-from-file`
/// JSON) and is never committed. Nothing here has a real default: a missing key
/// disables its feature rather than silently shipping someone else's credentials.
///
/// See `.env.example` and the README for the full list.
class AppConfig {
  const AppConfig({
    required this.geminiApiKey,
    required this.elevenLabsApiKey,
    required this.elevenLabsVoiceId,
    required this.revenueCatAndroidKey,
    required this.revenueCatIosKey,
    required this.oneSignalAppId,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
        geminiApiKey: String.fromEnvironment('GEMINI_API_KEY'),
        elevenLabsApiKey: String.fromEnvironment('ELEVENLABS_API_KEY'),
        elevenLabsVoiceId: String.fromEnvironment(
          'ELEVENLABS_VOICE_ID',
          defaultValue: '21m00Tcm4TlvDq8ikWAM',
        ),
        revenueCatAndroidKey: String.fromEnvironment('REVENUECAT_ANDROID_KEY'),
        revenueCatIosKey: String.fromEnvironment('REVENUECAT_IOS_KEY'),
        oneSignalAppId: String.fromEnvironment('ONESIGNAL_APP_ID'),
      );

  final String geminiApiKey;
  final String elevenLabsApiKey;
  final String elevenLabsVoiceId;
  final String revenueCatAndroidKey;
  final String revenueCatIosKey;
  final String oneSignalAppId;

  /// Without this the AI actor cannot run and the app falls back to a scripted
  /// rehearsal so the product is still usable.
  bool get hasAi => geminiApiKey.isNotEmpty;

  /// Without this the actor speaks through the device's built-in voice.
  bool get hasPremiumVoice => elevenLabsApiKey.isNotEmpty;

  bool get hasBilling =>
      revenueCatAndroidKey.isNotEmpty || revenueCatIosKey.isNotEmpty;

  bool get hasPush => oneSignalAppId.isNotEmpty;

  /// RevenueCat's Test Store runs real-shaped purchases with no App Store or
  /// Play Console account — the only way to exercise billing without a paid
  /// developer account.
  static const testStoreKeyPrefix = 'test_';

  static bool isTestStoreKey(String key) => key.startsWith(testStoreKeyPrefix);

  /// True when billing is pointed at the Test Store rather than a real store.
  ///
  /// Matters at release: RevenueCat crashes a release build configured with a
  /// Test Store key, so the app refuses to configure instead.
  bool get usesTestStore =>
      (revenueCatAndroidKey.isNotEmpty &&
          isTestStoreKey(revenueCatAndroidKey)) ||
      (revenueCatIosKey.isNotEmpty && isTestStoreKey(revenueCatIosKey));

  /// Safe to log: says what is configured without revealing any value.
  Map<String, bool> get diagnostics => {
        'ai': hasAi,
        'premiumVoice': hasPremiumVoice,
        'billing': hasBilling,
        'testStore': usesTestStore,
        'push': hasPush,
      };
}
