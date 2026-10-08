import 'dart:ui' as ui;

import 'package:diligent_life/data/activity_calendar_repository.dart';
import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/activity_calendar.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/activity_calendar_screen.dart';
import 'package:diligent_life/services/monthly_share.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:diligent_life/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LoadedCalendar extends ActivityCalendarRepository {
  LoadedCalendar(super.database, this.data, {this.previous});
  final CalendarMonth data;
  final CalendarMonth? previous;
  @override
  Future<(CalendarMonth, CalendarMonth)> month(
    DateTime month,
    DateTime now,
  ) async => (
    month.month == data.month.month && month.year == data.month.year
        ? data
        : CalendarMonth(month, {}),
    previous ?? CalendarMonth(DateTime(month.year, month.month - 1), {}),
  );
  @override
  Future<CalendarDay> day(DateTime day, DateTime now) async =>
      data.days[dateKey(day)] ?? CalendarDay(dateKey(day));
  @override
  Future<List<ExerciseSession>> sessions(DateTime day, DateTime now) async =>
      [];
  @override
  Future<TimelinePage> timeline(
    DateTime now, {
    String? before,
    int limit = 20,
  }) async => TimelinePage(data.days.values.toList(), null);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late ActivityCalendarRepository repo;
  final now = DateTime(2026, 10, 8, 12);
  Future<Database> open() => databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: RecordRepository.createSchema,
    ),
  );
  setUp(() async {
    db = await open();
    repo = ActivityCalendarRepository(db);
  });
  tearDown(() async => db.close());
  Future<void> steps(DateTime at, int count) => db.insert('daily_steps', {
    'date': dateKey(at),
    'steps': count,
    'coverage': 'observed',
    'updatedAt': at.toUtc().toIso8601String(),
  });
  Future<void> session(
    int id,
    DateTime at, {
    int seconds = 1800,
    double meters = 3000,
    SessionStatus status = SessionStatus.finished,
  }) => db.insert(
    'exercise_sessions',
    ExerciseSession(
      id: id,
      startedAt: at,
      updatedAt: at.add(Duration(seconds: seconds)),
      endedAt: at.add(Duration(seconds: seconds)),
      type: ExerciseType.lightWalk,
      status: status,
      elapsedSeconds: seconds,
      distanceMeters: meters,
    ).toMap(),
  );
  Future<void> cell(int x, DateTime at) async {
    final id = 'wm17.$x.50000.v1';
    await db.insert('exploration_events', {
      'eventKey': 'exploration:$id',
      'regionId': id,
      'modelVersion': 1,
      'discoveredAt': at.toUtc().toIso8601String(),
    });
  }

  Future<void> achievement(String key, DateTime at) async {
    await db.insert('xp_ledger', {
      'rewardKey': key,
      'xp': 50,
      'ruleVersion': 1,
      'earnedAt': at.toUtc().toIso8601String(),
    });
  }

  test('monthly totals keep steps and workout distance separate; multiple workouts', () async {
    await steps(DateTime(2026, 10, 7), 8420);
    await session(1, DateTime(2026, 10, 7, 8));
    await session(2, DateTime(2026, 10, 7, 18), meters: 2200);
    await cell(65000, DateTime(2026, 10, 7, 19));
    await session(3, now, status: SessionStatus.paused);
    final (month, previous) = await repo.month(now, now);
    expect(month.steps, 8420);
    expect(month.meters, 5200);
    expect(month.workouts, 2);
    expect(month.workoutDays, 1);
    expect(month.regions, 1);
    expect(previous.hasActivity, isFalse);
    expect((await repo.day(DateTime(2026, 10, 7), now)).seconds, 3600);
    expect((await repo.sessions(DateTime(2026, 10, 7), now)).map((s) => s.id), [
      2,
      1,
    ]);
  });
  for (final boundary in [
    DateTime(2024, 3, 1),
    DateTime(2026, 1, 1),
    DateTime(2026, 11, 1),
  ]) {
    test(
      'local midnight boundary ${dateKey(boundary)} including leap/year/month end',
      () async {
        final last = boundary.subtract(const Duration(seconds: 1));
        await steps(last, 100);
        await steps(boundary, 200);
        await session(1, last, seconds: 600);
        await session(2, boundary, meters: 1200);
        await cell(65000, last);
        await cell(65001, boundary);
        final (month, previous) = await repo.month(
          boundary,
          boundary.add(const Duration(days: 2)),
        );
        expect(previous.steps, 100);
        expect(month.steps, 200);
        expect(previous.meters, 3000);
        expect(month.meters, 1200);
        expect(previous.regions, 1);
        expect(month.regions, 1);
        expect(previous.days.keys.single, dateKey(last));
        final day = await repo.day(last, boundary.add(const Duration(days: 2)));
        expect(
          day.seconds,
          600,
        ); // Crossing midnight still belongs to start date.
        expect(
          (await repo.day(
            boundary,
            boundary.add(const Duration(days: 2)),
          )).workouts,
          1,
        );
      },
    );
  }
  test('UTC instants project to device-local dates; no future-day or future-instant activity', () async {
    final local = DateTime(2026, 10, 8, 0, 1);
    await session(1, local.toUtc());
    await session(2, DateTime(2026, 10, 8, 23));
    await steps(DateTime(2026, 10, 9), 9000);
    await cell(65000, DateTime(2026, 10, 9));
    await achievement('achievement.first_workout.v1', DateTime(2026, 10, 9));
    final (month, _) = await repo.month(now, now);
    expect(month.days.keys, ['2026-10-08']);
    expect(month.workouts, 1);
    expect((await repo.timeline(now)).days.map((d) => d.date), ['2026-10-08']);
    expect((await repo.sessions(now, now)).single.id, 1);
  });
  test('microsecond midnight boundaries neither round forward nor drop first instant', () async {
    final boundary = DateTime(2026, 10, 1);
    final before = boundary.subtract(const Duration(microseconds: 1));
    final after = boundary.add(const Duration(microseconds: 1));
    await session(1, before);
    await session(2, after);
    await cell(65000, before);
    await cell(65001, after);
    await achievement('achievement.first_workout.v1', before);
    await achievement('achievement.workout_5km.v1', after);
    for (final (level, at) in [(2, before), (3, after)]) {
      await db.insert('character_progress', {
        'progressKey': 'reward:level:$level',
        'kind': 'reward',
        'value': 'Lv. $level 달성',
        'ruleVersion': 1,
        'createdAt': at.toUtc().toIso8601String(),
      });
    }
    final (month, previous) = await repo.month(boundary, now);
    expect(previous.days.keys, ['2026-09-30']);
    expect(month.days.keys, ['2026-10-01']);
    expect(previous.workouts, 1);
    expect(month.workouts, 1);
    expect(previous.regions, 1);
    expect(month.regions, 1);
    expect(previous.days.values.single.milestones.length, 3);
    expect(month.days.values.single.milestones.length, 3);
    expect((await repo.sessions(before, now)).single.id, 1);
    expect((await repo.sessions(after, now)).single.id, 2);
    final (atBoundary, _) = await repo.month(boundary, boundary);
    expect(atBoundary.hasActivity, isFalse); // +1us is still future.
    expect((await repo.timeline(boundary)).days.map((d) => d.date), [
      '2026-09-30',
    ]);
  });
  test('offset and local growth timestamps in older backups retain local-day meaning', () async {
    final offset = now
        .toUtc()
        .add(const Duration(hours: 9))
        .toIso8601String()
        .replaceAll('Z', '+09:00');
    final local = now.toIso8601String();
    for (final (x, at) in [(65000, offset), (65001, local)]) {
      final id = 'wm17.$x.50000.v1';
      await db.insert('exploration_events', {
        'eventKey': 'exploration:$id',
        'regionId': id,
        'modelVersion': 1,
        'discoveredAt': at,
      });
    }
    await db.insert('xp_ledger', {
      'rewardKey': 'achievement.first_workout.v1',
      'xp': 50,
      'ruleVersion': 1,
      'earnedAt': offset,
    });
    await db.insert('character_progress', {
      'progressKey': 'reward:level:2',
      'kind': 'reward',
      'value': 'Lv. 2 달성',
      'ruleVersion': 1,
      'createdAt': local,
    });
    final day = await repo.day(now, now);
    expect(day.regions, 2);
    expect(day.milestones.length, 3);
    expect((await repo.timeline(now)).days.single.date, dateKey(now));
    final file = await BackupRepository(db).export();
    addTearDown(() => file.parent.delete(recursive: true));
    final target = await open();
    addTearDown(target.close);
    final staged = await BackupRepository(target).prepare(file);
    addTearDown(staged.dispose);
    await BackupRepository(target).replace(staged);
    expect((await ActivityCalendarRepository(target).day(now, now)).regions, 2);
  });
  test('milestones use recognition dates, safe catalog titles and no character achievement duplication', () async {
    await achievement('achievement.first_workout.v1', now);
    await achievement('quest.daily.steps_5000.v1:2026-10-08', now);
    await db.insert('character_progress', {
      'progressKey': 'reward:achievement.first_workout.v1',
      'kind': 'reward',
      'value': '업적 달성 · 첫 운동',
      'ruleVersion': 1,
      'createdAt': now.toUtc().toIso8601String(),
    });
    await db.insert('character_progress', {
      'progressKey': 'reward:level:2',
      'kind': 'reward',
      'value': 'arbitrary private text',
      'ruleVersion': 1,
      'createdAt': now.toUtc().toIso8601String(),
    });
    final day = await repo.day(now, now);
    expect(day.milestones, ['업적 · 첫 운동', '타이틀 · 첫 발걸음', 'Lv. 2 확인']);
    expect((await repo.month(now, now)).$1.highlight, '업적 · 첫 운동');
  });
  test('timeline keyset paging has no duplicate or missing dates; empty/zero dates omitted', () async {
    for (var i = 0; i < 47; i++) {
      await steps(DateTime(2026, 10, 8 - i), i + 1);
    }
    await steps(DateTime(2026, 8, 1), 0);
    final seen = <String>[];
    String? before;
    do {
      final page = await repo.timeline(now, before: before, limit: 7);
      expect(page.days.length, lessThanOrEqualTo(7));
      seen.addAll(page.days.map((d) => d.date));
      before = page.nextBefore;
    } while (before != null);
    expect(seen.length, 47);
    expect(seen.toSet().length, 47);
    expect(seen, [...seen]..sort((a, b) => b.compareTo(a)));
    await expectLater(repo.timeline(now, limit: 0), throwsArgumentError);
  });
  test(
    'stored zero-step days stay neutral without expanding sparse projections',
    () async {
      await steps(now, 0);
      expect((await repo.month(now, now)).$1.days, isEmpty);
      expect((await repo.day(now, now)).steps, 0);
      expect((await repo.timeline(now)).days, isEmpty);
    },
  );
  test('deletion immediately changes all projections without stale caches; unlocks remain', () async {
    await session(1, now);
    await achievement('achievement.first_workout.v1', now);
    expect((await repo.month(now, now)).$1.workouts, 1);
    await ExerciseRepository(db).deleteFinished(1);
    final day = await repo.day(now, now);
    expect(day.workouts, 0);
    expect(day.meters, 0);
    expect(day.milestones.length, 2);
    expect(await repo.sessions(now, now), isEmpty);
    expect((await repo.timeline(now)).days.single.workouts, 0);
  });
  test('schema5/format3 restore recreates calendar with no persisted aggregate or mutation', () async {
    await steps(now, 8420);
    await session(1, now);
    await cell(65000, now);
    await achievement('achievement.first_workout.v1', now);
    final tables = [
      ...backupTables,
      ...growthBackupTables,
      ...characterBackupTables,
    ];
    final before = {
      for (final table in tables) table: await db.query(table, orderBy: 'id'),
    };
    await repo.month(now, now);
    await repo.day(now, now);
    await repo.timeline(now);
    expect({
      for (final table in tables) table: await db.query(table, orderBy: 'id'),
    }, before);
    final file = await BackupRepository(db).export();
    addTearDown(() => file.parent.delete(recursive: true));
    final target = await open();
    addTearDown(target.close);
    final staged = await BackupRepository(target).prepare(file);
    addTearDown(staged.dispose);
    await BackupRepository(target).replace(staged);
    final restored = (await ActivityCalendarRepository(
      target,
    ).month(now, now)).$1;
    expect(restored.steps, 8420);
    expect(restored.meters, 3000);
    expect(restored.regions, 1);
    expect(restored.highlight, '업적 · 첫 운동');
    expect(await target.getVersion(), 5);
  });
  test('monthly and paged queries work without route tables on 20 years of history', () async {
    await db.execute('DROP TABLE raw_route_points');
    await db.execute('DROP TABLE route_points');
    final batch = db.batch();
    for (var i = 0; i < 7300; i++) {
      final at = DateTime(2006, 10, 8 + i);
      batch.insert('daily_steps', {
        'date': dateKey(at),
        'steps': 5000,
        'coverage': 'observed',
        'updatedAt': at.toUtc().toIso8601String(),
      });
      batch.insert(
        'exercise_sessions',
        ExerciseSession(
          id: i + 1,
          startedAt: at,
          updatedAt: at,
          type: ExerciseType.lightWalk,
          status: SessionStatus.finished,
          distanceMeters: 3000,
          elapsedSeconds: 1800,
        ).toMap(),
      );
      final regionId = 'wm17.${65000 + i}.50000.v1';
      batch.insert('exploration_events', {
        'eventKey': 'exploration:$regionId',
        'regionId': regionId,
        'modelVersion': 1,
        'discoveredAt': at.toUtc().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
    final watch = Stopwatch()..start();
    final (month, _) = await repo.month(DateTime(2026, 9), now);
    final page = await repo.timeline(now);
    watch.stop();
    // Informational host benchmark, not a device latency guarantee.
    // ignore: avoid_print
    print(
      'calendar 7300 days + sessions: month and timeline ${watch.elapsedMilliseconds}ms',
    );
    expect(month.workouts, 30);
    expect(month.steps, 150000);
    expect(page.days.length, 20);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness comparison requires prior data for each metric', (
      tester,
    ) async {
      final current = CalendarMonth(DateTime(2026, 10), {
        '2026-10-08': const CalendarDay(
          '2026-10-08',
          steps: 8000,
          workouts: 1,
          meters: 3000,
        ),
      });
      final milestonesOnly = CalendarMonth(DateTime(2026, 9), {
        '2026-09-01': const CalendarDay(
          '2026-09-01',
          milestones: ['업적 · 첫 운동'],
        ),
      });
      Widget app(CalendarMonth previous) => MaterialApp(
        theme: appTheme(brightness),
        home: ActivityCalendarScreen(
          repository: LoadedCalendar(db, current, previous: previous),
          exercises: ExerciseRepository(db),
          now: () => now,
        ),
      );
      await tester.pumpWidget(app(milestonesOnly));
      await tester.pumpAndSettle();
      expect(find.textContaining('지난달보다'), findsNothing);
      expect(find.textContaining('운동 거리 +'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        app(
          CalendarMonth(DateTime(2026, 9), {
            '2026-09-01': const CalendarDay('2026-09-01', steps: 2000),
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('지난달보다 +6,000 걸음'), findsOneWidget);
      expect(find.textContaining('운동 거리 +'), findsNothing);
    });
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '320dp $brightness font $scale day and timeline long milestones',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final data = CalendarMonth(DateTime(2026, 10), {
            '2026-10-08': const CalendarDay(
              '2026-10-08',
              steps: 128430,
              workouts: 12,
              meters: 42800,
              seconds: 36000,
              regions: 18,
              milestones: [
                '업적 · 꾸준히 쌓아온 일상의 움직임과 새로운 길',
                '타이틀 · 길 위의 개척자',
                'Lv. 12 확인',
              ],
            ),
          });
          final loaded = LoadedCalendar(db, data);
          Widget app(Widget child) => MaterialApp(
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: child,
          );
          await tester.pumpWidget(
            app(
              ActivityDayScreen(
                date: now,
                repository: loaded,
                exercises: ExerciseRepository(db),
                now: () => now,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('128,430 걸음'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Lv. 12 확인'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          String? selected;
          await tester.pumpWidget(
            app(
              Scaffold(
                body: ActivityTimeline(
                  repository: loaded,
                  now: () => now,
                  onDay: (date) async => selected = date,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('길 위의 개척자'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('2026.10.08'));
          await tester.pumpAndSettle();
          expect(selected, '2026-10-08');
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets('320dp $brightness font $scale calendar grid and semantics', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        String? selected;
        final data = CalendarMonth(DateTime(2026, 10), {
          '2026-10-08': const CalendarDay(
            '2026-10-08',
            steps: 8420,
            workouts: 3,
            regions: 4,
            milestones: ['업적 · 첫 운동'],
          ),
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: CalendarGrid(
                    month: data,
                    today: now,
                    onDay: (d) => selected = d,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final today = find.bySemanticsLabel(RegExp(r'^2026-10-08, 오늘'));
        expect(today, findsOneWidget);
        final node = tester.getSemantics(today);
        expect(node.getSemanticsData().label, contains('8,420걸음'));
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(today);
        expect(selected, '2026-10-08');
        final future = find.bySemanticsLabel(RegExp(r'^2026-10-09, 미래 날짜'));
        expect(
          tester
              .getSemantics(future)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        semantics.dispose();
      });
    }
    testWidgets(
      '320dp font2 $brightness monthly summary and empty month navigation',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = CalendarMonth(DateTime(2026, 10), {
          '2026-10-08': const CalendarDay(
            '2026-10-08',
            steps: 128430,
            workouts: 12,
            meters: 42800,
            regions: 18,
          ),
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ActivityCalendarScreen(
              repository: LoadedCalendar(db, data),
              exercises: ExerciseRepository(db),
              now: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('128,430 걸음'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('월간 기록 공유'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byTooltip('이전 달'),
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byTooltip('이전 달'));
        await tester.pumpAndSettle();
        expect(find.text('2026년 9월'), findsOneWidget);
        expect(find.text('0 걸음'), findsOneWidget);
        expect(find.textContaining('지난달보다'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('monthly share $brightness allowlist and 4:5 PNG', (
      tester,
    ) async {
      final month = CalendarMonth(DateTime(2026, 10), {
        '2026-10-08': const CalendarDay(
          '2026-10-08',
          steps: 128430,
          workouts: 12,
          meters: 42800,
          regions: 18,
          milestones: ['업적 · 첫 운동'],
        ),
      });
      expect(monthlyShareLabels(month), [
        '2026년 10월',
        '128,430 걸음',
        '42.8 km 운동',
        '12회 운동',
        '18개 지역 발견',
        '업적 · 첫 운동',
      ]);
      await tester.runAsync(() async {
        final bytes = await monthlyShareImage(month, brightness);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 720);
        expect(frame.image.height, 900);
        frame.image.dispose();
        codec.dispose();
      });
    });
  }
}
