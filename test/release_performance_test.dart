import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/data/portfolio_repository.dart';
import 'package:diligent_life/data/report_repository.dart';
import 'package:diligent_life/models/activity_report.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('48024 raw fixes: cold/warm portfolio, report and All-time Map preparation preserve originals', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 3,
        onCreate: RecordRepository.createSchema,
      ),
    );
    addTearDown(db.close);
    final exercises = ExerciseRepository(db);
    final records = RecordRepository(db);
    for (var n = 0; n < 24; n++) {
      final start = DateTime(2026, 9, 1, 8).add(Duration(hours: n * 12));
      final s = await exercises.start(ExerciseType.lightWalk, 70, start);
      final batch = db.batch();
      for (var i = 0; i <= 2000; i++) {
        final p = RoutePoint(
          latitude: 37 + i * 1.4 / 111195,
          longitude: 127 + n * .001,
          timestamp: start.add(Duration(seconds: i)),
          accuracy: 4,
          rawSpeed: 1.4,
        );
        batch.insert('raw_route_points', {
          ...p.toMap(s.id),
          'receivedAt': p.timestamp.toIso8601String(),
          'decision': 'accepted',
          'filterVersion': 2,
        });
      }
      await batch.commit(noResult: true);
      await exercises.checkpoint(
        s.copyWith(
          status: SessionStatus.finished,
          elapsedSeconds: 2000,
          distanceMeters: 2800,
          endedAt: start.add(const Duration(seconds: 2000)),
        ),
      );
    }
    final original = await db.query('raw_route_points', orderBy: 'id');
    final sessionsBefore = await db.query('exercise_sessions', orderBy: 'id');
    final now = DateTime(2026, 9, 22);
    final timings = <String, int>{};
    final clock = Stopwatch()..start();
    final portfolio = PortfolioRepository(records, exercises);
    final cold = await portfolio.load(PortfolioPeriod.all, now);
    timings['portfolioColdMs'] = clock.elapsedMilliseconds;
    clock.reset();
    final warm = await portfolio.load(PortfolioPeriod.all, now);
    timings['portfolioWarmMs'] = clock.elapsedMilliseconds;
    expect(cold.summary.count, 24);
    expect(warm.summary.meters, cold.summary.meters);
    expect(warm.summary.meters, 67200);
    clock.reset();
    final reports = ReportRepository(records, exercises);
    final report = await reports.load(ReportPeriod.month, now, now);
    timings['reportColdMs'] = clock.elapsedMilliseconds;
    clock.reset();
    final cached = await reports.load(ReportPeriod.month, now, now);
    timings['reportWarmMs'] = clock.elapsedMilliseconds;
    expect(report.current.count, 24);
    expect(cached.current.meters, report.current.meters);
    clock.reset();
    final sessions = await exercises.finishedBetween(before: now);
    var mapCount = 0;
    for (final s in sessions) {
      final a = await exercises.portfolioAnalysis(s);
      final route = sampleOverviewRoute(
        a.route,
        (50000 / sessions.length).floor().clamp(2, 600),
      );
      expect(route, isNotEmpty);
      mapCount += route.length;
    }
    timings['allTimeMapPreparationMs'] = clock.elapsedMilliseconds;
    expect(mapCount, lessThanOrEqualTo(24 * 600));
    // Generous CI guard against hangs/quadratic regressions, not a frame-rate benchmark.
    for (final ms in timings.values) {
      expect(ms, lessThan(30000));
    }
    expect(await db.query('raw_route_points', orderBy: 'id'), original);
    expect(await db.query('exercise_sessions', orderBy: 'id'), sessionsBefore);
    // ignore: avoid_print
    print(
      'RC synthetic performance (48024 fixes): $timings; mapPoints=$mapCount',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
