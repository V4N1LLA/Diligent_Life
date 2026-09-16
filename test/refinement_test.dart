import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diligent_life/screens/today_home.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/screens/portfolio_share_screen.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:diligent_life/utils/dates.dart';
import 'package:diligent_life/models/exercise_type.dart';

import 'widget_test.dart' show MemoryRecords;
import 'record_repository_test.dart' show record;
import 'exercise_widget_test.dart' show MemoryExerciseRepository;
import 'exercise_test.dart' show FakeLocation;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets(
      'today and quick weight preserve manual exercise at 320px / 2x in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final records = MemoryRecords();
        final existing = record(dateKey(DateTime.now()), weight: 70);
        await records.save(existing);
        var starts = 0;
        final location = FakeLocation();
        final recorder = ExerciseRecorder(
          MemoryExerciseRepository(),
          location: location,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: TodayHome(
                repository: records,
                recorder: recorder,
                revision: 0,
                onSaved: () {},
                openExercise: () => starts++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('운동 시작'));
        expect(starts, 1);
        await tester.ensureVisible(find.text('몸무게'));
        await tester.tap(find.text('몸무게'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('quick-weight')),
          '72',
        );
        records.failSave = true;
        await tester.ensureVisible(find.text('몸무게 저장'));
        await tester.tap(find.text('몸무게 저장'));
        await tester.pumpAndSettle();
        expect(find.textContaining('저장하지 못했어요.'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('quick-weight')))
              .controller!
              .text,
          '72',
        );
        records.failSave = false;
        await tester.ensureVisible(find.text('몸무게 저장'));
        await tester.tap(find.text('몸무게 저장'));
        await tester.pumpAndSettle();
        final saved = records.records[existing.date]!;
        expect(saved.weightKg, 72);
        expect(saved.durationMinutes, existing.durationMinutes);
        expect(saved.distanceKm, existing.distanceKm);
        expect(saved.exerciseType, existing.exerciseType);
        expect(saved.createdAt, existing.createdAt);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        recorder.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
  }
  testWidgets('manual input keeps unsaved values when closing is cancelled', (
    tester,
  ) async {
    final records = MemoryRecords();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayHome(
            repository: records,
            revision: 0,
            onSaved: () {},
            openExercise: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('지난 기록 · 운동 직접 입력'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지난 기록 · 운동 직접 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('weight')), '70');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않은 입력이 있어요.'), findsOneWidget);
    await tester.tap(find.text('계속 입력'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('weight')))
          .controller!
          .text,
      '70',
    );
    expect(records.records, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recent exercise restores; back preserves recording; finish requires confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_exercise_type': 'running',
      });
      final location = FakeLocation();
      final recorder = ExerciseRecorder(
        MemoryExerciseRepository(),
        location: location,
      );
      final records = MemoryRecords();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ExerciseScreen(recorder: recorder, records: records),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '달리기'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('운동 시작'));
      await tester.pumpAndSettle();
      expect(recorder.recording, isTrue);
      expect(recorder.session!.type, ExerciseType.running);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(recorder.recording, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('운동 종료'));
      await tester.pumpAndSettle();
      expect(recorder.recording, isTrue);
      await tester.tap(find.text('계속 운동'));
      await tester.pumpAndSettle();
      expect(recorder.recording, isTrue);
      await tester.tap(find.text('운동 종료'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('종료하고 저장'));
      // Stream cancellation may complete in the real async zone.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(recorder.issue, isNull);
      expect(recorder.active, isFalse);
      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      await tester.ensureVisible(find.text('운동 결과 공유'));
      await tester.pumpAndSettle();
      expect(find.text('운동 결과 공유').hitTestable(), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('운동 결과 공유'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioShareScreen), findsOneWidget);
      expect(find.textContaining('200m 숨김 켜짐'), findsOneWidget);
      expect(find.text('이미지 공유'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      recorder.dispose();
      await location.controller.close();
      await location.service.close();
    },
  );
}
