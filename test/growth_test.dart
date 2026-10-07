import 'dart:convert';
import 'dart:io';

import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/data/growth_repository.dart';
import 'package:diligent_life/models/growth.dart';
import 'package:diligent_life/models/route_exploration.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/services/theme_controller.dart';
import 'package:diligent_life/services/achievement_share.dart';
import 'package:diligent_life/screens/growth_screen.dart';
import 'package:diligent_life/widgets/route_scrubber.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:diligent_life/services/step_service.dart';
import 'package:diligent_life/screens/portfolio_share_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'exercise_test.dart' show point;
import 'exercise_map_test.dart' show TestTiles;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  Future<Database> database([int version = 4]) =>
      databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: version,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: RecordRepository.createSchema,
        ),
      );
  test('daily XP caps each source; level boundaries are exact', () {
    expect(
      const ActivityDay(
        '2026-10-06',
        steps: 500000,
        meters: 900000,
        seconds: 86400,
      ).baseXp,
      310,
    );
    expect(levelForXp(199), 1);
    expect(levelForXp(200), 2);
    expect(levelForXp(449), 2);
    expect(levelForXp(450), 3);
    expect(const ActivityDay('2026-10-06').baseXp, 0);
  });
  test('award transaction is idempotent, concurrent refresh cannot duplicate, title requires unlock', () async {
    final db = await database();
    addTearDown(db.close);
    final repo = GrowthRepository(db);
    final now = DateTime(2026, 10, 6);
    await db.insert('daily_steps', {
      'date': '2026-10-06',
      'steps': 5000,
      'coverage': 'observed',
      'updatedAt': now.toIso8601String(),
    });
    final s = ExerciseSession(
      id: 1,
      startedAt: now,
      type: ExerciseType.lightWalk,
      updatedAt: now,
      status: SessionStatus.finished,
      distanceMeters: 5000,
      elapsedSeconds: 1800,
    );
    await db.insert('exercise_sessions', s.toMap());
    final first = await repo.refresh(now);
    expect(first.xp, 375); // 50+75+30 activity, 90 daily, 50+80 achievements.
    await Future.wait(List.generate(8, (_) => repo.refresh(now)));
    expect((await repo.refresh(now)).xp, first.xp);
    await expectLater(
      repo.equip('title.ten_km.v1', first),
      throwsArgumentError,
    );
    await repo.equip('title.five_km.v1', first);
    expect((await repo.refresh(now)).titleId, 'title.five_km.v1');
    await db.delete('exercise_sessions');
    await repo.refresh(now);
    await db.insert('exercise_sessions', s.toMap());
    expect((await repo.refresh(now)).xp, first.xp);
  });
  test('week rollover and day rollover do not replay rewards; weight/manual never award XP', () async {
    final db = await database();
    addTearDown(db.close);
    final repo = GrowthRepository(db);
    for (var i = 0; i < 3; i++) {
      final d = DateTime(2026, 10, 5 + i);
      await db.insert(
        'exercise_sessions',
        ExerciseSession(
          id: i + 1,
          startedAt: d,
          type: ExerciseType.running,
          updatedAt: d,
          status: SessionStatus.finished,
          elapsedSeconds: 600,
        ).toMap(),
      );
    }
    final first = await repo.refresh(DateTime(2026, 10, 7));
    expect(first.quests.last.complete, true);
    final next = await repo.refresh(DateTime(2026, 10, 12));
    expect(next.quests.last.complete, false);
    expect(next.xp, first.xp);
    await db.insert('daily_records', {
      'date': '2026-10-12',
      'weightKg': 50,
      'exerciseType': 'lightWalk',
      'durationMinutes': 120,
      'distanceKm': 50,
      'estimatedCalories': 1000,
      'createdAt': '2026-10-12',
      'updatedAt': '2026-10-12',
    });
    expect((await repo.refresh(DateTime(2026, 10, 12))).xp, first.xp);
  });
  test('v4 backup roundtrips growth but hardware cursor stays local; legacy import preserves new state', () async {
    final db = await database();
    addTearDown(db.close);
    final repo = BackupRepository(db);
    await db.insert('daily_steps', {
      'date': '2026-10-06',
      'steps': 200,
      'coverage': 'partial',
      'updatedAt': '2026-10-06T00:00:00Z',
    });
    await db.insert('step_cursor', {
      'id': 1,
      'boot': 8,
      'counter': 1000,
      'sample': 100,
      'date': '2026-10-06',
    });
    await GrowthRepository(db).refresh(DateTime(2026, 10, 6));
    final file = await repo.export();
    addTearDown(() => file.parent.delete(recursive: true));
    expect(jsonDecode(file.readAsLinesSync().first)['schema'], 4);
    expect(file.readAsStringSync(), isNot(contains('step_cursor')));
    final prepared = await repo.prepare(file);
    addTearDown(prepared.dispose);
    final before = await db.query('daily_steps');
    await repo.replace(prepared);
    expect(await db.query('daily_steps'), before);
    expect((await db.query('step_cursor')).single['counter'], 1000);
    final old = await database(3);
    addTearDown(old.close);
    final legacy = await BackupRepository(old).export();
    addTearDown(() => legacy.parent.delete(recursive: true));
    final staged = await repo.prepare(legacy);
    addTearDown(staged.dispose);
    await repo.replace(staged);
    expect(await db.query('daily_steps'), before);
  });
  for (final brightness in Brightness.values) {
    testWidgets('growth fits small screen with large font in $brightness', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = await tester.runAsync(() => database());
      addTearDown(() => db!.close());
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: GrowthScreen(repository: GrowthRepository(db!)),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(find.text('오늘 0걸음'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'scrubber skips segment/gap time and distance, snaps to recorded samples',
    () {
      final route = [
        point(37, 0).withDistance(0),
        point(37.0001, 2).withDistance(10),
        point(37.0002, 100, segment: 2).withDistance(10),
        point(37.0003, 102, segment: 2).withDistance(20),
      ];
      final view = RouteExploration(route);
      expect(view.seconds(0, 3), 4);
      expect(view.meters(0, 3), 20);
      expect(view.indexAt(.98), 2);
      expect(view.speed(2), isNull);
      expect(route[3].cumulativeMeters, 20);
    },
  );
  testWidgets(
    'scrubber drag and range handles synchronize selected map samples',
    (tester) async {
      final route = [
        for (var i = 0; i < 15; i++)
          point(37 + i * .0001, i * 2).withDistance(i * 10),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteScrubber(points: route, tileProvider: TestTiles()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(Slider));
      await tester.pump();
      expect(find.textContaining('속도 정보 없음'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.textContaining('선택 구간'), findsOneWidget);
    },
  );
  test('theme persists and invalid values fall back to system', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ThemeController();
    await first.select(ThemeMode.dark);
    final second = ThemeController();
    await second.load();
    expect(second.value, ThemeMode.dark);
    await (await SharedPreferences.getInstance()).setString(
      'themeMode',
      'invalid',
    );
    await second.load();
    expect(second.value, ThemeMode.system);
    first.dispose();
    second.dispose();
  });
  testWidgets('achievement cards export square and 4:5 in both themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final bytes = await tester.runAsync(
        () => achievementShareImage('Lv 2', '첫 발걸음', brightness: brightness),
      );
      expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final portrait = await tester.runAsync(
        () => achievementShareImage(
          '5,000걸음',
          '완료',
          brightness: brightness,
          portrait: true,
        ),
      );
      expect(portrait!.length, greaterThan(1000));
    }
  });
  final private = Platform.environment['S26_V110_BACKUP'];
  test('midnight ambiguous steps remain preserved but do not claim daily XP or quest completion', () async {
    final db = await database();
    addTearDown(db.close);
    await db.insert('daily_steps', {
      'date': '2026-10-06',
      'steps': 5000,
      'uncertainSteps': 1000,
      'coverage': 'boundary',
      'updatedAt': '2026-10-06',
    });
    final snapshot = await GrowthRepository(db).refresh(DateTime(2026, 10, 6));
    expect(snapshot.days.single.steps, 5000);
    expect(snapshot.xp, 40);
    expect(snapshot.quests.first.complete, false);
  });
  for (final from in [1, 2, 3]) {
    test(
      'SQLite automatic $from to 4 migration preserves all original tables and reopens',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'diligent-v110-migration-',
        );
        final path = '${dir.path}/app.db';
        Future<Database> open(int version) => databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: version,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
            onCreate: RecordRepository.createSchema,
            onUpgrade: RecordRepository.upgradeSchema,
          ),
        );
        var db = await open(from);
        await db.insert('daily_records', {
          'date': '2026-10-06',
          'weightKg': 70,
          'exerciseType': 'lightWalk',
          'durationMinutes': 0,
          'distanceKm': null,
          'estimatedCalories': 0,
          'createdAt': '2026-10-06',
          'updatedAt': '2026-10-06',
        });
        final before = await db.query('daily_records');
        await db.close();
        db = await open(4);
        expect(await db.getVersion(), 4);
        expect(await db.query('daily_records'), before);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        await GrowthRepository(db).refresh(DateTime(2026, 10, 6));
        await db.close();
        db = await open(4);
        expect(await db.query('daily_records'), before);
        await db.close();
        await dir.delete(recursive: true);
      },
    );
  }
  testWidgets('step permission denial and native failure have readable UX', (
    tester,
  ) async {
    const channel = MethodChannel('diligent_life/steps');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'status'
              ? {
                  'supported': true,
                  'permission': false,
                  'enabled': false,
                  'running': false,
                  'error': 'start_restricted',
                }
              : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final status = await StepService().enable(true);
    expect(status.permission, false);
    expect(status.message, contains('권한'));
    expect(status.error, isNot(contains('start_restricted')));
    expect(calls, ['enable', 'status']);
  });
  testWidgets(
    'gallery action is available after preview and passes generated PNG only',
    (tester) async {
      final bytes = TestTiles().image.bytes;
      Map<Object?, Object?>? saved;
      const channel = MethodChannel('diligent_life/gallery');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            saved = call.arguments as Map<Object?, Object?>;
            return 'content://media/test';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PortfolioShareScreen.image(
            title: 'Lv 2',
            image: () async => bytes,
            notice: '위치 없는 성취 카드',
            fileName: 'achievement.png',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('갤러리에 저장'));
      await tester.pumpAndSettle();
      expect(saved!['bytes'], bytes);
      expect(saved!['name'], 'achievement.png');
      expect(find.textContaining('갤러리의 Diligent Life'), findsOneWidget);
    },
  );
  test('all real S26 original rows survive v3 to v4 migration and backup unchanged', () async {
    final db = await database(3);
    addTearDown(db.close);
    final source = File(private!);
    final bytes = source.readAsBytesSync();
    final prepared = await BackupRepository(db).prepare(source);
    addTearDown(prepared.dispose);
    await BackupRepository(db).replace(prepared);
    final before = {
      for (final table in backupTables)
        table: await db.query(table, orderBy: 'id'),
    };
    await db.transaction((txn) => GrowthRepository.createSchema(txn));
    await db.setVersion(4);
    await GrowthRepository(db).refresh(DateTime(2026, 10, 6));
    for (final table in backupTables) {
      expect(
        jsonEncode(await db.query(table, orderBy: 'id')) ==
            jsonEncode(before[table]),
        true,
        reason: 'Original $table changed',
      );
    }
    final export = await BackupRepository(db).export();
    addTearDown(() => export.parent.delete(recursive: true));
    final check = await BackupRepository(db).prepare(export);
    addTearDown(check.dispose);
    for (final table in backupTables) {
      expect(
        jsonEncode(await check.database.query(table, orderBy: 'id')) ==
            jsonEncode(before[table]),
        true,
        reason: 'Backup $table changed',
      );
    }

    expect(source.readAsBytesSync(), bytes);
  }, skip: private == null ? 'Private S26 backup not supplied' : false);
}
