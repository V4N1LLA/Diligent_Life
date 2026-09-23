import 'dart:io';

import 'package:diligent_life/app_info.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/models/exercise_session.dart';

import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'record_repository_test.dart' show record;
import 'exercise_test.dart' show point, FakeLocation;

void main() {
  sqfliteFfiInit();
  test('displayed release version matches package metadata', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: $appVersion+$appBuildNumber'),
    );
  });
  for (final path in [
    [1, 3],
    [2, 3],
    [1, 2, 3],
    [3, 3],
  ]) {
    test(
      'SQLite open/reopen migration path ${path.join(' -> ')} preserves rows',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'diligent-migration-',
        );
        final file = '${dir.path}/records.db';
        late Database db;
        addTearDown(() async {
          await db.close();
          await dir.delete(recursive: true);
        });
        Future<Database> open(int version) => databaseFactoryFfi.openDatabase(
          file,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: version,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
            onCreate: RecordRepository.createSchema,
            onUpgrade: RecordRepository.upgradeSchema,
          ),
        );
        db = await open(path.first);
        await RecordRepository(db).save(record('2026-09-01'));
        final daily = await db.query('daily_records');
        List<Map<String, Object?>>? legacySessions, legacyRoute;
        if (path.first == 2) {
          final legacy = await ExerciseRepository(db)
              .start(ExerciseType.lightWalk, 70, point(37, 0).timestamp);
          final row = point(37, 0).toMap(legacy.id)
            ..remove('rawSpeed')
            ..remove('cumulativeMeters');
          await db.insert('route_points', row);
          legacySessions = await db.query('exercise_sessions');
          legacyRoute = await db.query('route_points');
        }
        for (final version in path.skip(1)) {
          await db.close();
          db = await open(version);
          expect(await db.query('daily_records'), daily);
        }
        expect(await db.getVersion(), 3);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        if (legacySessions != null) {
          expect(await db.query('exercise_sessions'), legacySessions);
          final migrated = await db.query('route_points');
          expect(
            migrated
                .map(
                  (row) => Map<String, Object?>.from(row)
                    ..remove('rawSpeed')
                    ..remove('cumulativeMeters'),
                )
                .toList(),
            legacyRoute,
          );
          expect(await db.query('raw_route_points'), isEmpty);
          await db.update('exercise_sessions', {'status': 'finished'});
        }
        final repo = ExerciseRepository(db);
        final s = await repo.start(
          ExerciseType.lightWalk,
          70,
          point(37, 0).timestamp,
        );
        await repo.checkpoint(
          s.copyWith(elapsedSeconds: 6, distanceMeters: 10),
          point: point(37, 0),
          rawPoint: point(37, 0),
          decision: 'accepted',
        );
        expect(await repo.rawRoute(s.id), hasLength(1));
        await db.close();
        db = await open(3);
        expect((await ExerciseRepository(db).active())!.elapsedSeconds, 6);
        expect(await ExerciseRepository(db).rawRoute(s.id), hasLength(1));
        final rawBefore = await db.query('raw_route_points');
        final routeBefore = await db.query('route_points');
        final location = FakeLocation();
        final restored = ExerciseRecorder(
          ExerciseRepository(db),
          location: location,
        );
        await restored.restore();
        expect(restored.session!.status, SessionStatus.paused);
        expect(restored.elapsedSeconds, 6);
        expect(restored.session!.distanceMeters, 10);
        expect(location.requests, 0);
        expect(await db.query('raw_route_points'), rawBefore);
        expect(await db.query('route_points'), routeBefore);
        restored.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
  }
}
