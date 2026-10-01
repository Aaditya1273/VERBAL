import '../domain/playbook.dart';
import '../domain/session.dart';

/// Practice sessions and their analysis.
abstract class SessionRepository {
  Future<List<PracticeSession>> all();
  Future<PracticeSession?> byId(String id);
  Future<void> save(PracticeSession session);
  Future<void> delete(String id);

  /// Privacy: wipes every transcript on the device.
  Future<void> deleteAll();
}

/// The user's saved communication assets.
abstract class PlaybookRepository {
  Future<List<PlaybookEntry>> all();
  Future<void> add(PlaybookEntry entry);
  Future<void> delete(String id);

  /// Records that an entry was surfaced before a session — this is what makes
  /// "used in 3 sessions" a real number rather than a decoration.
  Future<void> markUsed(String id);

  Future<void> deleteAll();
}

/// Lightweight user state: onboarding, preferences and the free-tier counter.
abstract class ProfileRepository {
  Future<String> userId();
  Future<bool> hasOnboarded();
  Future<void> completeOnboarding(String interest);
  Future<String?> interest();

  Future<bool> voiceOutputEnabled();
  Future<void> setVoiceOutputEnabled(bool enabled);

  /// Sessions started inside the current rolling week.
  Future<int> sessionsThisWeek();
  Future<void> recordSessionStarted();

  Future<void> clear();
}
