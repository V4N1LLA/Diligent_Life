import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/daily_record.dart';
import '../utils/dates.dart';
import 'exercise_repository.dart';

class RecordRepository {
  RecordRepository(this.database);
  final Database database;

  static Future<RecordRepository> open() async => RecordRepository(
    await openDatabase(
      p.join(await getDatabasesPath(), 'diligent_life.db'),
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: createSchema,
      onUpgrade: upgradeSchema,
    ),
  );

  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await ExerciseRepository.createSchema(db, includeRaw: newVersion >= 3);
    }
    if (oldVersion == 2 && newVersion >= 3) {
      await ExerciseRepository.migrateV3(db);
    }
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''CREATE TABLE daily_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL UNIQUE,
      weightKg REAL CHECK(weightKg > 0),
      exerciseType TEXT NOT NULL,
      durationMinutes INTEGER NOT NULL CHECK(durationMinutes >= 0),
      distanceKm REAL CHECK(distanceKm >= 0),
      estimatedCalories REAL NOT NULL CHECK(estimatedCalories >= 0),
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL
    )''');
    if (version >= 2) {
      await ExerciseRepository.createSchema(db, includeRaw: version >= 3);
    }
  }

  Future<DailyRecord?> forDate(String date) async {
    final rows = await database.query(
      'daily_records',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isEmpty ? null : DailyRecord.fromMap(rows.first);
  }

  Future<double?> latestWeight(String onOrBefore) async {
    final rows = await database.query(
      'daily_records',
      columns: ['weightKg'],
      where: 'date <= ? AND weightKg IS NOT NULL',
      whereArgs: [onOrBefore],
      orderBy: 'date DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['weightKg'] as num).toDouble();
  }

  Future<List<DailyRecord>> list({String? since, required String until}) async {
    final rows = await database.query(
      'daily_records',
      where: since == null ? 'date <= ?' : 'date >= ? AND date <= ?',
      whereArgs: since == null ? [until] : [since, until],
      orderBy: 'date ASC',
    );
    return rows.map(DailyRecord.fromMap).toList();
  }

  Future<void> save(DailyRecord record) async {
    final date = DateTime.tryParse(record.date);
    final weight = record.weightKg;
    final distance = record.distanceKm;
    if (date == null ||
        dateKey(date) != record.date ||
        (weight != null && (!weight.isFinite || weight <= 0 || weight > 500)) ||
        record.durationMinutes < 0 ||
        record.durationMinutes > 1440 ||
        (distance != null &&
            (!distance.isFinite || distance < 0 || distance > 1000)) ||
        !record.estimatedCalories.isFinite ||
        record.estimatedCalories < 0 ||
        (record.durationMinutes == 0 &&
            (record.estimatedCalories != 0 || (distance ?? 0) > 0))) {
      throw ArgumentError('유효하지 않은 기록입니다.');
    }
    await database.transaction((txn) async {
      final values = record.toMap()..remove('createdAt');
      final changed = await txn.update(
        'daily_records',
        values,
        where: 'date = ?',
        whereArgs: [record.date],
      );
      if (changed == 0) await txn.insert('daily_records', record.toMap());
    });
  }
}
