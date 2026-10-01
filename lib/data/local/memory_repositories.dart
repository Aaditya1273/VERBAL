import '../../domain/playbook.dart';
import '../../domain/session.dart';
import '../repositories.dart';

/// In-memory implementations.
///
/// These are the test doubles *and* the fallback if the on-device database
/// cannot be opened — the app stays usable for the current run rather than
/// crashing on launch.
class MemorySessionRepository implements SessionRepository {
  final _sessions = <String, PracticeSession>{};

  @override
  Future<List<PracticeSession>> all() async {
    final list = _sessions.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  @override
  Future<PracticeSession?> byId(String id) async => _sessions[id];

  @override
  Future<void> save(PracticeSession session) async {
    _sessions[session.id] = session;
  }

  @override
  Future<void> delete(String id) async => _sessions.remove(id);

  @override
  Future<void> deleteAll() async => _sessions.clear();
}

class MemoryPlaybookRepository implements PlaybookRepository {
  final _entries = <String, PlaybookEntry>{};

  @override
  Future<List<PlaybookEntry>> all() async {
    final list = _entries.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> add(PlaybookEntry entry) async => _entries[entry.id] = entry;

  @override
  Future<void> delete(String id) async => _entries.remove(id);

  @override
  Future<void> markUsed(String id) async {
    final e = _entries[id];
    if (e == null) return;
    _entries[id] =
        e.copyWith(timesUsed: e.timesUsed + 1, lastUsedAt: DateTime.now());
  }

  @override
  Future<void> deleteAll() async => _entries.clear();
}

class MemoryProfileRepository implements ProfileRepository {
  MemoryProfileRepository({String id = 'local-user'}) : _id = id;

  final String _id;
  bool _onboarded = false;
  String? _interest;
  bool _voice = true;
  final List<DateTime> _starts = [];

  @override
  Future<String> userId() async => _id;

  @override
  Future<bool> hasOnboarded() async => _onboarded;

  @override
  Future<void> completeOnboarding(String interest) async {
    _onboarded = true;
    _interest = interest;
  }

  @override
  Future<String?> interest() async => _interest;

  @override
  Future<bool> voiceOutputEnabled() async => _voice;

  @override
  Future<void> setVoiceOutputEnabled(bool enabled) async => _voice = enabled;

  @override
  Future<int> sessionsThisWeek() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _starts.where((d) => d.isAfter(cutoff)).length;
  }

  @override
  Future<void> recordSessionStarted() async => _starts.add(DateTime.now());

  @override
  Future<void> clear() async {
    _onboarded = false;
    _interest = null;
    _starts.clear();
  }
}
