import 'package:diligent_life/data/exercise_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'exercise_test.dart' show point;
import 'exercise_widget_test.dart' show MemoryExerciseRepository;
import 'widget_test.dart' show MemoryRecords;

class DeletionRepository extends MemoryExerciseRepository {
  bool fail = false;
  int attempts = 0;
  @override
  Future<void> deleteFinished(int id) async {
    attempts++;
    if (fail) throw StateError('Storage failure');
    saved = null;
    savedPoints.clear();
  }
}

void main() {
  sqfliteFfiInit();
  group('atomic exercise deletion', () {
    late Database db;
    late ExerciseRepository repo;
    Future<ExerciseSession> finished() async {
      final s = await repo.start(
        ExerciseType.lightWalk,
        null,
        point(37, 0).timestamp,
      );
      await repo.checkpoint(s, point: point(37, 0), rawPoint: point(37, 0));
      final result = s.copyWith(status: SessionStatus.finished);
      await repo.checkpoint(result);
      return result;
    }

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: RecordRepository.createSchema,
        ),
      );
      repo = ExerciseRepository(db);
    });
    tearDown(() => db.close());

    test('zero-distance session and both GPS tables deleted; other session untouched', () async {
      final target = await finished(), other = await finished();
      await repo.deleteFinished(target.id);
      expect((await repo.history()).single.id, other.id);
      expect(await repo.route(target.id), isEmpty);
      expect(await repo.rawRoute(target.id), isEmpty);
      expect(await repo.route(other.id), hasLength(1));
      expect(await repo.rawRoute(other.id), hasLength(1));
    });

    test('parent deletion failure rolls back both child deletions', () async {
      final target = await finished();
      await db.execute(
        "CREATE TRIGGER fail_deletion BEFORE DELETE ON exercise_sessions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        repo.deleteFinished(target.id),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.history()).single.id, target.id);
      expect(await repo.route(target.id), hasLength(1));
      expect(await repo.rawRoute(target.id), hasLength(1));
    });

    test('recording, paused and unknown sessions cannot be deleted', () async {
      final target = await repo.start(
        ExerciseType.lightWalk,
        null,
        point(37, 0).timestamp,
      );
      await repo.checkpoint(
        target,
        point: point(37, 0),
        rawPoint: point(37, 0),
      );
      await expectLater(repo.deleteFinished(target.id), throwsStateError);
      await repo.checkpoint(target.copyWith(status: SessionStatus.paused));
      await expectLater(repo.deleteFinished(target.id), throwsStateError);
      await expectLater(repo.deleteFinished(target.id + 1), throwsStateError);
      expect((await repo.active())!.id, target.id);
      expect(await repo.route(target.id), hasLength(1));
      expect(await repo.rawRoute(target.id), hasLength(1));
    });
  });

  testWidgets(
    'detail deletion confirms, cancels, retries on failure and refreshes portfolio',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DeletionRepository();
      final now = DateTime(2026, 9, 11);
      repo.saved = ExerciseSession(
        id: 7,
        startedAt: now,
        updatedAt: now,
        type: ExerciseType.lightWalk,
        status: SessionStatus.finished,
      );
      final recorder = ExerciseRecorder(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseScreen(recorder: recorder, records: MemoryRecords()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1번의 움직임 · 0.00 km'), findsOneWidget);
      await tester.ensureVisible(find.byType(ListTile));
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('기록 삭제'));
      await tester.pumpAndSettle();
      expect(find.text('운동 기록을 삭제할까요?'), findsOneWidget);
      expect(repo.attempts, 0);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repo.attempts, 0);
      expect(repo.saved, isNotNull);
      repo.fail = true;
      await tester.tap(find.byTooltip('기록 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('기록을 삭제하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(repo.saved, isNotNull);
      repo.fail = false;
      await tester.tap(find.byTooltip('기록 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(repo.attempts, 2);
      expect(find.byType(ExerciseDetailScreen), findsNothing);
      expect(find.text('완료한 운동이 여기에 표시돼요.'), findsOneWidget);
      expect(find.text('1번의 움직임 · 0.00 km'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      recorder.dispose();
    },
  );
}
