/// A failure that the user can be shown and, usually, act on.
///
/// Every external system in VERBAL fails into one of these — nothing is
/// swallowed, and nothing reaches the UI as a raw exception string.
sealed class Failure implements Exception {
  const Failure(this.message, {this.cause});

  /// Plain, non-technical, and specific about what the user can do.
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkFailure extends Failure {
  const NetworkFailure({super.cause})
      : super('No connection. Your session is saved — reconnect and retry.');
}

class AiUnavailableFailure extends Failure {
  const AiUnavailableFailure({super.cause})
      : super(
            'The conversation engine is temporarily unavailable. Try again in a moment.');
}

class AiNotConfiguredFailure extends Failure {
  const AiNotConfiguredFailure()
      : super(
            'No AI key is configured, so VERBAL is running a scripted rehearsal.');
}

class VoiceFailure extends Failure {
  const VoiceFailure(super.message, {super.cause});

  static const recognitionUnavailable = VoiceFailure(
      'Speech recognition is not available on this device. You can type your turn instead.');

  static const synthesisFailed = VoiceFailure(
      'Could not play the reply out loud. You can still read it below.');
}

class MicrophonePermissionFailure extends Failure {
  const MicrophonePermissionFailure()
      : permanentlyDenied = false,
        super('VERBAL needs the microphone to hear your side of the '
            'conversation. Allow access when asked, or type your turn instead.');

  /// Denied for good — only Settings can re-enable it, so the UI must offer to
  /// open Settings rather than ask again (Android/iOS will not re-prompt).
  const MicrophonePermissionFailure.permanent()
      : permanentlyDenied = true,
        super('Microphone access is turned off for VERBAL. Open Settings > '
            'VERBAL > Microphone to turn it on, or type your turn instead.');

  final bool permanentlyDenied;
}

class StorageFailure extends Failure {
  const StorageFailure({super.cause})
      : super('Could not save to this device. Try again.');
}

class BillingFailure extends Failure {
  const BillingFailure(super.message, {super.cause});

  static const unavailable =
      BillingFailure('The store is unavailable right now. Try again shortly.');
  static const cancelled = BillingFailure('Purchase cancelled.');
}

class AnalysisFailure extends Failure {
  const AnalysisFailure({super.cause})
      : super(
            'We could not analyse that session. Your transcript is saved — you can retry.');
}
