import 'dart:async';

import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/utils/gps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'exercise_test.dart' show point, FakeLocation;
import 'record_repository_test.dart' show record;

void main() {
  sqfliteFfiInit();
  test('portfolio uses finished sessions and half-open calendar periods; missing kcal stays unknown', () {
    ExerciseSession session(
      DateTime date, {
      double? weight,
      SessionStatus status = SessionStatus.finished,
    }) => ExerciseSession(
      id: 1,
      startedAt: date,
      updatedAt: date,
      type: ExerciseType.lightWalk,
      weightKg: weight,
      elapsedSeconds: 600,
      distanceMeters: 1000,
      status: status,
    );
    final from = DateTime(2026, 9), before = DateTime(2026, 10);
    final values = [
      session(from.subtract(const Duration(seconds: 1))),
      session(from),
      session(from.add(const Duration(days: 1)), weight: 70),
      session(before),
      session(from, status: SessionStatus.paused),
    ];
    final summary = MovementSummary.fromSessions(
      values,
      from: from,
      before: before,
    );
    expect(summary.count, 2);
    expect(summary.meters, 2000);
    expect(summary.seconds, 1200);
    expect(summary.calorieCount, 1);
    expect(summary.calories, closeTo(34.3, .01));
    expect(MovementSummary.fromSessions([session(from)]).calories, isNull);
    expect(MovementSummary.fromSessions([]).count, 0);
  });
  test(
    'speed windows weight distance/time, ignore raw spikes and split pauses',
    () {
      final route = [
        for (int i = 0; i <= 6; i++)
          RoutePoint(
            latitude: 37 + i * .00001,
            longitude: 127,
            timestamp: point(37, i).timestamp,
            accuracy: 5,
            rawSpeed: i == 2 ? 99 : 1,
          ),
        point(38, 10, segment: 1),
        point(38.0001, 16, segment: 1),
      ];
      final sections = speedSections(route);
      expect(sections, hasLength(2));
      expect(sections.first.seconds, 5);
      expect(sections.first.kmh, closeTo(4, .02));
      expect(sections.first.paceSeconds, closeTo(900, 2));
      expect(sections.last.kmh, closeTo(6.67, .02));
      expect(speedSections([point(37, 0), point(38, 40)]), isEmpty);
    },
  );

  test(
    'sustained vehicle movement is never counted, including after 30 seconds',
    () {
      final filter = GpsFilter(
        maxSpeed: TrackingPolicy.maxSpeed(ExerciseType.lightWalk),
      );
      expect(filter.accept(point(37, 0), point(37, 0).timestamp), isNotNull);
      for (int i = 1; i <= 20; i++) {
        final p = point(37 + i * .001, i * 2);
        expect(filter.accept(p, p.timestamp), isNull);
        expect(filter.addedMeters, 0);
        expect(filter.decision, 'implausible_speed');
      }
      final stop = point(37.02001, 42);
      expect(filter.accept(stop, stop.timestamp)!.segment, greaterThan(0));
      expect(filter.addedMeters, 0);
      final walk = point(37.02006, 44);
      expect(filter.accept(walk, walk.timestamp), isNotNull);
      expect(filter.addedMeters, closeTo(5.56, .05));
    },
  );

  test('privacy splits sparse edges crossing an endpoint exclusion circle', () {
    final route = [
      point(37, 0),
      point(37.003, 100),
      point(36.997, 200),
      point(37.02, 400),
    ];
    final visible = privateRoute(route);
    expect(visible, hasLength(2));
    expect(visible.first.segment, isNot(visible.last.segment));
    expect(route[1].segment, 0);
  });

  test(
    'v2 migration preserves daily records and route and allows raw data',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 2,
          onCreate: (db, version) async {
            await RecordRepository.createSchema(db, 1);
            await db.execute('''CREATE TABLE exercise_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT, startedAt TEXT NOT NULL, endedAt TEXT,
          updatedAt TEXT NOT NULL, exerciseType TEXT NOT NULL, weightKg REAL,
          elapsedSeconds INTEGER NOT NULL, distanceMeters REAL NOT NULL,
          estimatedCalories REAL, status TEXT NOT NULL)''');
            await db.execute(
              '''CREATE TABLE route_points (
          id INTEGER PRIMARY KEY AUTOINCREMENT, sessionId INTEGER NOT NULL,
          latitude REAL NOT NULL, longitude REAL NOT NULL, timestamp TEXT NOT NULL,
          accuracy REAL NOT NULL, segment INTEGER NOT NULL, UNIQUE(sessionId, timestamp))''',
            );
          },
        ),
      );
      try {
        await RecordRepository(db).save(record('2026-09-10'));
        final repo = ExerciseRepository(db);
        final session = await repo.start(
          ExerciseType.jogging,
          70,
          point(37, 0).timestamp,
        );
        await db.insert(
          'route_points',
          point(37, 0).toMap(session.id)
            ..remove('rawSpeed')
            ..remove('cumulativeMeters'),
        );
        await db.transaction((txn) async {
          await ExerciseRepository.migrateV3(txn);
        });
        expect(
          (await RecordRepository(db).forDate('2026-09-10'))!.weightKg,
          70,
        );
        expect((await repo.route(session.id)).single.rawSpeed, isNull);
        expect((await repo.route(session.id)).single.latitude, 37);
        expect(
          await repo.rawRoute(session.id),
          isEmpty,
        ); // Never fabricate old raw data.
        final p = point(37.0001, 6).withDistance(11.12);
        await repo.checkpoint(
          session.copyWith(distanceMeters: 11.12),
          point: p,
          rawPoint: p,
          receivedAt: p.timestamp,
          filterVersion: TrackingPolicy.version,
        );
        final raw = (await repo.rawRoute(session.id)).single;
        expect(raw['filterVersion'], TrackingPolicy.version);
        expect(raw['cumulativeMeters'], 11.12);
        expect(await repo.route(session.id), hasLength(2));
        // Failure rolls back the sample and the aggregate together.
        await expectLater(
          repo.checkpoint(
            session.copyWith(distanceMeters: 99),
            point: p,
            rawPoint: p,
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect((await repo.active())!.distanceMeters, 11.12);
        expect(await repo.rawRoute(session.id), hasLength(1));
      } finally {
        await db.close();
      }
    },
  );

  test(
    'recorder preserves rejected, duplicate and pre-start raw samples',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 3,
          onCreate: RecordRepository.createSchema,
        ),
      );
      final repo = ExerciseRepository(db);
      final location = FakeLocation();
      final recorder = ExerciseRecorder(repo, location: location);
      try {
        await recorder.start(ExerciseType.lightWalk, null);
        final now = DateTime.now().toUtc();
        Future<void> emit(int seconds, double accuracy, double lat) async {
          final p = RoutePoint(
            latitude: lat,
            longitude: 127,
            timestamp: now.add(Duration(seconds: seconds)),
            accuracy: accuracy,
            rawSpeed: 45,
          );
          final changed = Completer<void>();
          void listener() {
            if (!changed.isCompleted) changed.complete();
          }

          recorder.addListener(listener);
          location.controller.add(p);
          // Drain the sensor callback before a serialized checkpoint action.
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (seconds >= 0) {
            await changed.future.timeout(const Duration(seconds: 3));
          }
          recorder.removeListener(listener);
        }

        await emit(0, 5, 37);
        await emit(1, 100, 37.01);
        await emit(2, 5, 37.02);
        await emit(2, 5, 37.02);
        await emit(-60, 5, 37);
        await recorder.finish();
        final raw = await repo.rawRoute(recorder.session!.id);
        expect(raw, hasLength(5));
        expect(raw.map((m) => m['decision']), [
          'accepted',
          'quality',
          'implausible_speed',
          'quality',
          'before_segment',
        ]);
        expect(raw.every((m) => m['rawSpeed'] == 45), isTrue);
        expect(await repo.route(recorder.session!.id), hasLength(1));
        expect(recorder.session!.distanceMeters, 0);
      } finally {
        recorder.dispose();
        await location.controller.close();
        await location.service.close();
        await db.close();
      }
    },
  );
}
