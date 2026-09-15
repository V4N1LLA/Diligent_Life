import 'dart:async';
import 'dart:ui' as ui;

import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/utils/movement_analysis.dart';
import 'package:diligent_life/main.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/services/exercise_share.dart';
import 'package:diligent_life/services/reminder_service.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show MemoryRecords;
import 'exercise_test.dart' show FakeLocation, point;

class MemoryExerciseRepository implements ExerciseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<MovementAnalysis> movementAnalysis(
    ExerciseSession session, {
    bool recalculate = false,
  }) async {
    final analyzer = MovementAnalyzer(session, rawAvailable: false);
    for (final p in savedPoints) {
      analyzer.addRow(p.toMap(session.id));
    }
    return analyzer.finish();
  }

  ExerciseSession? saved;
  final savedPoints = <RoutePoint>[];
  @override
  Future<ExerciseSession?> active() async =>
      saved?.status == SessionStatus.finished ? null : saved;
  @override
  Future<List<ExerciseSession>> history() async =>
      saved?.status == SessionStatus.finished ? [saved!] : [];
  @override
  Future<List<RoutePoint>> route(int id) async => savedPoints;
  @override
  Future<ExerciseSession> start(
    ExerciseType type,
    double? weight,
    DateTime now,
  ) async => saved = ExerciseSession(
    id: 1,
    startedAt: now,
    updatedAt: now,
    type: type,
    weightKg: weight,
  );
  @override
  Future<void> checkpoint(
    ExerciseSession session, {
    RoutePoint? point,
    RoutePoint? rawPoint,
    DateTime? receivedAt,
    String? decision,
    int filterVersion = 1,
  }) async {
    saved = session;
    if (point != null) savedPoints.add(point);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'GPS screen and sharing preview fit 320px / 2x text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final location = FakeLocation();
        final recorder = ExerciseRecorder(
          MemoryExerciseRepository(),
          location: location,
        );
        Widget host(Widget screen) => MaterialApp(
          theme: appTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: screen,
        );
        await tester.pumpWidget(
          host(ExerciseScreen(recorder: recorder, records: MemoryRecords())),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await recorder.start(ExerciseType.running, null);
        await tester.pump();
        expect(find.text('— kcal'), findsOneWidget);
        expect(tester.takeException(), isNull);
        unawaited(recorder.pause());
        await tester.pumpAndSettle();
        await tester.pump();
        expect(tester.takeException(), isNull);
        unawaited(recorder.finish());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          host(
            ExerciseDetailScreen(
              session: recorder.session!,
              route: Future.value([]),
              onDelete: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byType(SwitchListTile), 200);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        recorder.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
  }
  testWidgets(
    'ordinary exit has no dialog; unsaved input exit can be cancelled',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final reminders = ReminderService(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        DiligentLifeApp(
          home: AppShell(repository: MemoryRecords(), reminders: reminders),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopScope<dynamic>>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isTrue,
      );
      await tester.enterText(find.byKey(const ValueKey('weight')), '70');
      await tester.pump();
      expect(
        tester
            .widget<PopScope<dynamic>>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('저장하지 않은 입력이 있어요.'), findsOneWidget);
      await tester.tap(find.text('계속 입력'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('weight')))
            .controller!
            .text,
        '70',
      );
      await tester.enterText(find.byKey(const ValueKey('weight')), '');
      await tester.pump();
      expect(
        tester
            .widget<PopScope<dynamic>>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isTrue,
      );
      reminders.dispose();
    },
  );
  testWidgets('continue recording backgrounds Android without ending session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final reminders = ReminderService(await SharedPreferences.getInstance());
    final recorder = ExerciseRecorder(
      MemoryExerciseRepository(),
      location: FakeLocation(),
    );
    await recorder.start(ExerciseType.lightWalk, 70);
    String? method;
    const channel = MethodChannel('diligent_life/lifecycle');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      method = call.method;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      DiligentLifeApp(
        home: AppShell(
          repository: MemoryRecords(),
          reminders: reminders,
          recorder: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('계속 기록'), findsOneWidget);
    expect(find.text('운동 종료'), findsOneWidget);
    await tester.tap(find.text('계속 기록'));
    await tester.pumpAndSettle();
    expect(method, 'moveToBackground');
    expect(recorder.recording, isTrue);
    unawaited(recorder.finish());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    recorder.dispose();
    reminders.dispose();
  });
  testWidgets(
    'share card produces PNG, including when entire short route is hidden',
    (tester) async {
      final session = ExerciseSession(
        id: 1,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        type: ExerciseType.lightWalk,
        weightKg: 70,
        elapsedSeconds: 300,
        distanceMeters: 100,
      );
      // Image codec runs outside the widget test's fake async zone.
      await tester.runAsync(() async {
        final bytes = await exerciseShareImage(session, [
          point(37, 0),
          point(37.0001, 10),
        ], hideEndpoints: true);
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 720);
        expect(frame.image.height, 930);
        frame.image.dispose();
        codec.dispose();
      });
    },
  );
}
