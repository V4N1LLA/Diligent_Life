import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/daily_record.dart';
import '../models/character.dart';
import '../models/growth.dart';
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
const growthBackupTables = [
  'daily_steps',
  'xp_ledger',
  'growth_profile',
  'exploration_events',
];
const characterBackupTables = ['character_progress'];
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
  'daily_steps': [
    'id',
    'date',
    'steps',
    'uncertainSteps',
    'coverage',
    'updatedAt',
  ],
  'xp_ledger': ['id', 'rewardKey', 'xp', 'ruleVersion', 'earnedAt'],
  'growth_profile': ['id', 'titleId'],
  'character_progress': [
    'id',
    'progressKey',
    'kind',
    'value',
    'ruleVersion',
    'createdAt',
    'seen',
  ],
  'exploration_events': [
    'id',
    'eventKey',
    'regionId',
    'sourceSessionId',
    'modelVersion',
    'discoveredAt',
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
      final hasGrowth = (await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='daily_steps'",
      )).isNotEmpty;
      final hasCharacter = (await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='character_progress'",
      )).isNotEmpty;
      final tables = [
        ...backupTables,
        if (hasGrowth) ...growthBackupTables,
        if (hasCharacter) ...characterBackupTables,
      ];
      sink.writeln(
        jsonEncode({
          'format': 'diligent-life',
          'version': hasCharacter ? 3 : (hasGrowth ? 2 : 1),
          'schema': hasCharacter ? 5 : (hasGrowth ? 4 : 3),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final counts = <String, int>{};
      await database.transaction((txn) async {
        for (final table in tables) {
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
          version: 5,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: RecordRepository.createSchema,
        ),
      );
      var tables = backupTables;
      var counts = {for (final t in tables) t: 0};
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
              !((object['version'] == 1 && object['schema'] == 3) ||
                  (object['version'] == 2 && object['schema'] == 4) ||
                  (object['version'] == 3 && object['schema'] == 5))) {
            throw const FormatException('지원하지 않는 백업 버전이에요.');
          }
          if (object['version'] == 2 || object['version'] == 3) {
            tables = [
              ...backupTables,
              ...growthBackupTables,
              if (object['version'] == 3) ...characterBackupTables,
            ];
            counts = {for (final t in tables) t: 0};
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
        final index = tables.indexOf(table);
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
    final tables = backup.counts.keys.toList();
    await database.transaction((txn) async {
      final active = await txn.query(
        'exercise_sessions',
        columns: ['id'],
        where: "status != 'finished'",
        limit: 1,
      );
      if (active.isNotEmpty) throw StateError('진행 중인 운동을 종료한 뒤 가져와 주세요.');
      // Old backups have no character state: drop stale selections/inbox and
      // deterministically derive cosmetics from the restored growth data later.
      if (!tables.contains('character_progress') &&
          (await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE name='character_progress'",
          )).isNotEmpty) {
        await txn.delete('character_progress');
      }
      for (final table in ['portfolio_analysis', 'exploration_scans']) {
        final cache = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        );
        if (cache.isNotEmpty) await txn.delete(table);
      }
      for (final table in tables.reversed) {
        await txn.delete(table);
      }
      for (final table in tables) {
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
      final exploration = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='exploration_events'",
      );
      if (exploration.isNotEmpty) {
        // Legacy replacement retains unlocks, but replaces their source IDs.
        // A deleted source in a full backup can also be reused on a new device.
        // Keep rewards/cells; never attribute them to an unrelated future workout.
        await txn.update(
          'exploration_events',
          {'sourceSessionId': null},
          where: tables.contains('exploration_events')
              ? "sourceSessionId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM exercise_sessions WHERE exercise_sessions.id = exploration_events.sourceSessionId AND status = 'finished')"
              : 'sourceSessionId IS NOT NULL',
        );
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

    if (growthBackupTables.contains(table) ||
        characterBackupTables.contains(table)) {
      void integer(String key, {int min = 0, int max = 2147483647}) {
        if (row[key] is! int ||
            (row[key] as int) < min ||
            (row[key] as int) > max) {
          throw FormatException('잘못된 $key');
        }
      }

      void stable(String key) {
        if (row[key] is! String ||
            !RegExp(r'^[a-zA-Z0-9_.:\-]{1,160}$')
                .hasMatch(row[key] as String)) {
          throw FormatException('잘못된 $key');
        }
      }

      if (table == 'character_progress') {
        stable('progressKey');
        integer('ruleVersion', min: 1, max: 1);
        integer('seen', max: 1);
        timestamp('createdAt');
        if (!['unlock', 'equip', 'reward'].contains(row['kind']) ||
            row['value'] is! String ||
            (row['value'] as String).length > 200) {
          throw const FormatException('잘못된 캐릭터 기록');
        }
        final key = row['progressKey'] as String;
        final value = row['value'] as String;
        final cosmetic = cosmetics.where((c) => c.id == value).firstOrNull;
        final level = key.startsWith('reward:level:')
            ? int.tryParse(key.substring('reward:level:'.length))
            : null;
        final valid = switch (row['kind']) {
          'unlock' => cosmetic != null && key == 'unlock:$value',
          'equip' => cosmetic != null && key == 'equip:${cosmetic.slot.name}',
          'reward' =>
            (level != null &&
                    level >= 2 &&
                    level <= 1000000 &&
                    value == 'Lv. $level 달성') ||
                cosmetics.any(
                  (c) =>
                      c.requirement != '기본' &&
                      key == 'reward:cosmetic:${c.id}' &&
                      value == '새 외형 · ${c.name}',
                ) ||
                [...achievements([], 0), ...explorationAchievements(0)].any(
                  (a) =>
                      key == 'reward:${a.id}' && value == '업적 달성 · ${a.label}',
                ),
          _ => false,
        };
        if (!valid) throw const FormatException('알 수 없는 외형·보상 기록');
      } else if (table == 'daily_steps') {
        final date = row['date'];
        if (date is! String ||
            DateTime.tryParse(date) == null ||
            dateKey(DateTime.parse(date)) != date) {
          throw const FormatException('잘못된 걸음 날짜');
        }
        integer('steps', max: 1000000);
        integer('uncertainSteps', max: row['steps'] as int);
        if (![
          'observed',
          'partial',
          'boundary',
          'reset',
          'reboot',
        ].contains(row['coverage'])) {
          throw const FormatException('잘못된 걸음 상태');
        }
        timestamp('updatedAt');
      } else if (table == 'xp_ledger') {
        stable('rewardKey');
        integer('xp', max: 1000000);
        integer('ruleVersion', min: 1, max: 1);
        timestamp('earnedAt');
      } else if (table == 'growth_profile') {
        if (row['id'] != 1) throw const FormatException('잘못된 프로필');
        if (row['titleId'] != null) stable('titleId');
      } else {
        stable('eventKey');
        stable('regionId');
        integer('modelVersion', min: 1);
        if (row['sourceSessionId'] != null) integer('sourceSessionId', min: 1);
        timestamp('discoveredAt');
      }
    } else if (table == 'daily_records') {
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
