import 'dart:ui' as ui;

import 'package:diligent_life/data/portfolio_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/services/portfolio_share.dart';
import 'package:diligent_life/utils/gps.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';
import 'package:diligent_life/widgets/exercise_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exercise_map_test.dart' show TestTiles;
import 'record_repository_test.dart' show record;
import 'support/legacy_portfolio_analyzer.dart';

void main() {
  test('streamed fastest matches raw windows across pages, pauses and speed outliers', () {
    final points = [
      for (var i = 0; i < 12005; i++)
        RoutePoint(
          latitude: 37 + i * .00001,
          longitude: 127,
          timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: 2 * i)),
          accuracy: 5,
          segment: i < 6000 ? 0 : 1,
        ),
    ];
    final analyzer = PortfolioAnalyzer(stride: 21, maxKmh: 12.6);
    for (final p in points) {
      analyzer.add(p);
    }
    final result = analyzer.finish();
    final expected = speedSections(points)
        .reduce((a, b) => a.kmh >= b.kmh ? a : b);
    expect(result.fastest!.kmh, closeTo(expected.kmh, 1e-9));
    expect(
      result.fastest!.points.first.timestamp,
      expected.points.first.timestamp,
    );
    expect(result.route.length, lessThan(610));
    expect(result.route.first.timestamp, points.first.timestamp);
    expect(result.route.last.timestamp, points.last.timestamp);
    expect(
      result.route.where(
        (p) =>
            p.timestamp == points[5999].timestamp ||
            p.timestamp == points[6000].timestamp,
      ),
      hasLength(2),
    );
    final overview = sampleOverviewRoute(result.route, 20);
    expect(overview.first.timestamp, points.first.timestamp);
    expect(overview.last.timestamp, points.last.timestamp);
    expect(
      overview.where(
        (p) =>
            p.timestamp == points[5999].timestamp ||
            p.timestamp == points[6000].timestamp,
      ),
      hasLength(2),
    );
    expect(points, hasLength(12005));
    final restored = PortfolioAnalysis.fromMap(result.toMap());
    expect(restored.fastest!.seconds, result.fastest!.seconds);
    expect(restored.route.length, result.route.length);
  });

  test(
    'average record excludes zero time, tiny distance and implausible speeds',
    () {
      ExerciseSession session(double meters, int seconds) => ExerciseSession(
        id: 1,
        startedAt: DateTime(2026),
        updatedAt: DateTime(2026),
        type: ExerciseType.lightWalk,
        distanceMeters: meters,
        elapsedSeconds: seconds,
      );
      expect(averageKmh(session(1000, 600)), 6);
      expect(averageKmh(session(1000, 0)), isNull);
      expect(averageKmh(session(2, 600)), isNull);
      expect(averageKmh(session(1000, 10)), isNull);
    },
  );

  testWidgets(
    'overview map keeps separate polylines, has no false start/end and no speed overlays',
    (tester) async {
      final p = [
        for (var i = 0; i < 4; i++)
          RoutePoint(
            latitude: 37 + i * .0001,
            longitude: 127,
            timestamp: DateTime.utc(2026).add(Duration(seconds: i * 5)),
            accuracy: 5,
            segment: i < 2 ? 1 : 2,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseRoute(
              points: p,
              overview: true,
              tileProvider: TestTiles(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
        hasLength(2),
      );
      expect(find.byTooltip('시작'), findsNothing);
      expect(find.byTooltip('도착'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'monthly/yearly cards generate 900x1200 PNG for empty and measured history',
    (tester) async {
      for (final populated in [false, true]) {
        final data = PortfolioData(
          summary: MovementSummary(
            populated ? 12 : 0,
            populated ? 45678 : 0,
            123456,
            populated ? 3200 : null,
            populated ? 10 : 0,
          ),
          weights: populated
              ? [
                  record('2026-01-01', weight: 71),
                  record('2026-08-31', weight: 68),
                ]
              : [],
          months: [
            for (var i = 1; i <= 12; i++)
              PortfolioMonth(
                DateTime(2026, i),
                MovementSummary(i, i * 1500, i * 900, null, 0),
              ),
          ],
          periodStart: DateTime(2026),
          periodEnd: DateTime(2026, 12, 31),
        );
        await tester.runAsync(() async {
          final bytes = await portfolioShareImage(data, '2026년');
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 900);
          expect(frame.image.height, 1200);
          frame.image.dispose();
          codec.dispose();
        });
      }
    },
  );
}
