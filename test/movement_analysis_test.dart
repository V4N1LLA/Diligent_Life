import 'dart:convert';

import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/utils/movement_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final epoch = DateTime.utc(2026, 9, 15);
ExerciseSession session(
  int seconds, {
  ExerciseType type = ExerciseType.lightWalk,
}) => ExerciseSession(
  id: 1,
  startedAt: epoch,
  updatedAt: epoch.add(Duration(seconds: seconds)),
  endedAt: epoch.add(Duration(seconds: seconds)),
  elapsedSeconds: seconds,
  type: type,
  status: SessionStatus.finished,
);
RoutePoint fix(
  int seconds,
  double meters, {
  int segment = 0,
  double accuracy = 5,
}) => RoutePoint(
  latitude: meters / 111194.92664455874,
  longitude: 127,
  timestamp: epoch.add(Duration(seconds: seconds)),
  accuracy: accuracy,
  segment: segment,
  rawSpeed: 999,
);
Map<String, Object?> raw(RoutePoint p) => {
  ...p.toMap(1),
  'receivedAt': p.timestamp.toUtc().toIso8601String(),
  'decision': 'stationary_noise',
  'filterVersion': 2,
};
MovementAnalysis analyze(
  List<RoutePoint> points, {
  ExerciseType type = ExerciseType.lightWalk,
  bool rawAvailable = true,
  int? elapsed,
}) {
  final analyzer = MovementAnalyzer(
    session(
      elapsed ?? points.last.timestamp.difference(epoch).inSeconds,
      type: type,
    ),
    rawAvailable: rawAvailable,
  );
  for (final p in points) {
    analyzer.addRow(raw(p));
  }
  return analyzer.finish();
}

void main() {
  test('stationary → walking → stationary separates time and never adds idle drift', () {
    final result = analyze([
      for (var i = 0; i <= 120; i++)
        fix(
          i,
          i <= 30
              ? 0
              : i <= 90
              ? (i - 30) * 1.4
              : 84,
        ),
    ]);
    expect(result.movingSeconds, 60);
    expect(result.stoppedSeconds, 60);
    expect(result.unknownSeconds, 0);
    expect(result.meters, closeTo(84, .01));
    expect(result.averageMovingKmh, closeTo(5.04, .01));
    expect(result.fastest!.kmh, closeTo(5.04, .01));
    expect(result.bests, isEmpty);
  });
  test(
    'median removes alternating stationary jitter; raw sensor speed ignored',
    () {
      final result = analyze([
        for (var i = 0; i <= 120; i++) fix(i, i.isEven ? -1 : 1),
      ]);
      expect(result.meters, 0);
      expect(result.movingSeconds, 0);
      expect(result.stoppedSeconds, 120);
      expect(result.fastest, isNull);
    },
  );
  test('slow walking at mediocre accuracy extends windows instead of becoming stopped', () {
    final result = analyze([
      for (var i = 0; i <= 120; i++) fix(i, i.toDouble(), accuracy: 20),
    ]);
    // The unfinished final window remains explicitly unknown.
    expect(result.movingSeconds, inInclusiveRange(108, 120));
    expect(result.stoppedSeconds, 0);
    expect(result.meters, closeTo(120, 12));
    expect(result.unknownSeconds + result.movingSeconds, 120);
  });
  test('noisy one-fix speed does not reject a smooth walking average', () {
    final result = analyze([
      for (var i = 0; i <= 120; i++) fix(i, i * 1.4 + (i.isEven ? 1.1 : -1.1)),
    ]);
    expect(result.movingSeconds, 120);
    expect(result.meters, closeTo(168, 3));
    expect(result.fastest!.kmh, lessThan(7));
  });
  test('activity-specific average limits exclude vehicles and sustained excessive speed', () {
    final points = [for (var i = 0; i <= 120; i++) fix(i, i * 4.0)];
    expect(analyze(points).meters, 0);
    expect(analyze(points).stoppedSeconds, 0);
    expect(analyze(points).unknownSeconds, 120);
    expect(
      analyze(points, type: ExerciseType.jogging).meters,
      closeTo(480, .01),
    );
    expect(
      analyze([
        for (var i = 0; i <= 120; i++) fix(i, i * 30.0),
      ], type: ExerciseType.running).meters,
      0,
    );
  });
  test(
    'spike and recovery cannot bridge a gap or create a fastest distance',
    () {
      final result = analyze([
        for (var i = 0; i <= 120; i++) fix(i, i == 60 ? 10000 : i * 1.4),
      ]);
      expect(result.meters, lessThan(168));
      expect(result.movingSeconds, greaterThan(90));
      expect(result.bests, isEmpty); // Each uninterrupted half is <100m.
      expect(result.rejectedSamples, greaterThanOrEqualTo(2));
      expect(result.fastest!.kmh, closeTo(5.04, .01));
    },
  );
  test('manual pause, quality loss, stale and duplicate samples never inflate distance or stops', () {
    final analyzer = MovementAnalyzer(
      session(180).copyWith(elapsedSeconds: 120),
      rawAvailable: true,
    );
    for (var i = 0; i <= 60; i++) {
      analyzer.addRow(raw(fix(i, i * 1.4)));
    }
    analyzer.addRow(raw(fix(60, 9999))); // Duplicate.
    analyzer.addRow(raw(fix(70, 9999, accuracy: 60)));
    analyzer.addRow({
      ...raw(fix(80, 9999)),
      'receivedAt': epoch.add(const Duration(seconds: 100)).toIso8601String(),
    });
    for (var i = 120; i <= 180; i++) {
      analyzer.addRow(raw(fix(i, 1000 + (i - 120) * 1.4, segment: 1)));
    }
    final result = analyzer.finish();
    expect(result.meters, closeTo(168, .01));
    expect(result.movingSeconds, 120);
    expect(result.stoppedSeconds, 0);
    expect(result.unknownSeconds, 0);
    expect(result.bests, isEmpty);
  });
  test('outage is unknown, short idle evidence is unknown, legacy stops are unavailable', () {
    final gap = analyze([fix(0, 0), fix(6, 8.4), fix(60, 8.4), fix(66, 16.8)]);
    expect(gap.movingSeconds, 12);
    expect(gap.stoppedSeconds, 0);
    expect(gap.unknownSeconds, 54);
    final short = analyze([for (var i = 0; i <= 6; i++) fix(i, 0)]);
    expect(short.stoppedSeconds, 0);
    expect(short.unknownSeconds, 6);
    final legacy = analyze([
      for (var i = 0; i <= 30; i++) fix(i, 0),
    ], rawAvailable: false);
    expect(legacy.rawAvailable, isFalse);
    expect(legacy.stoppedSeconds, 0);
    expect(legacy.unknownSeconds, 30);
  });
  test('fixed distance records interpolate exact endpoints for all three distances', () {
    final result = analyze([for (var i = 0; i <= 720; i++) fix(i, i * 2.0)]);
    expect(result.bests.map((b) => b.meters), [100, 500, 1000]);
    for (final b in result.bests) {
      expect(b.seconds, closeTo(b.meters / 2, 1e-5));
      expect(b.paceSeconds, closeTo(500, .001));
    }
    expect(result.route.length, lessThan(400));
    expect(
      MovementAnalysis.fromMap(
        jsonDecode(jsonEncode(result.toMap())) as Map<String, dynamic>,
      ).toMap(),
      result.toMap(),
    );
  });
  test('fastest window may end at a vertex with an interpolated start', () {
    final points = [fix(0, 0), fix(100, 100), fix(115, 160), fix(135, 200)];
    final best = fastestDistances([
      MovementSection(points, 200, MovementKind.moving),
    ]).single;
    expect(best.seconds, closeTo(35, 1e-5));
    expect(best.start.timestamp, epoch.add(const Duration(seconds: 100)));
    final endBest = fastestDistances([
      MovementSection(
        [fix(0, 0), fix(50, 50), fix(75, 150)],
        150,
        MovementKind.moving,
      ),
    ]).single;
    expect(endBest.seconds, closeTo(25, 1e-5));
  });
  test('fastest end-anchored window interpolates a start between vertices', () {
    final best = fastestDistances([
      MovementSection(
        [fix(0, 0), fix(80, 80), fix(95, 140), fix(215, 200)],
        200,
        MovementKind.moving,
      ),
    ]).single;
    expect(best.seconds, closeTo(55, .00001));
    expect(
      best.start.timestamp.difference(epoch).inMicroseconds / 1e6,
      closeTo(40, .00001),
    );
    expect(best.end.timestamp, epoch.add(const Duration(seconds: 95)));
  });
  test('distance records never cross stopped or excluded sections', () {
    expect(
      fastestDistances([
        MovementSection([fix(0, 0), fix(40, 80)], 80, MovementKind.moving),
        MovementSection(
          [fix(40, 80, segment: 1), fix(60, 80, segment: 1)],
          0,
          MovementKind.stopped,
        ),
        MovementSection(
          [fix(60, 80, segment: 2), fix(100, 160, segment: 2)],
          80,
          MovementKind.moving,
        ),
      ]),
      isEmpty,
    );
  });
  test(
    'long raw trace keeps exact records before reducing display geometry',
    () {
      final result = analyze([
        for (var i = 0; i <= 24000; i++) fix(i, i * 1.4),
      ]);
      expect(result.movingSeconds, 24000);
      expect(result.meters, closeTo(33600, .1));
      expect(result.route.length, lessThanOrEqualTo(12000));
      for (final best in result.bests) {
        expect(best.seconds, closeTo(best.meters / 1.4, .00001));
      }
    },
  );
  test('cache, force recalculation and version invalidation preserve every original column', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        version: 1,
        onCreate: (db, _) => ExerciseRepository.createSchema(db),
      ),
    );
    addTearDown(db.close);
    final repository = ExerciseRepository(db);
    final s = session(120);
    await db.insert('exercise_sessions', s.toMap());
    final batch = db.batch();
    for (var i = 0; i <= 120; i++) {
      batch.insert('raw_route_points', raw(fix(i, i * 1.4)));
    }
    await batch.commit(noResult: true);
    final original = await db.query('raw_route_points');
    final sessionBefore = await db.query('exercise_sessions');
    final first = await repository.movementAnalysis(s);
    expect(first.meters, closeTo(168, .01));
    expect((await repository.movementAnalysis(s)).toMap(), first.toMap());
    await db.update('portfolio_analysis', {
      'sourceVersion': 'obsolete',
      'data': 'invalid',
    });
    expect((await repository.movementAnalysis(s)).toMap(), first.toMap());
    expect(
      (await repository.movementAnalysis(s, recalculate: true)).toMap(),
      first.toMap(),
    );
    expect(await db.query('raw_route_points'), original);
    expect(await db.query('exercise_sessions'), sessionBefore);
    expect(await db.query('route_points'), isEmpty);
  });
}
