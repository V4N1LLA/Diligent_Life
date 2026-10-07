import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/daily_record.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DailyRecord record(
  String date, {
  double? weight = 70,
  String stamp = '2026-09-09T00:00:00Z',
  int duration = 30,
  double? distance = 2,
  double calories = 102.9,
}) => DailyRecord(
  date: date,
  weightKg: weight,
  exerciseType: ExerciseType.lightWalk,
  durationMinutes: duration,
  distanceKm: distance,
  estimatedCalories: calories,
  createdAt: stamp,
  updatedAt: stamp,
);

void main() {
  sqfliteFfiInit();
  late RecordRepository repository;
  setUp(() async {
    repository = RecordRepository(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: RecordRepository.createSchema,
        ),
      ),
    );
  });
  tearDown(() => repository.database.close());
  test(
    'saving a date twice updates one row and preserves identity/creation',
    () async {
      await repository.save(record('2026-09-09'));
      final before = (await repository.forDate('2026-09-09'))!;
      await repository.save(
        record('2026-09-09', weight: 68, stamp: '2026-09-09T01:00:00Z'),
      );
      final after = (await repository.forDate('2026-09-09'))!;
      expect(after.id, before.id);
      expect(after.createdAt, before.createdAt);
      expect(after.updatedAt, '2026-09-09T01:00:00Z');
      expect(after.weightKg, 68);
      expect(await repository.list(until: '2026-09-09'), hasLength(1));
    },
  );
  test('fallback skips unmeasured weights and future dates', () async {
    await repository.save(record('2026-09-01', weight: 72));
    await repository.save(record('2026-09-08', weight: null));
    await repository.save(record('2026-09-10', weight: 60));
    expect(await repository.latestWeight('2026-09-09'), 72);
    expect(await repository.latestWeight('2026-08-31'), isNull);
    expect((await repository.forDate('2026-09-08'))!.weightKg, isNull);
  });
  test('date filter includes boundaries and sorts chronologically', () async {
    for (final date in [
      '2026-09-09',
      '2026-09-02',
      '2026-09-03',
      '2026-09-10',
    ]) {
      await repository.save(record(date));
    }
    expect(
      (await repository.list(
        since: '2026-09-03',
        until: '2026-09-09',
      )).map((r) => r.date),
      ['2026-09-03', '2026-09-09'],
    );
  });
  test('concurrent saves cannot create duplicate dates', () async {
    await Future.wait(
      List.generate(
        5,
        (i) => repository.save(record('2026-09-09', weight: 65 + i.toDouble())),
      ),
    );
    expect(await repository.list(until: '2026-09-09'), hasLength(1));
  });
  test('30 day range crosses month and includes both endpoints', () async {
    for (final date in [
      '2026-08-10',
      '2026-08-11',
      '2026-08-31',
      '2026-09-09',
      '2026-09-10',
    ]) {
      await repository.save(record(date));
    }
    expect(
      (await repository.list(
        since: '2026-08-11',
        until: '2026-09-09',
      )).map((r) => r.date),
      ['2026-08-11', '2026-08-31', '2026-09-09'],
    );
  });
  test('null distance and explicit rest day round trip without filling missing dates', () async {
    await repository.save(record('2026-09-07', distance: null));
    await repository.save(
      record('2026-09-09', duration: 0, distance: null, calories: 0),
    );
    expect((await repository.forDate('2026-09-07'))!.distanceKm, isNull);
    expect((await repository.forDate('2026-09-09'))!.durationMinutes, 0);
    expect(await repository.forDate('2026-09-08'), isNull);
  });
  test(
    'invalid calendar dates and nonfinite numbers never reach SQLite',
    () async {
      for (final invalid in [
        record('2026-02-30'),
        record(''),
        record('2026-09-09', weight: double.infinity),
        record('2026-09-09', distance: double.nan),
        record('2026-09-09', calories: double.infinity),
        record('2026-09-09', duration: -1),
      ]) {
        await expectLater(repository.save(invalid), throwsArgumentError);
      }
      expect(await repository.list(until: '2026-12-31'), isEmpty);
    },
  );
}
