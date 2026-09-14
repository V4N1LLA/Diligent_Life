import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/daily_record.dart';
import '../models/exercise_session.dart';
import '../utils/dates.dart';
import 'record_repository.dart';

// NDJSON is streamed in bounded batches. The temporary database validates every
// row/constraint before the user confirms; replacement is one atomic transaction.
const backupTables = [
  'daily_records',
  'exercise_sessions',
  'route_points',
  'raw_route_points',
];
const _columns = {
  'daily_records': [
    'id',
    'date',
    'weightKg',
    'exerciseType',
    'durationMinutes',
    'distanceKm',
    'estimatedCalories',
    'createdAt',
    'updatedAt',
  ],
  'exercise_sessions': [
    'id',
    'startedAt',
    'endedAt',
    'updatedAt',
    'exerciseType',
    'weightKg',
    'elapsedSeconds',
    'distanceMeters',
    'estimatedCalories',
    'status',
  ],
  'route_points': [
    'id',
    'sessionId',
    'latitude',
    'longitude',
    'timestamp',
    'accuracy',
    'segment',
    'rawSpeed',
    'cumulativeMeters',
  ],
  'raw_route_points': [
    'id',
    'sessionId',
    'latitude',
    'longitude',
    'timestamp',
    'accuracy',
    'segment',
    'rawSpeed',
    'cumulativeMeters',
    'receivedAt',
    'decision',
    'filterVersion',
  ],
};

class PreparedBackup {
  PreparedBackup._(this.database, this.directory, this.counts, this.createdAt);
  final Database database;
  final Directory directory;
  final Map<String, int> counts;
  final String createdAt;
  Future<void> dispose() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

class BackupRepository {
  BackupRepository(this.database);
  final Database database;

  Future<File> export() async {
    final dir = await Directory.systemTemp.createTemp('diligent-export-');
    final file = File('${dir.path}/diligent-life.diligent');
    final sink = file.openWrite();
    // Attach an error handler immediately; flush/close still propagate failures.
    sink.done.ignore();
    try {
      sink.writeln(
        jsonEncode({
          'format': 'diligent-life',
          'version': 1,
          'schema': 3,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final counts = <String, int>{};
      await database.transaction((txn) async {
        for (final table in backupTables) {
          int last = 0, count = 0;
          while (true) {
            final rows = await txn.query(
              table,
              where: 'id > ?',
              whereArgs: [last],
              orderBy: 'id',
              limit: 500,
            );
            if (rows.isEmpty) break;
            for (final row in rows) {
              sink.writeln(
                jsonEncode({
                  'table': table,
                  'row': row.map((k, v) => MapEntry(k, _encodeNumber(v))),
                }),
              );
            }
            await sink.flush();
            last = rows.last['id'] as int;
            count += rows.length;
          }
          counts[table] = count;
        }
      });
      sink.writeln(jsonEncode({'end': counts}));
      await sink.flush();
      await sink.close();
      return file;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<PreparedBackup> prepare(File file) async {
    final dir = await Directory.systemTemp.createTemp('diligent-import-');
    Database? staging;
    try {
      staging = await databaseFactory.openDatabase(
        '${dir.path}/validated.db',
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: RecordRepository.createSchema,
        ),
      );
      final counts = {for (final t in backupTables) t: 0};
      bool header = false, ended = false;
      String createdAt = '';
      int tableIndex = 0, batchCount = 0;
      var batch = staging.batch();
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (ended || line.length > 65536) {
          throw const FormatException('잘못되거나 손상된 백업 파일이에요.');
        }
        final object = jsonDecode(line);
        if (object is! Map<String, dynamic>) {
          throw const FormatException('백업 형식이 올바르지 않아요.');
        }
        if (!header) {
          if (object['format'] != 'diligent-life' ||
              object['version'] != 1 ||
              object['schema'] != 3) {
            throw const FormatException('지원하지 않는 백업 버전이에요.');
          }
          createdAt = object['createdAt'] as String;
          DateTime.parse(createdAt);
          header = true;
          continue;
        }
        if (object.containsKey('end')) {
          final expected = object['end'];
          if (expected is! Map ||
              expected.length != counts.length ||
              counts.entries.any((e) => expected[e.key] != e.value)) {
            throw const FormatException('백업 기록 수가 맞지 않아요.');
          }
          ended = true;
          continue;
        }
        final table = object['table'] as String;
        final index = backupTables.indexOf(table);
        if (index < tableIndex || index < 0) {
          throw const FormatException('백업 테이블 순서가 올바르지 않아요.');
        }
        tableIndex = index;
        final row = (object['row'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, _decodeNumber(v)),
        );
        _validate(table, row);
        batch.insert(table, row);
        counts[table] = counts[table]! + 1;
        if (++batchCount == 500) {
          await batch.commit(noResult: true);
          batch = staging.batch();
          batchCount = 0;
        }
      }
      if (!header || !ended) {
        throw const FormatException('백업 파일이 끝까지 저장되지 않았어요.');
      }
      await batch.commit(noResult: true);
      return PreparedBackup._(
        staging,
        dir,
        Map.unmodifiable(counts),
        createdAt,
      );
    } catch (_) {
      await staging?.close();
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> replace(PreparedBackup backup) async {
    await database.transaction((txn) async {
      final active = await txn.query(
        'exercise_sessions',
        columns: ['id'],
        where: "status != 'finished'",
        limit: 1,
      );
      if (active.isNotEmpty) throw StateError('진행 중인 운동을 종료한 뒤 가져와 주세요.');
      final cache = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='portfolio_analysis'",
      );
      if (cache.isNotEmpty) await txn.delete('portfolio_analysis');
      for (final table in backupTables.reversed) {
        await txn.delete(table);
      }
      for (final table in backupTables) {
        int last = 0;
        while (true) {
          final rows = await backup.database.query(
            table,
            where: 'id > ?',
            whereArgs: [last],
            orderBy: 'id',
            limit: 500,
          );
          if (rows.isEmpty) break;
          final batch = txn.batch();
          for (final row in rows) {
            batch.insert(table, row);
          }
          await batch.commit(noResult: true);
          last = rows.last['id'] as int;
        }
      }
    });
  }

  static Object? _encodeNumber(Object? v) =>
      v is double && !v.isFinite ? {'float': v.toString()} : v;
  static Object? _decodeNumber(Object? v) {
    if (v is Map && v.length == 1 && v.containsKey('float')) {
      return switch (v['float']) {
        'Infinity' => double.infinity,
        '-Infinity' => double.negativeInfinity,
        'NaN' => double.nan,
        _ => throw const FormatException('잘못된 숫자'),
      };
    }
    return v;
  }

  static void _validate(String table, Map<String, Object?> row) {
    final columns = _columns[table]!;
    if (row.length != columns.length ||
        columns.any((c) => !row.containsKey(c)) ||
        row['id'] is! int ||
        (row['id'] as int) <= 0) {
      throw const FormatException('잘못된 기록 필드');
    }
    void finite(
      String key, {
      double min = 0,
      double max = double.infinity,
      bool nullable = false,
    }) {
      final v = row[key];
      if (nullable && v == null) return;
      if (v is! num || !v.isFinite || v < min || v > max) {
        throw FormatException('잘못된 $key');
      }
    }

    void timestamp(String key, {bool nullable = false}) {
      if (nullable && row[key] == null) return;
      final value = row[key];
      if (value is! String || DateTime.tryParse(value) == null) {
        throw FormatException('잘못된 $key');
      }
    }

    if (table == 'daily_records') {
      final r = DailyRecord.fromMap(row);
      if (dateKey(DateTime.parse(r.date)) != r.date ||
          r.durationMinutes < 0 ||
          r.durationMinutes > 1440 ||
          (r.durationMinutes == 0 &&
              (r.estimatedCalories != 0 || (r.distanceKm ?? 0) > 0))) {
        throw const FormatException('잘못된 일상 기록');
      }
      finite('weightKg', min: double.minPositive, max: 500, nullable: true);
      finite('distanceKm', max: 1000, nullable: true);
      finite('estimatedCalories');
      timestamp('createdAt');
      timestamp('updatedAt');
    } else if (table == 'exercise_sessions') {
      final s = ExerciseSession.fromMap(row);
      if (s.elapsedSeconds < 0) throw const FormatException('잘못된 운동 시간');
      finite('weightKg', min: double.minPositive, max: 500, nullable: true);
      finite('distanceMeters');
      finite('estimatedCalories', nullable: true);
      timestamp('startedAt');
      timestamp('updatedAt');
      timestamp('endedAt', nullable: true);
      // Stored timestamps are canonical UTC so SQLite date range queries stay valid.
      for (final k in ['startedAt', 'updatedAt', 'endedAt']) {
        if (row[k] != null &&
            DateTime.parse(row[k] as String).toUtc().toIso8601String() !=
                row[k]) {
          throw const FormatException('운동 시각 형식이 올바르지 않아요.');
        }
      }
    } else {
      if (row['sessionId'] is! int ||
          (row['sessionId'] as int) <= 0 ||
          row['segment'] is! int ||
          (row['segment'] as int) < 0) {
        throw const FormatException('잘못된 경로 연결');
      }
      timestamp('timestamp');
      if (table == 'route_points') {
        finite('latitude', min: -90, max: 90);
        finite('longitude', min: -180, max: 180);
        finite('accuracy', min: double.minPositive);
      } else {
        // Rejected GPS samples intentionally include null/out-of-range sensor values.
        timestamp('receivedAt');
        if (row['filterVersion'] is! int || row['decision'] is! String) {
          throw const FormatException('잘못된 원본 정보');
        }
      }
      for (final k in [
        'latitude',
        'longitude',
        'accuracy',
        'rawSpeed',
        'cumulativeMeters',
      ]) {
        if (row[k] != null && row[k] is! num) throw FormatException('잘못된 $k');
      }
    }
  }
}
