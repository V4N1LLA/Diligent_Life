import 'package:diligent_life/theme/app_theme.dart';
import 'package:diligent_life/widgets/exercise_route.dart';
import 'package:diligent_life/widgets/movement_analysis_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exercise_map_test.dart' show TestTiles;
import 'movement_analysis_test.dart' show analyze, fix, session;

void main() {
  final data = analyze([
    for (var i = 0; i <= 120; i++)
      fix(
        i,
        i <= 30
            ? 0
            : i <= 90
            ? (i - 30) * 1.4
            : 84,
      ),
  ]);
  for (final brightness in Brightness.values) {
    testWidgets('analysis fits narrow screen with large text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? forced;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: MovementAnalysisPanel(
                session: session(120),
                tileProvider: TestTiles(),
                load: (force) async {
                  forced = force;
                  return data;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(forced, false);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('원본으로 다시 계산'), 250);
      await tester.tap(find.text('원본으로 다시 계산'));
      await tester.pumpAndSettle();
      expect(forced, true);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'chart selects identical colored map section and centers its location',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: MovementAnalysisPanel(
                session: session(120),
                tileProvider: TestTiles(),
                load: (_) async => data,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chart = find.byKey(const ValueKey('movement-speed-chart'));
      final rect = tester.getRect(chart);
      await tester.tapAt(Offset(rect.left + rect.width * .53, rect.center.dy));
      await tester.pumpAndSettle();
      final map = tester.widget<ExerciseRoute>(find.byType(ExerciseRoute));
      expect(map.selectedSection, isNotNull);
      expect(map.selectedSection!.kmh, closeTo(5.04, .01));
      expect(map.selectedPoint, map.selectedSection!.points.first);
      final selected = map.selectedPoint!;
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      expect(
        controller.camera.center.latitude,
        closeTo(selected.latitude, 1e-6),
      );
      expect(find.textContaining('구간 페이스'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing GPS and failed analysis have useful empty and retry states',
    (tester) async {
      var failed = true;
      final empty = analyze([fix(0, 0)], elapsed: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MovementAnalysisPanel(
                session: session(0),
                load: (_) async {
                  if (failed) {
                    throw StateError('read failed');
                  }
                  return empty;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('분석을 불러오지 못했어요. 다시 계산해 주세요.'), findsOneWidget);
      failed = false;
      await tester.tap(find.text('원본으로 다시 계산'));
      await tester.pumpAndSettle();
      expect(find.text('분석할 연속 GPS가 아직 부족해요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
