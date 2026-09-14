import 'dart:io';

import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/screens/backup_screen.dart';
import 'package:diligent_life/services/backup_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 350));
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
