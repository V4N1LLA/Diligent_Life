import 'dart:io';
import 'dart:convert';

import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/screens/backup_screen.dart';
import 'package:diligent_life/services/backup_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PreviewBackup implements PreparedBackup {
  @override
  final counts = {
    'daily_records': 3,
    'exercise_sessions': 2,
    'route_points': 100,
    'raw_route_points': 200,
  };
  @override
  final createdAt = '2026-09-14T00:00:00.000Z';
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewRepository implements BackupRepository {
  int replacements = 0;
  bool fail = false;
  @override
  Future<PreparedBackup> prepare(File file) async => PreviewBackup();
  @override
  Future<void> replace(PreparedBackup backup) async {
    if (fail) throw StateError('storage');
    replacements++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewFiles extends BackupFiles {
  int picks = 0;
  @override
  Future<File?> pick() async {
    picks++;
    return File('${Directory.systemTemp.path}/diligent-nonexistent-preview');
  }
}

class ExportFiles extends BackupFiles {
  List<String>? saved;
  @override
  Future<bool> save(File file) async {
    saved = await file.readAsLines();
    return true;
  }
}

void main() {
  for (final failFlush in [false, true]) {
    testWidgets(
      'export includes pending sensor steps or aborts on flush failure ($failFlush)',
      (tester) async {
        sqfliteFfiInit();
        final db = await tester.runAsync(
          () => databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(
              version: 4,
              singleInstance: false,
              onCreate: RecordRepository.createSchema,
            ),
          ),
        );
        addTearDown(db!.close);
        const channel = MethodChannel('diligent_life/steps');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method != 'flush') {
              throw StateError('Unexpected sensor operation');
            }
            if (failFlush) throw PlatformException(code: 'storage');
            // Model a sensor batch that has not reached the 30-second DB checkpoint.
            await db.insert('daily_steps', {
              'date': '2026-10-07',
              'steps': 59,
              'coverage': 'observed',
              'updatedAt': '2026-10-07T00:00:00Z',
            });
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final files = ExportFiles();
        await tester.pumpWidget(
          MaterialApp(
            home: BackupScreen(
              repository: BackupRepository(db),
              files: files,
              canImport: () => true,
              onImported: () async {},
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('전체 기록 내보내기'));
        });
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
        }
        if (failFlush) {
          expect(files.saved, isNull);
          expect(find.textContaining('저장하지 못했어요.'), findsOneWidget);
        } else {
          final rows = files.saved!.map(
            (line) => jsonDecode(line) as Map<String, dynamic>,
          );
          expect(
            rows
                .where((r) => r['table'] == 'daily_steps')
                .single['row']['steps'],
            59,
          );
          expect(find.text('백업 파일을 저장했어요.'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'import previews counts, cancel preserves data, explicit confirmation replaces once',
    (tester) async {
      final repository = PreviewRepository();
      final files = PreviewFiles();
      int refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            repository: repository,
            files: files,
            canImport: () => true,
            onImported: () async {
              refreshed++;
            },
          ),
        ),
      );
      Future<void> settle() async {
        // Document I/O and the native step pause/resume reply in the real zone.
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 350));
        }
      }

      await tester.tap(find.text('백업 파일 가져오기'));
      await settle();
      expect(find.text('이 백업으로 전체 기록을 교체할까요?'), findsOneWidget);
      expect(find.textContaining('원본 GPS 200개'), findsOneWidget);
      expect(repository.replacements, 0);
      await tester.tap(find.text('취소'));
      await settle();
      expect(repository.replacements, 0);
      expect(refreshed, 0);
      await tester.tap(find.text('백업 파일 가져오기'));
      await settle();
      await tester.tap(find.text('전체 기록 교체'));
      await settle();
      expect(repository.replacements, 1);
      expect(refreshed, 1);
      expect(find.text('백업의 전체 기록을 복원했어요.'), findsOneWidget);
      repository.fail = true;
      await tester.tap(find.text('백업 파일 가져오기'));
      await settle();
      await tester.tap(find.text('전체 기록 교체'));
      await settle();
      expect(repository.replacements, 1);
      expect(refreshed, 1);
      expect(find.textContaining('가져오지 못했어요.'), findsOneWidget);
    },
  );

  testWidgets(
    'active exercise or unsaved entry blocks picker and replacement',
    (tester) async {
      final repository = PreviewRepository();
      final files = PreviewFiles();
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            repository: repository,
            files: files,
            canImport: () => false,
            onImported: () async {},
          ),
        ),
      );
      await tester.tap(find.text('백업 파일 가져오기'));
      await tester.pumpAndSettle();
      expect(files.picks, 0);
      expect(repository.replacements, 0);
      expect(find.textContaining('진행 중인 운동을 종료하고'), findsOneWidget);
    },
  );
}
