import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/failures.dart';
import '../../core/logger.dart';
import '../../domain/analysis.dart';
import '../../domain/conversation_engine.dart';
import '../../domain/difficulty.dart';
import '../../domain/playbook.dart';
import '../../domain/session.dart';
import '../repositories.dart';

/// On-device SQLite. Transcripts never leave the phone.
class VerbalDatabase {
  const VerbalDatabase._();

  static const _file = 'verbal.db';
  static const _version = 1;

  static Future<Database> open() async {
    final path = p.join(await getDatabasesPath(), _file);
    return openDatabase(path, version: _version, onCreate: _create);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        scenario_id TEXT NOT NULL,
        scenario_title TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        end_reason TEXT,
        turns_json TEXT NOT NULL,
        analysis_json TEXT,
        objections_raised INTEGER NOT NULL DEFAULT 0,
        objections_handled INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_sessions_started ON sessions (started_at DESC)');

    await db.execute('''
      CREATE TABLE playbook (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        why_it_works TEXT NOT NULL,
        skill TEXT NOT NULL,
        source_scenario_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        times_used INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT
      )
    ''');
  }
}

class SqliteSessionRepository implements SessionRepository {
  const SqliteSessionRepository(this._db);

  final Database _db;

  @override
  Future<List<PracticeSession>> all() async {
    try {
      final rows = await _db.query('sessions', orderBy: 'started_at DESC');
      return rows.map(_fromRow).toList();
    } on Object catch (e, s) {
      Log.e('reading sessions failed', e, s);
      throw StorageFailure(cause: e);
    }
  }

  @override
  Future<PracticeSession?> byId(String id) async {
    final rows =
        await _db.query('sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> save(PracticeSession s) async {
    try {
      await _db.insert('sessions', _toRow(s),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } on Object catch (e, st) {
      Log.e('saving session failed', e, st);
      throw StorageFailure(cause: e);
    }
  }

  @override
  Future<void> delete(String id) async =>
      _db.delete('sessions', where: 'id = ?', whereArgs: [id]).then((_) {});

  @override
  Future<void> deleteAll() async => _db.delete('sessions').then((_) {});

  Map<String, Object?> _toRow(PracticeSession s) => {
        'id': s.id,
        'scenario_id': s.scenarioId,
        'scenario_title': s.scenarioTitle,
        'difficulty': s.difficulty.name,
        'started_at': s.startedAt.toIso8601String(),
        'ended_at': s.endedAt?.toIso8601String(),
        'end_reason': s.endReason?.name,
        'turns_json': jsonEncode(s.turns.map((t) => t.toJson()).toList()),
        'analysis_json':
            s.analysis == null ? null : jsonEncode(s.analysis!.toJson()),
        'objections_raised': s.objectionsRaised,
        'objections_handled': s.objectionsHandled,
      };

  PracticeSession _fromRow(Map<String, Object?> r) {
    final turnsRaw = jsonDecode(r['turns_json'] as String? ?? '[]');
    final analysisRaw = r['analysis_json'] as String?;

    return PracticeSession(
      id: r['id'] as String,
      scenarioId: r['scenario_id'] as String,
      scenarioTitle: r['scenario_title'] as String,
      difficulty: Difficulty.values.firstWhere(
        (d) => d.name == r['difficulty'],
        orElse: () => Difficulty.moderate,
      ),
      startedAt: DateTime.parse(r['started_at'] as String),
      endedAt: DateTime.tryParse(r['ended_at'] as String? ?? ''),
      endReason:
          EndReason.values.where((e) => e.name == r['end_reason']).firstOrNull,
      turns: (turnsRaw as List)
          .whereType<Map<String, dynamic>>()
          .map(Turn.fromJson)
          .toList(),
      analysis: analysisRaw == null
          ? null
          : SessionAnalysis.fromJson(
              jsonDecode(analysisRaw) as Map<String, dynamic>),
      objectionsRaised: (r['objections_raised'] as int? ?? 0),
      objectionsHandled: (r['objections_handled'] as int? ?? 0),
    );
  }
}

class SqlitePlaybookRepository implements PlaybookRepository {
  const SqlitePlaybookRepository(this._db);

  final Database _db;

  @override
  Future<List<PlaybookEntry>> all() async {
    try {
      final rows = await _db.query('playbook', orderBy: 'created_at DESC');
      return rows.map(_fromRow).toList();
    } on Object catch (e, s) {
      Log.e('reading playbook failed', e, s);
      throw StorageFailure(cause: e);
    }
  }

  @override
  Future<void> add(PlaybookEntry e) async {
    try {
      await _db.insert('playbook', _toRow(e),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } on Object catch (err, s) {
      Log.e('saving playbook entry failed', err, s);
      throw StorageFailure(cause: err);
    }
  }

  @override
  Future<void> delete(String id) async =>
      _db.delete('playbook', where: 'id = ?', whereArgs: [id]).then((_) {});

  @override
  Future<void> markUsed(String id) async {
    await _db.rawUpdate(
      'UPDATE playbook SET times_used = times_used + 1, last_used_at = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), id],
    );
  }

  @override
  Future<void> deleteAll() async => _db.delete('playbook').then((_) {});

  Map<String, Object?> _toRow(PlaybookEntry e) => {
        'id': e.id,
        'kind': e.kind.name,
        'title': e.title,
        'body': e.body,
        'why_it_works': e.whyItWorks,
        'skill': e.skill.name,
        'source_scenario_id': e.sourceScenarioId,
        'created_at': e.createdAt.toIso8601String(),
        'times_used': e.timesUsed,
        'last_used_at': e.lastUsedAt?.toIso8601String(),
      };

  PlaybookEntry _fromRow(Map<String, Object?> r) => PlaybookEntry.fromJson({
        'id': r['id'],
        'kind': r['kind'],
        'title': r['title'],
        'body': r['body'],
        'whyItWorks': r['why_it_works'],
        'skill': r['skill'],
        'sourceScenarioId': r['source_scenario_id'],
        'createdAt': r['created_at'],
        'timesUsed': r['times_used'],
        'lastUsedAt': r['last_used_at'],
      });
}

/// Preferences-backed profile.
class PrefsProfileRepository implements ProfileRepository {
  const PrefsProfileRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kUserId = 'user_id';
  static const _kOnboarded = 'onboarded';
  static const _kInterest = 'interest';
  static const _kVoice = 'voice_output';
  static const _kStarts = 'session_starts';

  @override
  Future<String> userId() async {
    final existing = _prefs.getString(_kUserId);
    if (existing != null) return existing;
    final id = 'u_${DateTime.now().microsecondsSinceEpoch}';
    await _prefs.setString(_kUserId, id);
    return id;
  }

  @override
  Future<bool> hasOnboarded() async => _prefs.getBool(_kOnboarded) ?? false;

  @override
  Future<void> completeOnboarding(String interest) async {
    await _prefs.setBool(_kOnboarded, true);
    await _prefs.setString(_kInterest, interest);
  }

  @override
  Future<String?> interest() async => _prefs.getString(_kInterest);

  @override
  Future<bool> voiceOutputEnabled() async => _prefs.getBool(_kVoice) ?? true;

  @override
  Future<void> setVoiceOutputEnabled(bool enabled) async =>
      _prefs.setBool(_kVoice, enabled).then((_) {});

  @override
  Future<int> sessionsThisWeek() async => _recentStarts().length;

  @override
  Future<void> recordSessionStarted() async {
    final starts = _recentStarts()
      ..add(DateTime.now())
      ..sort();
    await _prefs.setStringList(
        _kStarts, starts.map((d) => d.toIso8601String()).toList());
  }

  List<DateTime> _recentStarts() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return (_prefs.getStringList(_kStarts) ?? [])
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .where((d) => d.isAfter(cutoff))
        .toList();
  }

  @override
  Future<void> clear() async {
    for (final key in [_kOnboarded, _kInterest, _kStarts]) {
      await _prefs.remove(key);
    }
  }
}
