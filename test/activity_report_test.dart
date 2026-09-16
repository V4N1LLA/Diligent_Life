import 'dart:ui' as ui;

import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/data/report_repository.dart';
import 'package:diligent_life/models/activity_report.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/services/report_share.dart';
import 'package:diligent_life/utils/movement_analysis.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'record_repository_test.dart' show record;

ReportEntry entry(
  int id,
  DateTime date, {
  double meters = 1000,
  int seconds = 600,
  ExerciseType type = ExerciseType.lightWalk,
  double? weight = 70,
  double latitude = 37,
  bool reverse = false,
}) {
  final s = ExerciseSession(
    id: id,
    startedAt: date,
    updatedAt: date,
    endedAt: date.add(Duration(seconds: seconds)),
    elapsedSeconds: seconds,
    distanceMeters: meters,
    type: type,
    weightKg: weight,
    status: SessionStatus.finished,
  );
  final points = [
    for (var i = 0; i < 64; i++)
      RoutePoint(
        latitude: latitude + (reverse ? 63 - i : i) * .0002,
        longitude: 127,
        timestamp: date.add(Duration(seconds: seconds * i ~/ 63)),
        accuracy: 5,
      ),
  ];
  return ReportEntry(
    s,
    PortfolioAnalysis(
      points,
      null,
      movement: MovementAnalysis(
        sections: [MovementSection(points, meters, MovementKind.moving)],
        bests: const [],
        elapsedSeconds: seconds,
        rawAvailable: true,
        rejectedSamples: 0,
      ),
    ),
  );
}

void main() {
  test('week starts Monday across year; partial month and leap year comparisons use calendar dates', () {
    final week = ReportWindow(
      ReportPeriod.week,
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 1, 12),
    );
    expect(week.start, DateTime(2025, 12, 29));
    expect(week.previousStart, DateTime(2025, 12, 22));
    expect(week.previousBefore, DateTime(2025, 12, 26));
    final month = ReportWindow(
      ReportPeriod.month,
      DateTime(2026, 3, 31),
      DateTime(2026, 3, 31),
    );
    expect(month.before, DateTime(2026, 4));
    expect(month.previousBefore, DateTime(2026, 3));
    final partial = ReportWindow(
      ReportPeriod.month,
      DateTime(2026, 9, 15),
      DateTime(2026, 9, 15),
    );
    expect(partial.previousBefore, DateTime(2026, 8, 16));
    final leap = ReportWindow(
      ReportPeriod.year,
      DateTime(2024, 2, 29),
      DateTime(2024, 2, 29),
    );
    expect(
      leap.previousBefore,
      DateTime(2023, 3, 2),
    ); // Same 60 elapsed calendar days.
    expect(
      () => ReportWindow(ReportPeriod.month, DateTime(2027), DateTime(2026)),
      throwsArgumentError,
    );
  });
  test('comparison excludes later prior-period days and future records; missing kcal stays unknown', () {
    final w = ReportWindow(
      ReportPeriod.month,
      DateTime(2026, 9, 15),
      DateTime(2026, 9, 15),
    );
    final d = buildActivityReport(w, [
      entry(1, DateTime(2026, 8, 1)),
      entry(2, DateTime(2026, 8, 2)),
      entry(3, DateTime(2026, 8, 20), meters: 99999),
      entry(4, DateTime(2026, 9, 1), meters: 1180),
      entry(5, DateTime(2026, 9, 2), meters: 1180, weight: null),
      entry(6, DateTime(2026, 9, 16), meters: 999999),
    ], []);
    expect(d.current.meters, 2360);
    expect(d.previous.meters, 2000);
    expect(d.insight, contains('18% 증가'));
    expect(d.current.calorieCount, 1);
    expect(d.delta(1, 0), contains('계산 불가'));
    expect(d.delta(1, 2, available: false), '데이터 부족');
    expect(d.records.firstWhere((r) => r.label == '최장 거리').entry.session.id, 3);
    expect(d.representative!.session.id, 4);
  });
  test(
    'empty / single records do not invent comparisons, patterns or improvement',
    () {
      final w = ReportWindow(
        ReportPeriod.week,
        DateTime(2026, 9, 15),
        DateTime(2026, 9, 15),
      );
      final empty = buildActivityReport(w, [], []);
      expect(empty.insight, contains('데이터 부족'));
      expect(empty.records, isEmpty);
      final one = buildActivityReport(
        w,
        [entry(1, DateTime(2026, 9, 14))],
        [record('2026-09-14', weight: 70)],
      );
      expect(one.insight, contains('데이터 부족'));
      expect(one.pattern, contains('데이터 부족'));
      expect(one.weightChange, isNull);
      expect(one.improvements, isEmpty);
      expect(one.speeds.single.current, isNull);
    },
  );
  test('speed is time-weighted and stratified; four completed weeks need two observations each', () {
    final w = ReportWindow(
      ReportPeriod.month,
      DateTime(2026, 9, 28),
      DateTime(2026, 9, 28),
    );
    final history = <ReportEntry>[];
    var id = 0;
    for (var week = 0; week < 4; week++) {
      for (var day = 0; day < 2; day++) {
        history.add(
          entry(
            ++id,
            DateTime(2026, 8, 31 + week * 7 + day),
            meters: 1000 + week * 100,
          ),
        );
      }
    }
    history.add(
      entry(
        ++id,
        DateTime(2026, 9, 10),
        meters: 3000,
        type: ExerciseType.running,
      ),
    );
    final d = buildActivityReport(w, history, []);
    final walk = d.speeds.firstWhere((s) => s.type == ExerciseType.lightWalk);
    expect(walk.weeks, [6, 6.6, 7.2, 7.8]);
    expect(walk.increasing, isTrue);
    expect(
      d.speeds.firstWhere((s) => s.type == ExerciseType.running).current,
      isNull,
    );
    final sparse = buildActivityReport(w, history.skip(1).toList(), []);
    expect(
      sparse.speeds
          .firstWhere((s) => s.type == ExerciseType.lightWalk)
          .increasing,
      isFalse,
    );
    final weighted = buildActivityReport(w, [
      entry(1, DateTime(2026, 9, 1), meters: 1000, seconds: 600),
      entry(2, DateTime(2026, 9, 2), meters: 1000, seconds: 1200),
    ], []);
    expect(weighted.speeds.single.current, 4);
  });
  test('weights have explicit gaps, bucket means and no causal statement', () {
    final w = ReportWindow(
      ReportPeriod.month,
      DateTime(2026, 9, 30),
      DateTime(2026, 10, 1),
    );
    final d = buildActivityReport(
      w,
      [entry(1, DateTime(2026, 9, 1))],
      [
        record('2026-08-31', weight: 100),
        record('2026-09-01', weight: 71),
        record('2026-09-02', weight: 69),
        record('2026-09-29', weight: 68),
      ],
    );
    expect(d.weights.length, 3);
    expect(d.weightChange, -3);
    expect(d.buckets.first.meanWeight, 70);
    expect(d.buckets[1].meanWeight, isNull);
    expect(d.buckets.last.meanWeight, 68);
    expect(d.buckets.first.summary.meters, 1000);
  });
  test(
    'weekday/time marginal modes are not falsely combined into a joint mode',
    () {
      final w = ReportWindow(
        ReportPeriod.month,
        DateTime(2026, 9),
        DateTime(2026, 10),
      );
      final d = buildActivityReport(w, [
        entry(1, DateTime(2026, 9, 1, 19)),
        entry(2, DateTime(2026, 9, 8, 19)),
        entry(3, DateTime(2026, 9, 15, 19)),
        entry(4, DateTime(2026, 9, 2, 8)),
      ], []);
      expect(d.pattern, contains('화요일 저녁'));
      expect(d.pattern, contains('3회'));
      final tied = buildActivityReport(w, [
        entry(1, DateTime(2026, 9, 1, 19)),
        entry(2, DateTime(2026, 9, 8, 8)),
        entry(3, DateTime(2026, 9, 2, 19)),
        entry(4, DateTime(2026, 9, 3, 8)),
      ], []);
      expect(tied.pattern, isNot(contains('에 가장 자주 운동했습니다')));
    },
  );
  test(
    'similar routes match reversed traces, reject different places and lengths',
    () {
      final routes = frequentRoutes([
        entry(1, DateTime(2026, 9, 1)),
        entry(2, DateTime(2026, 9, 2), reverse: true),
        entry(3, DateTime(2026, 9, 3), latitude: 38),
        entry(4, DateTime(2026, 9, 4), meters: 3000),
      ]);
      expect(routes.length, 1);
      expect(routes.single.entries.map((e) => e.session.id), [1, 2]);
      expect(frequentRoutes([entry(5, DateTime(2026), meters: 50)]), isEmpty);
    },
  );
  test('records and recent improvements are chronological and period representative is deterministic', () {
    final w = ReportWindow(
      ReportPeriod.month,
      DateTime(2026, 9),
      DateTime(2026, 10),
    );
    final d = buildActivityReport(w, [
      entry(3, DateTime(2026, 9, 3), meters: 1500),
      entry(1, DateTime(2026, 8, 1)),
      entry(2, DateTime(2026, 9, 2), meters: 1200),
      entry(4, DateTime(2026, 10, 1), meters: 9000),
    ], []);
    expect(d.records.firstWhere((r) => r.label == '최장 거리').value, 1.5);
    expect(
      d.improvements.where((r) => r.label == '최장 거리').map((r) => r.previous),
      [1.2, 1.0],
    );
    expect(d.representative!.session.id, 3);
  });
  test(
    'SQLite report cache refresh preserves all originals and reflects deletion',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: RecordRepository.createSchema,
        ),
      );
      addTearDown(db.close);
      final exercises = ExerciseRepository(db), records = RecordRepository(db);
      final repository = ReportRepository(records, exercises);
      final s = entry(1, DateTime(2026, 9, 1)).session;
      await db.insert('exercise_sessions', s.toMap());
      await records.save(record('2026-09-01', weight: 71));
      final original = await db.query('exercise_sessions');
      final a = await repository.load(
        ReportPeriod.month,
        DateTime(2026, 9),
        DateTime(2026, 10),
      );
      expect(a.current.count, 1);
      expect(a.speeds, isEmpty);
      expect(await db.query('exercise_sessions'), original);
      await exercises.deleteFinished(s.id);
      repository.invalidate();
      expect(
        (await repository.load(
          ReportPeriod.month,
          DateTime(2026, 9),
          DateTime(2026, 10),
        )).current.count,
        0,
      );
    },
  );
  for (final period in ReportPeriod.values) {
    testWidgets(
      '${period.name} report card decodes with empty and populated data',
      (tester) async {
        for (final populated in [false, true]) {
          final d = buildActivityReport(
            ReportWindow(period, DateTime(2026, 9, 15), DateTime(2026, 9, 15)),
            populated
                ? [
                    entry(1, DateTime(2026, 9, 14)),
                    entry(2, DateTime(2026, 9, 15)),
                  ]
                : [],
            [],
          );
          await tester.runAsync(() async {
            final bytes = await reportShareImage(d);
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            expect(frame.image.width, 900);
            expect(frame.image.height, greaterThanOrEqualTo(1200));
            frame.image.dispose();
            codec.dispose();
          });
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
