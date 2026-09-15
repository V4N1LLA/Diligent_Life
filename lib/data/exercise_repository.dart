import 'dart:convert';
import 'dart:isolate';

import 'package:sqflite/sqflite.dart';

import '../models/exercise_session.dart';
import '../models/exercise_type.dart';
import '../utils/movement_analysis.dart';
import '../utils/portfolio_analysis.dart';

class ExerciseRepository {
  ExerciseRepository(this.database);
  final Database database;
  Future<void>? _cacheReady;
  Future<void> _ensureCache() => _cacheReady ??= database.execute('''
    CREATE TABLE IF NOT EXISTS portfolio_analysis (
      sessionId INTEGER PRIMARY KEY REFERENCES exercise_sessions(id) ON DELETE CASCADE,
      sourceVersion TEXT NOT NULL, data TEXT NOT NULL
    )''');

  Future<PortfolioAnalysis> portfolioAnalysis(ExerciseSession session) async {
    await _ensureCache();
    return database.transaction((txn) => _portfolioAnalysis(session.id, txn));
  }

  Future<MovementAnalysis> movementAnalysis(
    ExerciseSession session, {
    bool recalculate = false,
  }) async {
    await _ensureCache();
    final data = await database.transaction(
      (txn) => _portfolioAnalysis(session.id, txn, recalculate: recalculate),
    );
    return data.movement ??
        MovementAnalyzer(session, rawAvailable: false).finish();
  }

  Future<PortfolioAnalysis> _portfolioAnalysis(
    int id,
    Transaction txn, {
    bool recalculate = false,
  }) async {
    final current = await txn.query(
      'exercise_sessions',
      where: "id = ? AND status = 'finished'",
      whereArgs: [id],
    );
    if (current.isEmpty) return const PortfolioAnalysis([], null);
    final session = ExerciseSession.fromMap(current.single);
    final version =
        '2/${AnalysisPolicy.version}/${session.updatedAt.toIso8601String()}';
    final cached = await txn.query(
      'portfolio_analysis',
      where: 'sessionId = ? AND sourceVersion = ?',
      whereArgs: [session.id, version],
    );
    if (!recalculate && cached.isNotEmpty) {
      try {
        return PortfolioAnalysis.fromMap(
          jsonDecode(cached.first['data'] as String) as Map<String, dynamic>,
        );
      } catch (_) {
        /* Derived data can always be rebuilt. */
      }
    }
    var table = 'raw_route_points';
    var where = 'sessionId = ?';
    final count = Sqflite.firstIntValue(
      await txn.rawQuery('SELECT COUNT(*) FROM $table WHERE $where', [
        session.id,
      ]),
    )!;
    if (count == 0) {
      table = 'route_points';
      where = 'sessionId = ?';
    }
    final analyzer = MovementAnalyzer(
      session,
      rawAvailable: table == 'raw_route_points',
    );
    int lastId = 0;
    while (true) {
      final rows = await txn.query(
        table,
        where: '$where AND id > ?',
        whereArgs: [session.id, lastId],
        orderBy: 'id',
        limit: 1000,
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        analyzer.addRow(row);
      }
      lastId = rows.last['id'] as int;
    }
    final movement = await Isolate.run(analyzer.finish);
    final analysis = PortfolioAnalysis(
      sampleOverviewRoute(movement.route, 600),
      movement.fastest?.speed,
      movement: movement,
    );
    // A deletion/import during asynchronous analysis must not resurrect a cache.
    final existing = await txn.query(
      'exercise_sessions',
      columns: ['updatedAt'],
      where: "id = ? AND status = 'finished'",
      whereArgs: [session.id],
    );
    if (existing.isNotEmpty &&
        existing.first['updatedAt'] ==
            session.updatedAt.toUtc().toIso8601String()) {
      await txn.insert('portfolio_analysis', {
        'sessionId': session.id,
        'sourceVersion': version,
        'data': jsonEncode(analysis.toMap()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return analysis;
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE exercise_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      startedAt TEXT NOT NULL, endedAt TEXT, updatedAt TEXT NOT NULL,
      exerciseType TEXT NOT NULL, weightKg REAL CHECK(weightKg > 0),
      elapsedSeconds INTEGER NOT NULL CHECK(elapsedSeconds >= 0),
      distanceMeters REAL NOT NULL CHECK(distanceMeters >= 0),
      estimatedCalories REAL CHECK(estimatedCalories >= 0),
      status TEXT NOT NULL CHECK(status IN ('recording','paused','finished'))
    )''');
    await db.execute(
      "CREATE UNIQUE INDEX one_active_session ON exercise_sessions ((1)) WHERE status != 'finished'",
    );
    await db.execute('''CREATE TABLE route_points (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sessionId INTEGER NOT NULL REFERENCES exercise_sessions(id),
      latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
      longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
      timestamp TEXT NOT NULL, accuracy REAL NOT NULL CHECK(accuracy > 0),
      segment INTEGER NOT NULL,
      rawSpeed REAL, cumulativeMeters REAL,
      UNIQUE(sessionId, timestamp)
    )''');
    await db.execute(
      'CREATE INDEX session_route ON route_points(sessionId, id)',
    );
    await createRawSchema(db);
  }

  static Future<void> migrateV3(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE route_points ADD COLUMN rawSpeed REAL');
    await db.execute(
      'ALTER TABLE route_points ADD COLUMN cumulativeMeters REAL',
    );
    await createRawSchema(db);
  }

  static Future<void> createRawSchema(DatabaseExecutor db) async {
    // Append-only sensor samples, including duplicate timestamps and rejected fixes.
    await db.execute('''CREATE TABLE raw_route_points (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sessionId INTEGER NOT NULL REFERENCES exercise_sessions(id),
      latitude REAL, longitude REAL, timestamp TEXT NOT NULL, accuracy REAL,
      segment INTEGER NOT NULL, rawSpeed REAL, cumulativeMeters REAL,
      receivedAt TEXT NOT NULL, decision TEXT NOT NULL,
      filterVersion INTEGER NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX raw_session_route ON raw_route_points(sessionId, id)',
    );
  }

  Future<List<Map<String, Object?>>> rawRoute(int id) => database.query(
    'raw_route_points',
    where: 'sessionId = ?',
    whereArgs: [id],
    orderBy: 'id ASC',
  );

  Future<ExerciseSession> start(
    ExerciseType type,
    double? weight,
    DateTime now,
  ) async {
    if (weight != null && (!weight.isFinite || weight <= 0 || weight > 500)) {
      throw ArgumentError('Invalid weight');
    }
    final session = ExerciseSession(
      id: 0,
      startedAt: now,
      updatedAt: now,
      type: type,
      weightKg: weight,
    );
    final map = session.toMap()..remove('id');
    final id = await database.insert('exercise_sessions', map);
    return ExerciseSession.fromMap({...map, 'id': id});
  }

  Future<ExerciseSession?> active() async {
    final rows = await database.query(
      'exercise_sessions',
      where: "status != 'finished'",
      limit: 1,
    );
    return rows.isEmpty ? null : ExerciseSession.fromMap(rows.first);
  }

  Future<List<ExerciseSession>> history() async => (await database.query(
    'exercise_sessions',
    where: "status = 'finished'",
    orderBy: 'startedAt DESC',
  )).map(ExerciseSession.fromMap).toList();

  Future<List<ExerciseSession>> finishedBetween({
    DateTime? from,
    required DateTime before,
  }) async => (await database.query(
    'exercise_sessions',
    where:
        "status = 'finished' AND startedAt < ?${from == null ? '' : ' AND startedAt >= ?'}",
    whereArgs: [
      before.toUtc().toIso8601String(),
      if (from != null) from.toUtc().toIso8601String(),
    ],
    orderBy: 'startedAt ASC, id ASC',
  )).map(ExerciseSession.fromMap).toList();

  // v0.3 raw samples retain the filtering decisions. Older sessions fall back
  // to their saved accepted route; unavailable raw data is never fabricated.
  Future<List<RoutePoint>> analysisRoute(int id) async {
    final rows = await database.query(
      'raw_route_points',
      where: "sessionId = ? AND decision = 'accepted'",
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    return rows.isEmpty ? route(id) : rows.map(RoutePoint.fromMap).toList();
  }

  Future<List<RoutePoint>> route(int id) async => (await database.query(
    'route_points',
    where: 'sessionId = ?',
    whereArgs: [id],
    orderBy: 'id ASC',
  )).map(RoutePoint.fromMap).toList();

  Future<void> deleteFinished(int id) => database.transaction((txn) async {
    final sessions = await txn.query(
      'exercise_sessions',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (sessions.isEmpty ||
        sessions.single['status'] != SessionStatus.finished.name) {
      throw StateError('Only an existing finished session can be deleted');
    }
    await txn.delete(
      'raw_route_points',
      where: 'sessionId = ?',
      whereArgs: [id],
    );
    await txn.delete('route_points', where: 'sessionId = ?', whereArgs: [id]);
    final deleted = await txn.delete(
      'exercise_sessions',
      where: "id = ? AND status = 'finished'",
      whereArgs: [id],
    );
    if (deleted != 1) throw StateError('Session deletion failed');
  });

  Future<void> checkpoint(
    ExerciseSession session, {
    RoutePoint? point,
    RoutePoint? rawPoint,
    DateTime? receivedAt,
    String? decision,
    int filterVersion = 1,
  }) async {
    if (!session.distanceMeters.isFinite ||
        session.distanceMeters < 0 ||
        session.elapsedSeconds < 0) {
      throw ArgumentError('Invalid session statistics');
    }
    await database.transaction((txn) async {
      final changed = await txn.update(
        'exercise_sessions',
        session.toMap()
          ..remove('id')
          ..remove('startedAt'),
        where: "id = ? AND status != 'finished'",
        whereArgs: [session.id],
      );
      if (changed != 1) throw StateError('Session is no longer active');
      if (point != null) {
        await txn.insert('route_points', point.toMap(session.id));
      }
      if (rawPoint != null) {
        await txn.insert('raw_route_points', {
          ...rawPoint.toMap(session.id),
          'receivedAt': (receivedAt ?? session.updatedAt)
              .toUtc()
              .toIso8601String(),
          'decision': decision ?? 'accepted',
          'filterVersion': filterVersion,
        });
      }
    });
  }
}
