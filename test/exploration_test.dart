import 'dart:convert';
import 'dart:ui' as ui;

import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/exploration_repository.dart';
import 'package:diligent_life/data/growth_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/models/exploration.dart';
import 'package:diligent_life/screens/all_time_map_screen.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/services/exploration_share.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:diligent_life/utils/gps.dart';
import 'package:diligent_life/utils/movement_analysis.dart';
import 'package:diligent_life/widgets/exercise_route.dart';
import 'package:diligent_life/widgets/exploration_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'exercise_map_test.dart' show TestTiles;
import 'exercise_widget_test.dart' show MemoryExerciseRepository;
import 'exercise_test.dart' show FakeLocation;
import 'widget_test.dart' show MemoryRecords;

final epoch = DateTime.utc(2026, 10, 5, 3);
final cell = ExplorationCell.at(37.5, 127);
ExerciseSession session(int id, {int seconds = 80}) => ExerciseSession(
  id: id,
  startedAt: epoch,
  endedAt: epoch.add(Duration(seconds: seconds)),
  updatedAt: epoch.add(Duration(seconds: seconds)),
  status: SessionStatus.finished,
  type: ExerciseType.lightWalk,
  elapsedSeconds: seconds,
  distanceMeters: 112,
);

List<Map<String, Object?>> path({int id = 1, int count = 41}) {
  final nw = cell.corner(0, 0), se = cell.corner(1, 1);
  return [
    for (var i = 0; i < count; i++)
      {
        ...RoutePoint(
          latitude:
              (nw.latitude + se.latitude) / 2 - 56 / 111195 + i * 2.8 / 111195,
          longitude: (nw.longitude + se.longitude) / 2,
          timestamp: epoch.add(Duration(seconds: i * 2)),
          accuracy: 5,
          rawSpeed: 1.4,
          cumulativeMeters: i * 2.8,
        ).toMap(id),
        'receivedAt': epoch.add(Duration(seconds: i * 2)).toIso8601String(),
        'decision': 'accepted',
        'filterVersion': 2,
      },
  ];
}

MovementAnalysis analyze(ExerciseSession s, List<Map<String, Object?>> rows) {
  final analyzer = MovementAnalyzer(s, rawAvailable: true);
  for (final row in rows) {
    analyzer.addRow(row);
  }
  return analyzer.finish();
}

// Isolate the exploration guard from the analysis guard, so either guard
// regressing is caught rather than hidden by the other rejecting the same input.
MovementAnalysis trusted(List<Map<String, Object?>> rows) => MovementAnalysis(
  sections: [
    MovementSection(
      [RoutePoint.fromMap(rows.first), RoutePoint.fromMap(rows.last)],
      112,
      MovementKind.moving,
    ),
  ],
  bests: const [],
  elapsedSeconds: 80,
  rawAvailable: true,
  rejectedSamples: 0,
);

Future<Database> database() => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: 4,
    singleInstance: false,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
    onCreate: RecordRepository.createSchema,
  ),
);

Future<ExerciseSession> seed(Database db, {int id = 1, bool raw = true}) async {
  final s = session(id);
  await db.insert('exercise_sessions', s.toMap());
  final batch = db.batch();
  for (final row in path(id: id)) {
    batch.insert(
      'route_points',
      Map.of(row)
        ..remove('receivedAt')
        ..remove('decision')
        ..remove('filterVersion'),
    );
    if (raw) batch.insert('raw_route_points', row);
  }
  await batch.commit(noResult: true);
  return s;
}

Future<void> event(Database db, int n, DateTime at, {int version = 1}) =>
    db.insert('exploration_events', {
      'eventKey': 'exploration:wm17.${cell.x + n}.${cell.y}.v1',
      'regionId': 'wm17.${cell.x + n}.${cell.y}.v1',
      'modelVersion': version,
      'discoveredAt': at.toUtc().toIso8601String(),
    });

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final fail in [false, true]) {
    testWidgets(
      'workout is saved before exploration; failure=$fail preserves detail',
      (tester) async {
        final exercises = MemoryExerciseRepository(), location = FakeLocation();
        final recorder = ExerciseRecorder(exercises, location: location);
        await recorder.start(ExerciseType.lightWalk, 70);
        var called = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ExerciseScreen(
              recorder: recorder,
              records: MemoryRecords(),
              onDiscover: (s) async {
                expect(exercises.saved!.status, SessionStatus.finished);
                expect(recorder.active, false);
                called++;
                if (fail) throw StateError('disk error');
                return {cell.id};
              },
            ),
          ),
        );
        await tester.pump();
        await tester.ensureVisible(find.text('운동 종료'));
        await tester.tap(find.text('운동 종료'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('종료하고 저장'));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(called, 1);
        expect(find.byType(ExerciseDetailScreen), findsOneWidget);
        expect(
          find.text('새로운 지역 1곳을 발견했어요'),
          fail ? findsNothing : findsOneWidget,
        );
        expect(exercises.saved!.status, SessionStatus.finished);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        recorder.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
  }
  test(
    'IDs are canonical and stable, Seoul cells have walking-scale dimensions',
    () {
      expect(ExplorationCell.parse(cell.id)!.id, cell.id);
      final nw = cell.corner(0, 0), se = cell.corner(1, 1);
      final center = ExplorationCell.at(
        (nw.latitude + se.latitude) / 2,
        (nw.longitude + se.longitude) / 2,
      );
      expect(center.id, cell.id);
      final width = metersBetween(
        RoutePoint(
          latitude: nw.latitude,
          longitude: nw.longitude,
          timestamp: epoch,
          accuracy: 5,
        ),
        RoutePoint(
          latitude: nw.latitude,
          longitude: se.longitude,
          timestamp: epoch,
          accuracy: 5,
        ),
      );
      expect(width, inInclusiveRange(240, 245));
      for (final invalid in [
        'home',
        'wm17.01.2.v1',
        'wm17.131072.0.v1',
        'wm18.1.2.v1',
        'wm17.${'9' * 150}.0.v1',
      ]) {
        expect(ExplorationCell.parse(invalid), isNull);
      }
    },
  );
  test('real analysis corroborates continuous walking; raw and analysis are unchanged', () {
    final rows = path(), s = session(1);
    final movement = analyze(s, rows);
    final beforeRows = jsonEncode(rows),
        beforeAnalysis = jsonEncode(movement.toMap());
    expect(movement.sections.where((s) => s.recordEligible), isNotEmpty);
    expect(qualifyingCells(s, rows, movement), {cell.id});
    expect(jsonEncode(rows), beforeRows);
    expect(jsonEncode(movement.toMap()), beforeAnalysis);
  });
  test('single fix, brief passage and raw-less analysis cannot unlock', () {
    final rows = path();
    expect(qualifyingCells(session(1), [rows.first], trusted(rows)), isEmpty);
    expect(
      qualifyingCells(session(1), rows.take(10).toList(), trusted(rows)),
      isEmpty,
    );
    final legacy = MovementAnalyzer(session(1), rawAvailable: false);
    for (final row in rows) {
      legacy.addRow(row);
    }
    expect(qualifyingCells(session(1), rows, legacy.finish()), isEmpty);
  });
  for (final (field, value) in <(String, Object?)>[
    ('accuracy', 30.0),
    ('accuracy', double.nan),
    ('rawSpeed', null),
    ('rawSpeed', 8.0),
    ('rawSpeed', 0.0),
    ('latitude', double.infinity),
    ('decision', 'unrealistic_speed'),
    ('decision', 'poor_accuracy'),
  ]) {
    test('exploration independently rejects $field=$value', () {
      final rows = path(), analysis = trusted(rows);
      for (final row in rows) {
        row[field] = value;
      }
      expect(qualifyingCells(session(1), rows, analysis), isEmpty);
    });
  }
  test('boundary fixes, stationary jitter, gaps, pauses and duplicate times never bridge unlocks', () {
    final rows = path(), analysis = trusted(rows);
    final edge = rows
        .map((r) => {...r, 'longitude': cell.corner(0, 0).longitude})
        .toList();
    expect(qualifyingCells(session(1), edge, analysis), isEmpty);
    final jitter = rows
        .map((r) => {...r, 'latitude': rows.first['latitude']})
        .toList();
    expect(qualifyingCells(session(1), jitter, analysis), isEmpty);
    final paused = rows
        .map((r) => {...r, 'segment': rows.indexOf(r) ~/ 10})
        .toList();
    expect(qualifyingCells(session(1), paused, analysis), isEmpty);
    final duplicates = rows
        .map((r) => {...r, 'timestamp': rows.first['timestamp']})
        .toList();
    expect(qualifyingCells(session(1), duplicates, analysis), isEmpty);
    final gaps = rows
        .map(
          (r) => {
            ...r,
            'timestamp': epoch
                .add(Duration(seconds: rows.indexOf(r) * 16))
                .toIso8601String(),
          },
        )
        .toList();
    expect(qualifyingCells(session(1), gaps, trusted(gaps)), isEmpty);
  });
  test('v4 additive cache, repeat/concurrent scans and repeat workouts preserve raw and unlock once', () async {
    final db = await database();
    addTearDown(db.close);
    final s = await seed(db), exercises = ExerciseRepository(db);
    final repo = ExplorationRepository(exercises);
    final original = await db.query('raw_route_points');
    final analysis = jsonEncode((await exercises.movementAnalysis(s)).toMap());
    final results = await Future.wait(
      List.generate(3, (_) => repo.discover(s)),
    );
    expect(results.fold<int>(0, (n, r) => n + r.length), 1);
    expect(await repo.discover(s), isEmpty);
    final next = await seed(db, id: 2);
    expect(await repo.discover(next), isEmpty);
    expect(await db.getVersion(), 4);
    expect(await db.query('exploration_events'), hasLength(1));
    expect(
      (await db.query('raw_route_points')).take(original.length).toList(),
      original,
    );
    expect(jsonEncode((await exercises.movementAnalysis(s)).toMap()), analysis);
    final summary = await repo.summary(
      epoch.add(const Duration(days: 1)),
      sessionId: 1,
    );
    expect(summary.cells.single.id, cell.id);
    expect(summary.newIds, {cell.id});
    expect(summary.monthCount, 1);
    await exercises.deleteFinished(1);
    expect(
      (await repo.summary(epoch.add(const Duration(days: 1)))).cells,
      hasLength(1),
    );
    expect(
      await db.query('exploration_scans', where: 'sessionId = 1'),
      isEmpty,
    );
  });
  test('legacy route without raw GPS and unfinished sessions do not invent unlocks', () async {
    final db = await database();
    addTearDown(db.close);
    final repo = ExplorationRepository(ExerciseRepository(db));
    final s = await seed(db, raw: false);
    expect(await repo.discover(s), isEmpty);
    expect(
      await repo.discover(s.copyWith(status: SessionStatus.recording)),
      isEmpty,
    );
    expect(await db.query('exploration_events'), isEmpty);
  });
  test('100 regions award cell XP, daily quest, four achievements and titles only once across dates', () async {
    final db = await database();
    addTearDown(db.close);
    final growth = GrowthRepository(db);
    for (var n = 0; n < 100; n++) {
      await event(db, n, epoch);
    }
    final now = epoch.add(const Duration(hours: 1));
    final first = await growth.refresh(now);
    expect(first.xp, 1000 + 30 + 30 + 80 + 150 + 250);
    expect(first.unlockedTitles, hasLength(4));
    expect(
      first.quests.singleWhere((q) => q.id.contains('exploration')).complete,
      true,
    );
    await Future.wait(List.generate(5, (_) => growth.refresh(now)));
    expect(
      (await growth.refresh(now.add(const Duration(days: 1)))).xp,
      first.xp,
    );
    expect(
      (await growth.refresh(now.add(const Duration(days: 1)))).quests
          .singleWhere((q) => q.id.contains('exploration'))
          .value,
      0,
    );
    await growth.equip('title.exploration_100.v1', first);
    expect((await growth.refresh(now)).titleId, 'title.exploration_100.v1');
    expect(await db.query('xp_ledger'), hasLength(105));
  });
  test(
    'future, unknown-version and malformed events neither surface nor reward',
    () async {
      final db = await database();
      addTearDown(db.close);
      await event(db, 0, epoch.add(const Duration(days: 1)));
      await event(db, 1, epoch, version: 99);
      await db.insert('exploration_events', {
        'eventKey': 'future-format',
        'regionId': 'home',
        'modelVersion': 1,
        'discoveredAt': epoch.toIso8601String(),
      });
      expect((await GrowthRepository(db).refresh(epoch)).xp, 0);
      expect(
        (await ExplorationRepository(ExerciseRepository(db)).summary(epoch))
            .cells,
        isEmpty,
      );
    },
  );
  test('v4 backup preserves every source column, ledger, profile and cells; cache is disposable', () async {
    final db = await database();
    addTearDown(db.close);
    final s = await seed(db),
        repo = ExplorationRepository(ExerciseRepository(db));
    await repo.discover(s);
    await GrowthRepository(db).refresh(epoch.add(const Duration(days: 1)));
    final before = {
      for (final t in [...backupTables, ...growthBackupTables])
        t: await db.query(t, orderBy: 'id'),
    };
    final backup = BackupRepository(db), file = await backup.export();
    addTearDown(() => file.parent.delete(recursive: true));
    expect(file.readAsStringSync(), isNot(contains('exploration_scans')));
    final staged = await backup.prepare(file);
    addTearDown(staged.dispose);
    await backup.replace(staged);
    expect({
      for (final t in [...backupTables, ...growthBackupTables])
        t: await db.query(t, orderBy: 'id'),
    }, before);
    expect(await db.query('exploration_scans'), isEmpty);
    expect(await repo.discover(s), isEmpty);
    expect(
      (await GrowthRepository(db).refresh(epoch.add(const Duration(days: 1))))
          .xp,
      (before['xp_ledger']!).fold<int>(0, (n, r) => n + (r['xp'] as int)),
    );
  });
  for (final legacy in [false, true]) {
    test(
      'restore detaches stale source IDs without losing cells or XP; legacy=$legacy',
      () async {
        final db = await database();
        addTearDown(db.close);
        final exercises = ExerciseRepository(db),
            repo = ExplorationRepository(exercises);
        final s = await seed(db);
        await repo.discover(s);
        final now = epoch.add(const Duration(days: 1));
        final xp = (await GrowthRepository(db).refresh(now)).xp;
        final backup = BackupRepository(db);
        late final PreparedBackup staged;
        if (legacy) {
          final old = await databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(
              version: 3,
              singleInstance: false,
              onCreate: RecordRepository.createSchema,
            ),
          );
          addTearDown(old.close);
          // A different restored workout happens to have the same integer ID.
          await old.insert(
            'exercise_sessions',
            session(1).copyWith(distanceMeters: 0).toMap(),
          );
          final file = await BackupRepository(old).export();
          addTearDown(() => file.parent.delete(recursive: true));
          staged = await backup.prepare(file);
        } else {
          await exercises.deleteFinished(s.id);
          final file = await backup.export();
          addTearDown(() => file.parent.delete(recursive: true));
          staged = await backup.prepare(file);
        }
        addTearDown(staged.dispose);
        await backup.replace(staged);
        final rows = await db.query('exploration_events');
        expect(rows.single['regionId'], cell.id);
        expect(rows.single['sourceSessionId'], isNull);
        expect((await repo.summary(now, sessionId: 1)).newIds, isEmpty);
        expect((await GrowthRepository(db).refresh(now)).xp, xp);
      },
    );
  }
  test('large route calculation and 10k-cell camera queries are bounded by viewport/LOD', () {
    final rows = path(count: 24001), s = session(1, seconds: 48000);
    final timer = Stopwatch()..start();
    final found = qualifyingCells(s, rows, trusted(rows));
    expect(found.length, greaterThan(200));
    final grid = [
      for (var y = 0; y < 100; y++)
        for (var x = 0; x < 100; x++) ExplorationCell(cell.x + x, cell.y + y),
    ];
    final index = ExplorationIndex(grid, {grid.first.id});
    final bounds = (
      cell.corner(0, 0),
      ExplorationCell(cell.x + 3, cell.y + 3).corner(1, 1),
    );
    for (var i = 0; i < 1000; i++) {
      final visible = index.visible(
        bounds.$1.longitude,
        bounds.$2.latitude,
        bounds.$2.longitude,
        bounds.$1.latitude,
        17,
      );
      expect(visible.length, lessThanOrEqualTo(25));
      expect(visible.any((v) => v.$2), true);
    }
    expect(index.visible(-180, -85, 180, 85, 0).length, 1);
    expect(
      index.visible(-180, -85, 180, 85, 17).length,
      lessThanOrEqualTo(512),
    );
    expect(timer.elapsed, lessThan(const Duration(seconds: 15)));
    // Printed aggregate timings contain no source GPS data.
    debugPrint(
      'Exploration benchmark: ${rows.length} fixes / ${grid.length} cells / 1000 viewports in ${timer.elapsedMilliseconds}ms',
    );
  });
  test(
    'camera queries wrap the date line, including longitudes beyond 180',
    () {
      final index = ExplorationIndex([
        ExplorationCell(0, cell.y),
        ExplorationCell((1 << 17) - 1, cell.y),
      ], {});
      final nw = cell.corner(0, 0), se = cell.corner(1, 1);
      final normal = index.visible(
        179.99,
        se.latitude,
        -179.99,
        nw.latitude,
        17,
      );
      final wrapped = index.visible(
        179.99,
        se.latitude,
        180.01,
        nw.latitude,
        17,
      );
      expect(
        normal.map((e) => e.$1.id),
        containsAll(['wm17.0.${cell.y}.v1', 'wm17.131071.${cell.y}.v1']),
      );
      expect(wrapped.map((e) => e.$1.id), normal.map((e) => e.$1.id));
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'exploration overlay and count-only card render in $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: Scaffold(
              body: ExerciseRoute(
                points: const [],
                exploredCells: [cell],
                newCellIds: {cell.id},
                tileProvider: TestTiles(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ExplorationOverlay), findsOneWidget);
        expect(
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
          isNotEmpty,
        );
        await tester.drag(find.byType(FlutterMap), const Offset(40, 20));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final controller = tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .mapController!;
        controller.move(controller.camera.center, 9);
        await tester.pumpAndSettle();
        expect(
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
          isEmpty,
        );
        expect(
          tester.widget<CircleLayer>(find.byType(CircleLayer)).circles,
          isNotEmpty,
        );
        await tester.runAsync(() async {
          final bytes = await explorationShareImage(
            total: 84,
            discovered: 5,
            workout: true,
            brightness: brightness,
          );
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 720);
          expect(frame.image.height, 720);
          frame.image.dispose();
          codec.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'empty exploration screen fits 320dp and font2 in $brightness',
      (tester) async {
        final db = await tester.runAsync(database);
        addTearDown(() => db!.close());
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
              ),
              child: AllTimeMapScreen(repository: ExerciseRepository(db!)),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
        }
        expect(find.text('0개 지역 탐험'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
