import 'dart:convert';
import 'dart:io';

import 'package:diligent_life/models/activity_report.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/utils/movement_analysis.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import 'movement_analysis_test.dart' as fixture;

void main() {
  test(
    'stationary anchor resets do not invent outages; actual pauses stay split',
    () {
      final points = [
        for (var i = 0; i <= 140; i += 7)
          fixture.fix(i, i.isEven ? .1 : -.1, segment: i ~/ 35, speed: 0),
      ];
      final result = fixture.analyze(points);
      expect(result.movingSeconds, 0);
      expect(result.stoppedSeconds, 140);
      expect(result.unknownSeconds, 0);
      expect(result.stopCount, 1);
      expect(result.longestStop, 140);
      final paused = fixture.analyze(points, elapsed: 130);
      expect(paused.longestStop, lessThan(140));
      expect(
        paused.movingSeconds + paused.stoppedSeconds,
        lessThanOrEqualTo(130),
      );
    },
  );

  test(
    'sensor/coordinate disagreement never earns a record or an invented stop',
    () {
      final jump = fixture.analyze([
        for (var i = 0; i <= 120; i++) fixture.fix(i, i * 2.4, speed: 1.2),
      ]);
      expect(jump.meters, greaterThan(200));
      expect(jump.fastest, isNull);
      expect(jump.bests, isEmpty);
      expect(jump.lowConfidenceSections, greaterThan(0));
      final frozen = fixture.analyze([
        for (var i = 0; i <= 120; i++) fixture.fix(i, 0, speed: 1.4),
      ]);
      expect(frozen.stoppedSeconds, 0);
      expect(frozen.movingSeconds, 0);
      expect(frozen.unknownSeconds, 120);
      final noSensor = fixture.analyze([
        for (var i = 0; i <= 120; i++) fixture.fix(i, i * 1.4, speed: null),
      ]);
      expect(noSensor.meters, closeTo(168, .01));
      expect(noSensor.fastest, isNull);
      expect(noSensor.bests, isEmpty);
    },
  );

  test('splits conserve distance/time, interpolate boundaries and flag interruptions', () {
    final sections = [
      MovementSection(
        [fixture.fix(0, 0), fixture.fix(300, 600)],
        600,
        MovementKind.moving,
      ),
      MovementSection(
        [fixture.fix(300, 600), fixture.fix(330, 600)],
        0,
        MovementKind.stopped,
      ),
      MovementSection(
        [fixture.fix(330, 600, segment: 1), fixture.fix(780, 1500, segment: 1)],
        900,
        MovementKind.moving,
      ),
    ];
    final laps = movementLaps(sections, 500);
    expect(laps, hasLength(3));
    expect(laps.map((s) => s.seconds), everyElement(closeTo(250, .001)));
    expect(laps.map((s) => s.meters), everyElement(closeTo(500, .001)));
    expect(laps[1].interrupted, isTrue);
    final halves = movementLaps(sections, 750);
    expect(halves, hasLength(2));
    expect(halves.map((s) => s.seconds), everyElement(closeTo(375, .001)));
    final km = movementLaps(sections, 1000);
    expect(km.last.partial, isTrue);
    expect(km.last.meters, closeTo(500, .001));
  });

  test(
    'sub-error personal record changes are not improvements for any target',
    () {
      for (final target in [100, 500, 1000]) {
        ReportEntry entry(int id, double seconds) {
          final date = fixture.epoch.add(Duration(days: id));
          final s = fixture.session(1200).copyWith(updatedAt: date);
          final session = ExerciseSession(
            id: id,
            startedAt: date,
            updatedAt: date,
            type: s.type,
            elapsedSeconds: 1200,
            distanceMeters: 1500,
            endedAt: date.add(const Duration(seconds: 1200)),
            status: SessionStatus.finished,
          );
          final best = DistanceBest(
            target,
            fixture.fix(0, 0),
            RoutePoint(
              latitude: target / 111194.92664455874,
              longitude: 127,
              accuracy: 5,
              timestamp: fixture.epoch.add(
                Duration(microseconds: (seconds * 1e6).round()),
              ),
            ),
          );
          return ReportEntry(
            session,
            PortfolioAnalysis(
              const [],
              null,
              movement: MovementAnalysis(
                sections: const [],
                bests: [best],
                elapsedSeconds: 1200,
                rawAvailable: true,
                rejectedSamples: 0,
              ),
            ),
          );
        }

        final base = target * .66;
        final report = buildActivityReport(
          ReportWindow(
            ReportPeriod.month,
            fixture.epoch,
            fixture.epoch.add(const Duration(days: 10)),
          ),
          [entry(1, base), entry(2, base - .15), entry(3, base * .8)],
          [],
        );
        final gains = report.improvements
            .where((r) => r.label.endsWith('${target}m'))
            .toList();
        expect(gains, hasLength(1));
        expect(gains.single.entry.session.id, 3);
      }
    },
  );

  final source = Platform.environment['S26_REGRESSION_DATA'];
  test(
    'S26 exported sessions: reliability regression without changing source rows',
    () {
      final file = File(source!);
      final original = file.readAsStringSync();
      final data = jsonDecode(original) as Map<String, dynamic>;
      final results = <int, MovementAnalysis>{};
      final entries = <ReportEntry>[];
      for (final row in data['exercise_sessions'] as List) {
        final s = ExerciseSession.fromMap(Map<String, Object?>.from(row));
        final raw = (data['raw_route_points'] as List)
            .where((r) => r['sessionId'] == s.id)
            .toList();
        final rows = raw.isNotEmpty
            ? raw
            : (data['route_points'] as List).where(
                (r) => r['sessionId'] == s.id,
              );
        final analyzer = MovementAnalyzer(s, rawAvailable: raw.isNotEmpty);
        for (final r in rows) {
          analyzer.addRow(Map<String, Object?>.from(r));
        }
        final result = analyzer.finish();
        results[s.id] = result;
        entries.add(
          ReportEntry(
            s,
            PortfolioAnalysis(
              result.route,
              result.fastest?.speed,
              movement: result,
            ),
          ),
        );
        expect(
          result.movingSeconds + result.stoppedSeconds + result.unknownSeconds,
          closeTo(s.elapsedSeconds, .001),
        );
        expect(result.rejectedSamples, lessThanOrEqualTo(result.sampleCount));
        expect(
          result.speedDistribution.reduce((a, b) => a + b),
          closeTo(result.movingSeconds, .001),
        );
        for (final target in [500, 1000]) {
          final splits = result.splits.where((s) => s.targetMeters == target);
          expect(
            splits.fold<double>(0, (v, s) => v + s.meters),
            closeTo(result.meters, .001),
          );
          expect(
            splits.fold<double>(0, (v, s) => v + s.seconds),
            closeTo(result.movingSeconds, .001),
          );
        }
      }
      final latest = results[13]!;
      expect(latest.sampleCount, 1879);
      expect(latest.fastest!.kmh, inInclusiveRange(4, 6.1));
      expect(latest.unknownSeconds / latest.elapsedSeconds, lessThan(.08));
      expect(latest.movingSeconds, lessThanOrEqualTo(2180.302));
      expect(latest.meters, closeTo(2414.2759, .1));
      expect(latest.bests.map((b) => b.meters), [100, 500]);
      expect(latest.bests.first.seconds, closeTo(70.16014, .01));
      expect(
        latest.bests.first.points.first.timestamp,
        latest.bests.first.start.timestamp,
      );
      expect(
        latest.bests.first.points.last.timestamp,
        latest.bests.first.end.timestamp,
      );
      final report = buildActivityReport(
        ReportWindow(
          ReportPeriod.month,
          DateTime(2026, 9, 21),
          DateTime(2026, 9, 21),
        ),
        entries,
        [],
      );
      expect(report.current.meters, closeTo(16489.71938, .001));
      expect(report.current.seconds, 29799);
      expect(
        report.improvements.where(
          (r) => r.entry.session.id == 13 && r.label.endsWith('100m'),
        ),
        isEmpty,
      );
      expect(file.readAsStringSync(), original);
      expect(jsonEncode(data), jsonEncode(jsonDecode(original)));
      // No coordinates or identifying timestamps in the regression output.
      stdout.writeln(
        'S26 regression: stored=2584.6326 analyzed=${latest.meters.toStringAsFixed(4)} '
        'peak=${latest.fastest!.kmh.toStringAsFixed(4)} unknown=${latest.unknownSeconds.toStringAsFixed(3)} '
        'moving=${latest.movingSeconds.toStringAsFixed(3)} stopped=${latest.stoppedSeconds.toStringAsFixed(3)}',
      );
    },
    skip: source == null
        ? 'Set S26_REGRESSION_DATA to the private exported data.json copy.'
        : false,
  );
}
