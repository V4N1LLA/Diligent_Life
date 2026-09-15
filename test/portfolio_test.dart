import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/data/portfolio_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/trends_screen.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:diligent_life/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'record_repository_test.dart' show record;
import 'widget_test.dart' show MemoryRecords;
import 'exercise_widget_test.dart' show MemoryExerciseRepository;

class PortfolioExercises extends MemoryExerciseRepository {
  final sessions = <ExerciseSession>[];
  bool fail = false;
  @override
  Future<List<ExerciseSession>> finishedBetween({
    DateTime? from,
    required DateTime before,
  }) async {
    if (fail) throw StateError('read failed');
    return sessions
        .where(
          (s) =>
              s.status == SessionStatus.finished &&
              (from == null || !s.startedAt.isBefore(from)) &&
              s.startedAt.isBefore(before),
        )
        .toList();
  }

  @override
  Future<List<RoutePoint>> analysisRoute(int id) async => [];
  @override
  Future<PortfolioAnalysis> portfolioAnalysis(ExerciseSession session) async =>
      const PortfolioAnalysis([], null);
}

void main() {
  sqfliteFfiInit();
  group('SQLite portfolio', () {
    late Database db;
    late RecordRepository records;
    late ExerciseRepository exercises;
    late PortfolioRepository portfolio;
    final now = DateTime(2026, 9, 11, 12);
    Future<ExerciseSession> session(
      DateTime date,
      double meters, {
      double? weight,
    }) async {
      final s = await exercises.start(ExerciseType.lightWalk, weight, date);
      final done = s.copyWith(
        status: SessionStatus.finished,
        distanceMeters: meters,
        elapsedSeconds: 600,
      );
      await exercises.checkpoint(done);
      return done;
    }

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: RecordRepository.createSchema,
        ),
      );
      records = RecordRepository(db);
      exercises = ExerciseRepository(db);
      portfolio = PortfolioRepository(records, exercises);
    });
    tearDown(() => db.close());

    test('calendar month/year navigation, longest time, average record and recent order', () async {
      await session(DateTime(2025, 12, 31, 23, 59), 500);
      final august = await session(DateTime(2026, 8, 31, 23, 59), 900);
      final september = await session(DateTime(2026, 9, 1), 2000);
      await records.save(record('2026-08-01', weight: 71));
      await records.save(record('2026-08-31', weight: 69));
      await records.save(record('2026-09-01', weight: 68));
      await db.update(
        'exercise_sessions',
        {'elapsedSeconds': 1200},
        where: 'id = ?',
        whereArgs: [august.id],
      );
      final previous = await portfolio.load(
        PortfolioPeriod.month,
        now,
        anchor: DateTime(2026, 8),
      );
      expect(previous.summary.count, 1);
      expect(previous.weightChange, -2);
      expect(previous.periodEnd, DateTime(2026, 8, 31));
      expect(previous.longestTime!.id, august.id);
      final year = await portfolio.load(PortfolioPeriod.year, now);
      expect(year.bestAverage!.id, september.id);
      expect(year.longestTime!.id, august.id);
      expect(year.recent.map((s) => s.id), [september.id, august.id]);
      final old = await portfolio.load(
        PortfolioPeriod.year,
        now,
        anchor: DateTime(2025),
      );
      expect(old.summary.count, 1);
      expect(old.months, hasLength(12));
      final empty = await portfolio.load(
        PortfolioPeriod.month,
        now,
        anchor: DateTime(2026, 2),
      );
      expect(empty.summary.count, 0);
      expect(empty.periodEnd, DateTime(2026, 2, 28));
    });

    test('local calendar boundaries, unknown kcal, zero months, and no manual double counting', () async {
      await session(DateTime(2025, 12, 31, 23, 59, 59), 500);
      await session(DateTime(2026), 1000);
      await session(DateTime(2026, 8, 12, 23, 59, 59), 2000);
      await session(DateTime(2026, 8, 13), 3000, weight: 70);
      await session(DateTime(2026, 9, 11, 23, 59, 59), 4000);
      await session(DateTime(2026, 9, 12), 99999);
      await exercises.start(
        ExerciseType.running,
        70,
        now,
      ); // Unfinished is excluded.
      await records.save(record('2026-08-13', weight: 70));
      await records.save(record('2026-09-11', weight: 68));
      final recent = await portfolio.load(PortfolioPeriod.recent, now);
      expect(recent.summary.count, 2);
      expect(recent.summary.meters, 7000);
      expect(recent.summary.seconds, 1200);
      expect(recent.summary.calorieCount, 1);
      expect(recent.summary.calories, closeTo(34.3, .01));
      expect(recent.weightChange, -2);
      expect(recent.months.map((m) => m.summary.count), [1, 1]);
      expect(recent.longest!.distanceMeters, 4000);
      expect(recent.route, isEmpty);
      final year = await portfolio.load(PortfolioPeriod.year, now);
      expect(year.summary.count, 4);
      expect(year.months, hasLength(9));
      expect(
        year.months.firstWhere((m) => m.month.month == 2).summary.count,
        0,
      );
      expect((await portfolio.load(PortfolioPeriod.all, now)).summary.count, 5);
    });

    test('fastest uses reanalyzed raw geometry, legacy fallback and deletion refresh', () async {
      RoutePoint p(DateTime date, int seconds, double delta) => RoutePoint(
        latitude: 37 + delta,
        longitude: 127,
        timestamp: date.add(Duration(seconds: seconds)),
        accuracy: 5,
        rawSpeed: 99,
      );
      final legacyDate = DateTime(2026, 9, 1);
      final old = await exercises.start(
        ExerciseType.lightWalk,
        null,
        legacyDate,
      );
      await exercises.checkpoint(old, point: p(legacyDate, 0, 0));
      await exercises.checkpoint(old, point: p(legacyDate, 6, .00006));
      await exercises.checkpoint(
        old.copyWith(
          status: SessionStatus.finished,
          distanceMeters: 100,
          elapsedSeconds: 50,
        ),
      );
      final date = DateTime(2026, 9, 2);
      final raw = await exercises.start(ExerciseType.lightWalk, null, date);
      await exercises.checkpoint(
        raw,
        point: p(date, 0, 0),
        rawPoint: p(date, 0, 0),
      );
      await exercises.checkpoint(
        raw,
        rawPoint: p(date, 2, 1),
        decision: 'implausible_speed',
      );
      await exercises.checkpoint(
        raw,
        point: p(date, 6, .00006),
        rawPoint: p(date, 6, .00012),
        receivedAt: date.add(const Duration(seconds: 6)),
      );
      await exercises.checkpoint(
        raw,
        rawPoint: p(date, 12, .00024),
        receivedAt: date.add(const Duration(seconds: 12)),
      );
      await exercises.checkpoint(
        raw,
        rawPoint: p(date, 18, .00036),
        receivedAt: date.add(const Duration(seconds: 18)),
      );
      await exercises.checkpoint(
        raw.copyWith(
          status: SessionStatus.finished,
          distanceMeters: 200,
          elapsedSeconds: 100,
        ),
      );
      final data = await portfolio.load(PortfolioPeriod.recent, now);
      expect(data.fastestSession!.id, raw.id);
      expect(data.fastest!.kmh, closeTo(8, .02));
      expect(data.fastest!.seconds, 6);
      expect(data.representative!.id, raw.id);
      expect(data.route, isNotEmpty);
      expect(await exercises.rawRoute(raw.id), hasLength(5));
      await exercises.deleteFinished(raw.id);
      final after = await portfolio.load(PortfolioPeriod.recent, now);
      expect(after.summary.count, 1);
      expect(after.fastestSession!.id, old.id);
      expect(after.fastest!.kmh, closeTo(4, .02));
    });

    test('weights alone and entirely empty data remain useful', () async {
      final empty = await portfolio.load(PortfolioPeriod.all, now);
      expect(empty.summary.count, 0);
      expect(empty.summary.calories, isNull);
      expect(empty.fastest, isNull);
      expect(empty.weightChange, isNull);
      await records.save(record('2026-09-11'));
      final weights = await portfolio.load(PortfolioPeriod.recent, now);
      expect(weights.weights, hasLength(1));
      expect(weights.weightChange, isNull);
      expect(weights.summary.count, 0);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'portfolio periods, populated summary, retry and large type in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final exercises = PortfolioExercises(), records = MemoryRecords();
        final now = DateTime.now();
        final oldDate = DateTime(now.year - 1, 12, 1);
        exercises.sessions.addAll([
          ExerciseSession(
            id: 1,
            startedAt: now,
            updatedAt: now,
            type: ExerciseType.lightWalk,
            status: SessionStatus.finished,
            distanceMeters: 1500,
            elapsedSeconds: 900,
          ),
          ExerciseSession(
            id: 2,
            startedAt: oldDate,
            updatedAt: oldDate,
            type: ExerciseType.lightWalk,
            status: SessionStatus.finished,
            distanceMeters: 500,
            elapsedSeconds: 600,
          ),
        ]);
        await records.save(record(dateKey(now)));
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: TrendsScreen(
                repository: records,
                exercises: exercises,
                revision: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('1회'), 200);
        expect(find.text('1회'), findsOneWidget);
        expect(find.text('1.50 km'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('전체'));
        await tester.tap(find.text('전체'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('2회'), 200);
        expect(find.text('2회'), findsOneWidget);
        expect(find.text('2.00 km'), findsOneWidget);
        await tester.ensureVisible(find.text('연간'));
        await tester.tap(find.text('연간'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('1회'), 200);
        expect(find.text('1회'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('가장 멀리 간 운동'), 350);
        expect(tester.takeException(), isNull);
        exercises.fail = true;
        await tester.ensureVisible(find.text('최근 30일'));
        await tester.tap(find.text('최근 30일'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('포트폴리오를 불러오지 못했어요.'), 200);
        expect(find.text('포트폴리오를 불러오지 못했어요.'), findsOneWidget);
        exercises.fail = false;
        await tester.ensureVisible(find.text('다시 시도'));
        await tester.tap(find.text('다시 시도'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('1회'), 200);
        expect(find.text('1회'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
