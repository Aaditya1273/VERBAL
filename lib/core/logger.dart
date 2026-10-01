import 'dart:developer' as developer;

/// Minimal logger. Debug builds log; release builds stay silent.
///
/// Deliberately never accepts a secret or a raw transcript — conversation
/// content is sensitive and stays out of logs entirely.
///
/// Pure Dart on purpose. This used to import `package:flutter/foundation.dart`
/// for `kDebugMode`, which dragged Flutter into every file that logs — and so
/// into the command-line tools in `tool/`, which cannot provide `dart:ui`.
class Log {
  const Log._();

  /// True in debug and profile builds, false in release.
  ///
  /// Asserts are stripped from release builds, so the assignment never runs
  /// there. Same semantics as `kDebugMode`, without the dependency.
  static final bool _debug = () {
    var debug = false;
    assert(() {
      debug = true;
      return true;
    }());
    return debug;
  }();

  static void d(String message) => _emit(message, 0);

  static void w(String message) => _emit(message, 900);

  static void e(String message, [Object? error, StackTrace? stack]) {
    if (!_debug) return;
    developer.log(
      message,
      name: 'verbal',
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }

  static void _emit(String message, int level) {
    if (!_debug) return;
    developer.log(message, name: 'verbal', level: level);
  }
}
