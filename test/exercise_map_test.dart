import 'dart:convert';
import 'dart:ui' as ui;

import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/widgets/exercise_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exercise_test.dart' show point;

class TestTiles extends TileProvider {
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
    ),
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

void main() {
  testWidgets('offline map tile is a decodable 1x1 PNG', (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(TestTiles().image.bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 1);
          expect(frame.image.height, 1);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'live map follows fixes; gesture suspends follow; button restores it',
    (tester) async {
      final tiles = TestTiles();
      final first = point(37, 0);
      final second = point(37.0001, 6);
      Widget host(List<RoutePoint> points) => MaterialApp(
        home: Scaffold(
          body: ExerciseRoute(
            points: points,
            currentPosition: points.last,
            live: true,
            tileProvider: tiles,
          ),
        ),
      );
      await tester.pumpWidget(host([first]));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host([first, second]));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      expect(
        controller.camera.center.latitude,
        closeTo(second.latitude, .000001),
      );
      await tester.drag(find.byType(FlutterMap), const Offset(120, 0));
      await tester.pumpAndSettle();
      final browsed = controller.camera.center;
      final third = point(37.0002, 12);
      await tester.pumpWidget(host([first, second, third]));
      await tester.pumpAndSettle();
      expect(controller.camera.center, browsed);
      await tester.tap(find.byTooltip('현재 위치 따라가기'));
      await tester.pumpAndSettle();
      expect(
        controller.camera.center.latitude,
        closeTo(third.latitude, .000001),
      );
      expect(find.byTooltip('최근 수신 위치'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail map fits route, exposes endpoints and never bridges pauses',
    (tester) async {
      final points = [
        point(37, 0),
        point(37.0001, 6),
        point(37.001, 20, segment: 1),
        point(37.0011, 26, segment: 1),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseRoute(points: points, tileProvider: TestTiles()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('시작'), findsOneWidget);
      expect(find.byTooltip('도착'), findsOneWidget);
      final lines = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines;
      expect(lines.every((line) => line.points.length == 2), isTrue);
      final camera = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .camera;
      for (final p in points) {
        expect(camera.visibleBounds.contains(routeLocation(p)), isTrue);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fully private route never requests map tiles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ExerciseRoute(points: [], private: true)),
    );
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('위치 보호를 위해 경로를 모두 숨겼어요.'), findsOneWidget);
  });
}
