import 'dart:convert';
import 'dart:io';

import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'record_repository_test.dart' show record;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late BackupRepository backups;
  late ExerciseRepository exercises;
  final temporary = <Directory>[];
  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: RecordRepository.createSchema,
      ),
    );
    backups = BackupRepository(db);
    exercises = ExerciseRepository(db);
  });
  tearDown(() async {
    await db.close();
    for (final dir in temporary) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    temporary.clear();
  });
  Future<File> export() async {
    final f = await backups.export();
    temporary.add(f.parent);
    return f;
  }

  Future<ExerciseSession> seed({bool active = false}) async {
    await RecordRepository(db).save(record('2026-09-01', weight: 71));
    final s = await exercises.start(
      ExerciseType.briskWalk,
      71,
      DateTime.utc(2026, 9, 1),
    );
    final batch = db.batch();
    for (var i = 0; i < 1503; i++) {
      final p = RoutePoint(
        latitude: 37 + i * .00001,
        longitude: 127,
        timestamp: s.startedAt.add(Duration(seconds: i * 2)),
        accuracy: 5,
        rawSpeed: i == 7 ? -1 : 1.2,
        segment: i < 750 ? 0 : 1,
        cumulativeMeters: i.toDouble(),
      );
      batch.insert('route_points', p.toMap(s.id));
      batch.insert('raw_route_points', {
        ...p.toMap(s.id),
        'receivedAt': p.timestamp.toIso8601String(),
        'decision': i.isEven ? 'accepted' : 'stationary_noise',
        'filterVersion': 2,
      });
    }
    await batch.commit(noResult: true);
    final done = s.copyWith(
      status: active ? SessionStatus.paused : SessionStatus.finished,
      elapsedSeconds: 3006,
      distanceMeters: 1503,
      endedAt: active ? null : DateTime.utc(2026, 9, 1, 1),
    );
    await exercises.checkpoint(done);
    return done;
  }

  Future<Map<String, Object>> snapshot() async => {
    for (final table in backupTables)
      table: await db.query(table, orderBy: 'id'),
  };

  final legacySource = Platform.environment['LEGACY_BACKUP_DATA'];
  test(
    'existing v0.x exported backup prepares and round-trips without rewriting source',
    () async {
      final source = File(legacySource!);
      final bytes = await source.readAsBytes();
      final prepared = await backups.prepare(source);
      try {
        final expected = {
          for (final table in backupTables)
            table: await prepared.database.query(table, orderBy: 'id'),
        };
        await backups.replace(prepared);
        expect(await snapshot(), expected);
        final roundTrip = await backups.prepare(await export());
        try {
          for (final table in backupTables) {
            expect(
              await roundTrip.database.query(table, orderBy: 'id'),
              expected[table],
            );
          }
        } finally {
          await roundTrip.dispose();
        }
        expect(await source.readAsBytes(), bytes);
      } finally {
        await prepared.dispose();
      }
    },
    skip: legacySource == null
        ? 'Set LEGACY_BACKUP_DATA to a private existing .diligent export.'
        : false,
  );

  test('full multi-page backup restores every column and original GPS, clears only derived cache', () async {
    final session = await seed();
    await exercises.portfolioAnalysis(session);
    final expected = await snapshot();
    final file = await export();
    final prepared = await backups.prepare(file);
    try {
      expect(prepared.counts['route_points'], 1503);
      expect(prepared.counts['raw_route_points'], 1503);
      await exercises.deleteFinished(session.id);
      await RecordRepository(db).save(record('2026-09-02', weight: 68));
      await backups.replace(prepared);
      expect(await snapshot(), expected);
      expect(await db.query('portfolio_analysis'), isEmpty);
      expect((await exercises.portfolioAnalysis(session)).route, isNotEmpty);
    } finally {
      await prepared.dispose();
    }
  });

  test('truncated, unsupported, orphaned and malformed backups leave originals untouched', () async {
    await seed();
    final before = await snapshot();
    final file = await export();
    final lines = await file.readAsLines();
    final variants = <List<String>>[
      lines.sublist(0, lines.length - 1),
      [...lines, lines[1]],
      [lines.first, lines[1], ...lines.skip(1)],
      [lines.first.replaceFirst('"schema":3', '"schema":99'), ...lines.skip(1)],
      [...lines.take(lines.length - 1), '{}'],
      [
        lines.first.replaceFirst('"version":1', '"version":99'),
        ...lines.skip(1),
      ],
      lines
          .map(
            (l) => l.contains('"table":"route_points"')
                ? l.replaceFirst('"sessionId":1', '"sessionId":999')
                : l,
          )
          .toList(),
      lines
          .map(
            (l) => l.contains('"table":"daily_records"')
                ? l.replaceFirst('"weightKg":71.0', '"weightKg":-1')
                : l,
          )
          .toList(),
    ];
    final invalidUtf8 = File('${file.parent.path}/invalid-utf8.diligent');
    await invalidUtf8.writeAsBytes([0xff, 0xfe, 0x00]);
    await expectLater(backups.prepare(invalidUtf8), throwsA(anything));
    expect(await snapshot(), before);
    for (var i = 0; i < variants.length; i++) {
      final invalid = File('${file.parent.path}/invalid-$i.diligent');
      await invalid.writeAsString('${variants[i].join('\n')}\n');
      await expectLater(backups.prepare(invalid), throwsA(anything));
      expect(await snapshot(), before);
    }
  });

  test(
    'replace failure rolls back deleted records; active exercise blocks import',
    () async {
      final s = await seed();
      final prepared = await backups.prepare(await export());
      try {
        final before = await snapshot();
        await db.execute(
          "CREATE TRIGGER reject_restore BEFORE INSERT ON raw_route_points BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
        );
        await expectLater(backups.replace(prepared), throwsA(anything));
        expect(await snapshot(), before);
        await db.execute('DROP TRIGGER reject_restore');
        await exercises.start(s.type, null, DateTime.utc(2026, 9, 2));
        final activeBefore = await snapshot();
        await expectLater(backups.replace(prepared), throwsStateError);
        expect(await snapshot(), activeBefore);
      } finally {
        await prepared.dispose();
      }
    },
  );

  test(
    'empty and paused session backups are supported and footer is required',
    () async {
      final empty = await backups.prepare(await export());
      try {
        expect(empty.counts.values.every((c) => c == 0), isTrue);
        await backups.replace(empty);
      } finally {
        await empty.dispose();
      }
      await seed(active: true);
      final paused = await backups.prepare(await export());
      try {
        expect(
          (await paused.database.query('exercise_sessions')).single['status'],
          'paused',
        );
      } finally {
        await paused.dispose();
      }
      final file = await export();
      final text = await file.readAsString();
      expect(jsonDecode(text.split('\n').first)['format'], 'diligent-life');
    },
  );
}
