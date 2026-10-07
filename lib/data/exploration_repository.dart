import 'dart:isolate';

import 'package:sqflite/sqflite.dart';

import '../models/exercise_session.dart';
import '../models/exploration.dart';
import '../utils/movement_analysis.dart';
import 'exercise_repository.dart';

// Persistent unlocks use the schema-4 exploration_events table already backed up.
// Scans are a disposable derived cache, like portfolio_analysis (not user data).
class ExplorationRepository {
  ExplorationRepository(this.exercises);
  final ExerciseRepository exercises;
  Database get database => exercises.database;
  Future<void> _prepare() async {
    await database.execute('''CREATE TABLE IF NOT EXISTS exploration_scans (
      sessionId INTEGER PRIMARY KEY REFERENCES exercise_sessions(id) ON DELETE CASCADE,
      sourceVersion TEXT NOT NULL)''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS exploration_region ON exploration_events(regionId)',
    );
  }

  Future<Set<String>> discover(ExerciseSession session) async {
    if (session.status != SessionStatus.finished) return {};
    await _prepare();
    final version =
        '$explorationRuleVersion/${AnalysisPolicy.version}/${session.updatedAt.toUtc().toIso8601String()}';
    final scanned = await database.query(
      'exploration_scans',
      where: 'sessionId = ? AND sourceVersion = ?',
      whereArgs: [session.id, version],
    );
    if (scanned.isNotEmpty) return {};
    // Raw-less legacy sessions never produce invented unlocks.
    final raw = await exercises.rawRoute(session.id);
    final analysis = raw.isEmpty
        ? null
        : await exercises.movementAnalysis(session);
    final cells = analysis == null
        ? <String>{}
        : await _calculate(session, raw, analysis);
    return database.transaction((txn) async {
      final current = await txn.query(
        'exercise_sessions',
        where: "id = ? AND status = 'finished' AND updatedAt = ?",
        whereArgs: [session.id, session.updatedAt.toUtc().toIso8601String()],
      );
      if (current.isEmpty) {
        return <String>{}; // Deletion/import during calculation.
      }
      final added = <String>{};
      for (final id in cells) {
        final existing = await txn.query(
          'exploration_events',
          columns: ['id'],
          where: 'regionId = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        await txn.insert('exploration_events', {
          'eventKey': 'exploration:$id',
          'regionId': id,
          'sourceSessionId': session.id,
          'modelVersion': explorationRuleVersion,
          'discoveredAt': (session.endedAt ?? session.updatedAt)
              .toUtc()
              .toIso8601String(),
        });
        added.add(id);
      }
      await txn.insert('exploration_scans', {
        'sessionId': session.id,
        'sourceVersion': version,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return added;
    });
  }

  Future<ExplorationSummary> summary(DateTime now, {int? sessionId}) async {
    final rows = await database.query(
      'exploration_events',
      where: 'modelVersion = ?',
      whereArgs: [explorationRuleVersion],
      orderBy: 'id',
    );
    final cells = <String, ExplorationCell>{}, highlighted = <String>{};
    int month = 0;
    for (final row in rows) {
      final id = row['regionId'] as String;
      final cell = ExplorationCell.parse(id);
      final at = DateTime.tryParse(row['discoveredAt'] as String)?.toLocal();
      if (cell == null ||
          row['eventKey'] != 'exploration:$id' ||
          at == null ||
          at.isAfter(now)) {
        continue;
      }
      if (cells.containsKey(id)) continue;
      cells[id] = cell;
      if (at.year == now.year && at.month == now.month) month++;
      if (sessionId != null && row['sourceSessionId'] == sessionId) {
        highlighted.add(id);
      }
    }
    return ExplorationSummary(
      List.unmodifiable(cells.values),
      month,
      Set.unmodifiable(highlighted),
    );
  }
}

Future<Set<String>> _calculate(
  ExerciseSession session,
  List<Map<String, Object?>> raw,
  MovementAnalysis analysis,
) => Isolate.run(() => qualifyingCells(session, raw, analysis));
