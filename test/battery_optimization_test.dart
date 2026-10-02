import 'dart:async';

import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/services/recording_presentation.dart';
import 'package:diligent_life/utils/gps.dart';
import 'package:diligent_life/widgets/route_polyline_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_test.dart' show FakeLocation, ManualClock, point;
import 'exercise_widget_test.dart' show MemoryExerciseRepository;
import 'widget_test.dart' show MemoryRecords;

class CountingRepository extends MemoryExerciseRepository {
  int gpsCommits = 0, clockCommits = 0;
  final raw = <Map<String, Object?>>[];
  bool fail = false;
  @override
  Future<void> checkpoint(
    ExerciseSession session, {
    RoutePoint? point,
    RoutePoint? rawPoint,
    DateTime? receivedAt,
    String? decision,
    int filterVersion = 1,
  }) async {
    if (fail) throw StateError('disk full');
    if (rawPoint == null) {
      clockCommits++;
    } else {
      gpsCommits++;
      raw.add({
        ...rawPoint.toMap(session.id),
        'decision': decision,
        'filterVersion': filterVersion,
      });
    }
    await super.checkpoint(session, point: point, rawPoint: rawPoint);
  }
}

void main() {
  late CountingRepository repository;
  late FakeLocation location;
  late ManualClock clock;
  late ExerciseRecorder recorder;
  bool disposed = false;
  void cleanup() {
    if (disposed) return;
    disposed = true;
    recorder.dispose();
    unawaited(location.controller.close());
    unawaited(location.service.close());
  }

  Future<void> action(WidgetTester tester, Future<void> operation) async {
    // StreamSubscription.cancel can complete in the real zone even though
    // widget timers run on the fake clock. Drain both without advancing time.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await operation;
  }

  void fixture() {
    disposed = false;
    SharedPreferences.setMockInitialValues({});
    repository = CountingRepository();
    location = FakeLocation();
    clock = ManualClock();
    recorder = ExerciseRecorder(repository, location: location, clock: clock);
    addTearDown(cleanup);
  }

  void fix({double latitude = 37}) => location.controller.add(
    RoutePoint(
      latitude: latitude,
      longitude: 127,
      timestamp: DateTime.now().toUtc(),
      accuracy: 5,
      rawSpeed: 0,
    ),
  );

  testWidgets(
    'two-second GPS commits replace clock-only transactions and retain all raw fixes',
    (tester) async {
      fixture();
      await recorder.start(ExerciseType.lightWalk, 70);
      for (var i = 0; i < 10; i++) {
        clock.seconds = i * 2;
        fix();
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      }
      expect(repository.gpsCommits, 10);
      expect(repository.clockCommits, 0);
      expect(repository.raw, hasLength(10));
      expect(
        repository.raw.where((r) => r['decision'] == 'stationary_noise'),
        isNotEmpty,
      );
      expect(repository.saved!.elapsedSeconds, 18);
      final snapshot = recorder.points;
      fix();
      await tester.pump();
      expect(identical(snapshot, recorder.points), isTrue);
      expect(repository.raw, hasLength(11));
      cleanup();
    },
  );

  testWidgets(
    'GPS silence checkpoints every five seconds; pause stops the fallback',
    (tester) async {
      fixture();
      await recorder.start(ExerciseType.running, 70);
      clock.seconds = 5;
      await tester.pump(const Duration(seconds: 5));
      expect(repository.clockCommits, 1);
      expect(repository.saved!.elapsedSeconds, 5);
      clock.seconds = 10;
      await tester.pump(const Duration(seconds: 5));
      expect(repository.clockCommits, 2);
      await action(tester, recorder.pause());
      expect(location.controller.hasListener, isFalse);
      expect(repository.saved!.status, SessionStatus.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(repository.clockCommits, 3); // Explicit pause, no further timers.
      await action(tester, recorder.resume());
      clock.seconds = 15;
      await tester.pump(const Duration(seconds: 5));
      expect(repository.saved!.elapsedSeconds, 15);
      await action(tester, recorder.finish());
      final commits = repository.clockCommits;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.clockCommits, commits);
      expect(location.controller.hasListener, isFalse);
      cleanup();
    },
  );

  testWidgets(
    'storage failure cancels GPS and fallback without publishing an unsaved route',
    (tester) async {
      fixture();
      await recorder.start(ExerciseType.running, 70);
      repository.fail = true;
      fix();
      await tester.pump();
      await action(tester, Future<void>.value());
      expect(recorder.recording, isFalse);
      expect(recorder.issue, isNotNull);
      expect(recorder.points, isEmpty);
      expect(location.controller.hasListener, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(repository.gpsCommits, 0);
      expect(repository.clockCommits, 0);
      cleanup();
    },
  );

  testWidgets(
    'presentation isolates GPS, throttles map, and catches up after being hidden',
    (tester) async {
      fixture();
      final presentation = RecordingPresentation(recorder);
      addTearDown(presentation.dispose);
      await recorder.start(ExerciseType.running, 70);
      var ticks = 0, maps = 0;
      presentation.addListener(() => ticks++);
      presentation.map.addListener(() => maps++);
      presentation.setVisible(true);
      ticks = maps = 0;
      fix();
      await tester.pump();
      expect(ticks, 0);
      expect(maps, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, 1);
      expect(maps, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, 2);
      expect(maps, 1);
      final shown = presentation.map.value;
      presentation.setVisible(false);
      clock.seconds = 5;
      fix();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(ticks, 2);
      expect(maps, 1);
      expect(presentation.map.value, same(shown));
      expect(repository.raw, hasLength(2));
      presentation.setVisible(true);
      expect(presentation.map.value.position, same(recorder.currentPosition));
      expect(ticks, 3);
      expect(maps, 2);
      await action(tester, recorder.pause());
      final paused = ticks;
      await tester.pump(const Duration(seconds: 5));
      expect(ticks, paused);
      cleanup();
    },
  );

  testWidgets(
    'actual screen stops presentation for lifecycle and covered routes, but retains recording',
    (tester) async {
      fixture();
      await recorder.start(ExerciseType.running, 70);
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseScreen(recorder: recorder, records: MemoryRecords()),
        ),
      );
      await tester.pump();
      final presentation =
          tester
                  .widget<ListenableBuilder>(
                    find
                        .descendant(
                          of: find.byType(ExerciseScreen),
                          matching: find.byType(ListenableBuilder),
                        )
                        .first,
                  )
                  .listenable
              as RecordingPresentation;
      var ticks = 0;
      presentation.addListener(() => ticks++);
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));
      expect(ticks, 1);
      expect(recorder.recording, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final navigator = Navigator.of(
        tester.element(find.byType(ExerciseScreen)),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final covered = ticks;
      await tester.pump(const Duration(seconds: 3));
      expect(ticks, covered);
      expect(recorder.recording, isTrue);
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final restored = ticks;
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, restored + 1);
      await tester.pumpWidget(const SizedBox());
      cleanup();
    },
  );

  test('incremental map retains completed chunks and matches all legacy speed windows', () {
    final points = [
      for (var i = 0; i < 280; i++)
        point(37 + i * .00001, i * 2, segment: i < 150 ? 1 : 2),
    ];
    final cache = RoutePolylineCache();
    cache.sync(List.unmodifiable(points.take(140)), incremental: true);
    final completed = cache.lines.first;
    cache.sync(List.unmodifiable(points), incremental: true);
    expect(cache.lines.first, same(completed));
    final base = cache.lines.take(4).toList();
    expect(base, hasLength(4));
    expect(base[0].points.last, base[1].points.first);
    expect(base[1].points.last, isNot(base[2].points.first));
    final speeds = speedSections(points);
    final colored = cache.lines.skip(base.length).toList();
    expect(colored.length, speeds.length);
    for (var i = 0; i < speeds.length; i++) {
      expect(colored[i].points, speeds[i].points.map(routeLocation).toList());
      expect(colored[i].color, speedColor(speeds[i].kmh));
    }
    final frozen = cache.lines;
    cache.sync(List<RoutePoint>.unmodifiable(points), incremental: true);
    // A fresh equal-length source is conservatively rebuilt, then reused.
    final source = List<RoutePoint>.unmodifiable(points);
    cache.sync(source, incremental: true);
    final reused = cache.lines;
    cache.sync(source, incremental: true);
    expect(cache.lines, same(reused));
    expect(frozen.first.points, completed.points);
    cache.sync([point(38, 0), point(38.0001, 6)], incremental: true);
    expect(cache.lines.first.points.first.latitude, 38);
  });
}
