import 'dart:async';

import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/utils/gps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'record_repository_test.dart' show record;

RoutePoint point(
  double latitude,
  int seconds, {
  double accuracy = 5,
  int segment = 0,
}) => RoutePoint(
  latitude: latitude,
  longitude: 127,
  timestamp: DateTime.utc(2026, 9, 10).add(Duration(seconds: seconds)),
  accuracy: accuracy,
  segment: segment,
);

class FakeLocation extends ExerciseLocation {
  final controller = StreamController<RoutePoint>.broadcast();
  final service = StreamController<bool>.broadcast();
  @override
  Stream<bool> serviceEnabled() => service.stream;
  LocationIssue? failure;
  int requests = 0;
  @override
  Future<void> prepare() async {
    requests++;
    if (failure != null) throw failure!;
  }

  @override
  Stream<RoutePoint> positions() => controller.stream;
}

class ManualClock implements Stopwatch {
  int seconds = 0;
  @override
  bool isRunning = false;
  @override
  Duration get elapsed => Duration(seconds: seconds);
  @override
  int get elapsedMilliseconds => seconds * 1000;
  @override
  int get elapsedMicroseconds => seconds * 1000000;
  @override
  int get elapsedTicks => seconds * frequency;
  @override
  int get frequency => 1000000;
  @override
  void reset() {
    seconds = 0;
  }

  @override
  void start() {
    isRunning = true;
  }

  @override
  void stop() {
    isRunning = false;
  }
}

void main() {
  sqfliteFfiInit();
  group('GPS filtering and privacy', () {
    test('stationary noise, poor accuracy, stale/future and impossible jump rejected', () {
      final filter = GpsFilter();
      RoutePoint? accept(RoutePoint p) => filter.accept(p, p.timestamp);
      expect(accept(point(37, 0)), isNotNull);
      expect(accept(point(37.00001, 2)), isNull);
      expect(accept(point(37.1, 4)), isNull);
      expect(accept(point(37.0001, 6, accuracy: 100)), isNull);
      expect(accept(point(double.nan, 8)), isNull);
      expect(filter.accept(point(37.0001, 8), point(37, 40).timestamp), isNull);
      expect(filter.accept(point(37.0001, 40), point(37, 8).timestamp), isNull);
      // Returning from a teleport is also an implausible edge. Recover only
      // after a second plausible fix, without counting the intervening gap.
      expect(accept(point(37.0001, 10)), isNull);
      expect(accept(point(37.0002, 12)), isNotNull);
      expect(filter.addedMeters, 0);
      expect(accept(point(37.0003, 14)), isNotNull);
      expect(filter.addedMeters, closeTo(11.12, .1));
      expect(accept(point(37.0001, 10)), isNull);
    });
    test('pause and GPS outage never accumulate connecting distance', () {
      final filter = GpsFilter();
      final first = filter.accept(point(37, 0), point(37, 0).timestamp)!;
      filter.breakSegment();
      final resumed = filter.accept(point(38, 2), point(38, 2).timestamp)!;
      expect(filter.addedMeters, 0);
      expect(resumed.segment, isNot(first.segment));
      final recovered = filter.accept(point(39, 40), point(39, 40).timestamp)!;
      expect(filter.addedMeters, 0);
      expect(recovered.segment, isNot(resumed.segment));
    });
    test('privacy removes endpoints and revisits, preserving disconnected segments', () {
      final raw = [
        point(37, 0),
        point(37.003, 10),
        point(37.004, 20),
        point(37, 30),
        point(37.004, 40),
        point(37.005, 50),
        point(37.01, 60),
      ];
      final hidden = privateRoute(raw);
      expect(hidden, hasLength(4));
      expect(hidden[1].segment, isNot(hidden[2].segment));
      for (final p in hidden) {
        expect(metersBetween(p, raw.first), greaterThan(200));
        expect(metersBetween(p, raw.last), greaterThan(200));
      }
      expect(raw[1].segment, 0);
      expect(privateRoute([point(37, 0), point(37.001, 1)]), isEmpty);
      expect(privateRoute([]), isEmpty);
    });
    test('seconds-based kcal and pace handle missing weight or distance', () {
      final s = ExerciseSession(
        id: 1,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        type: ExerciseType.lightWalk,
        weightKg: 70,
        elapsedSeconds: 90,
        distanceMeters: 200,
      );
      expect(s.calories, closeTo(5.145, .0001));
      expect(s.paceSeconds, 450);
      expect(paceLabel(s.paceSeconds), '7:30 /km');
      expect(s.copyWith(distanceMeters: 0).paceSeconds, isNull);
      expect(elapsedLabel(3661), '01:01:01');
    });
  });

  group('session persistence', () {
    late Database db;
    late ExerciseRepository repository;
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: RecordRepository.createSchema,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );
      repository = ExerciseRepository(db);
    });
    tearDown(() => db.close());
    test('v1 additive migration preserves daily measurements', () async {
      final old = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: RecordRepository.createSchema,
        ),
      );
      try {
        await RecordRepository(old).save(record('2026-09-10'));
        await ExerciseRepository.createSchema(old);
        await ExerciseRepository(old)
            .start(ExerciseType.running, null, DateTime.now());
        expect(
          (await RecordRepository(old).forDate('2026-09-10'))!.weightKg,
          70,
        );
      } finally {
        await old.close();
      }
    });
    test('one unfinished session, atomic point/stat update, immutable finished session', () async {
      final s = await repository.start(
        ExerciseType.jogging,
        null,
        DateTime.now(),
      );
      await expectLater(
        repository.start(ExerciseType.running, 70, DateTime.now()),
        throwsA(isA<DatabaseException>()),
      );
      final p = point(37, 0);
      await repository.checkpoint(
        s.copyWith(elapsedSeconds: 10, distanceMeters: 12),
        point: p,
      );
      await expectLater(
        repository.checkpoint(s.copyWith(elapsedSeconds: 99), point: p),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repository.active())!.elapsedSeconds, 10);
      expect(await repository.route(s.id), hasLength(1));
      expect((await repository.active())!.calories, isNull);
      await repository.checkpoint(
        s.copyWith(status: SessionStatus.finished, endedAt: DateTime.now()),
      );
      expect(await repository.active(), isNull);
      expect(await repository.history(), hasLength(1));
      await expectLater(repository.checkpoint(s), throwsStateError);
      expect(await RecordRepository(db).forDate('2026-09-10'), isNull);
    });
    test('start pause resume finish exclude paused time and restore interrupted session', () async {
      final location = FakeLocation();
      final clock = ManualClock();
      final recorder = ExerciseRecorder(
        repository,
        location: location,
        clock: clock,
      );
      await recorder.restore();
      expect(location.requests, 0);
      await recorder.start(ExerciseType.running, 70);
      clock.seconds = 30;
      await recorder.pause();
      expect(clock.isRunning, isFalse);
      expect((await repository.active())!.elapsedSeconds, 30);
      await recorder.resume();
      expect(clock.isRunning, isTrue);
      clock.seconds = 45;
      await recorder.pause();
      final id = recorder.session!.id;
      final started = recorder.session!.startedAt;
      // Simulate process loss after a recording checkpoint, without a clean stop.
      await repository.checkpoint(
        recorder.session!.copyWith(status: SessionStatus.recording),
      );
      recorder.dispose();
      final restored = ExerciseRecorder(
        repository,
        location: location,
        clock: ManualClock(),
      );
      await restored.restore();
      expect(restored.recording, isFalse);
      expect(restored.session!.id, id);
      expect(restored.elapsedSeconds, 45);
      await restored.finish();
      expect(restored.active, isFalse);
      expect((await repository.history()).single.startedAt, started);
      restored.dispose();
      await location.controller.close();
      await location.service.close();
    });
    test(
      'sensor positions persist with statistics and never bridge a pause',
      () async {
        final location = FakeLocation();
        final recorder = ExerciseRecorder(
          repository,
          location: location,
          clock: ManualClock(),
        );
        await recorder.start(ExerciseType.running, 70);
        final now = DateTime.now().toUtc();
        Future<void> emit(double latitude, int seconds, int count) async {
          final complete = Completer<void>();
          void changed() {
            if (recorder.points.length == count && !complete.isCompleted) {
              complete.complete();
            }
          }

          recorder.addListener(changed);
          location.controller.add(
            RoutePoint(
              latitude: latitude,
              longitude: 127,
              accuracy: 5,
              timestamp: now.add(Duration(seconds: seconds)),
            ),
          );
          try {
            await complete.future.timeout(const Duration(seconds: 5));
          } finally {
            recorder.removeListener(changed);
          }
        }

        await emit(37, 0, 1);
        await emit(37.0001, 2, 2);
        await recorder.pause();
        await recorder.resume();
        await emit(38, 3, 3);
        await recorder.finish();
        final saved = (await repository.history()).single;
        expect(saved.distanceMeters, closeTo(11.12, .1));
        final route = await repository.route(saved.id);
        expect(route, hasLength(3));
        expect(route[1].segment, isNot(route[2].segment));
        expect(location.controller.hasListener, isFalse);
        expect(location.service.hasListener, isFalse);
        recorder.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
    test(
      'location service OFF checkpoints a pause and permits explicit resume',
      () async {
        final location = FakeLocation();
        final clock = ManualClock();
        final recorder = ExerciseRecorder(
          repository,
          location: location,
          clock: clock,
        );
        await recorder.start(ExerciseType.running, 70);
        clock.seconds = 12;
        final paused = Completer<void>();
        void changed() {
          if (!recorder.recording &&
              recorder.issue != null &&
              !paused.isCompleted) {
            paused.complete();
          }
        }

        recorder.addListener(changed);
        location.service.add(false);
        await paused.future.timeout(const Duration(seconds: 5));
        recorder.removeListener(changed);
        expect((await repository.active())!.status, SessionStatus.paused);
        expect((await repository.active())!.elapsedSeconds, 12);
        expect(recorder.issue!.locationSettings, isTrue);
        await recorder.resume();
        expect(recorder.recording, isTrue);
        await recorder.finish();
        recorder.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
    test('denied permission creates no session and can be retried', () async {
      final location = FakeLocation()..failure = const LocationIssue('denied');
      final recorder = ExerciseRecorder(repository, location: location);
      await recorder.start(ExerciseType.running, null);
      expect(recorder.issue!.message, 'denied');
      expect(await repository.active(), isNull);
      location.failure = null;
      await recorder.start(ExerciseType.running, null);
      expect(recorder.recording, isTrue);
      await recorder.finish();
      recorder.dispose();
      await location.controller.close();
      await location.service.close();
    });
  });
}
