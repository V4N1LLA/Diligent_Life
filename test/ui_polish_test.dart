import 'dart:async';

import 'package:diligent_life/data/growth_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/growth.dart';
import 'package:diligent_life/screens/growth_screen.dart';
import 'package:diligent_life/screens/trends_screen.dart';
import 'package:diligent_life/screens/settings_screen.dart';
import 'package:diligent_life/services/reminder_service.dart';
import 'package:diligent_life/widgets/route_scrubber.dart';
import 'package:diligent_life/widgets/exercise_route.dart';
import 'package:diligent_life/services/theme_controller.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:diligent_life/widgets/activity_style.dart';
import 'package:diligent_life/widgets/theme_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_map_test.dart' show TestTiles;
import 'exercise_test.dart' show point;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show MemoryRecords;

import 'package:diligent_life/utils/dates.dart';

class PendingGrowth implements GrowthRepository {
  final result = Completer<GrowthSnapshot>();
  @override
  Future<GrowthSnapshot> refresh(DateTime now) => result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  Future<Database> database() => databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
      singleInstance: false,
      onCreate: RecordRepository.createSchema,
    ),
  );
  testWidgets(
    'settings reports step availability without starting or polling the service',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final reminders = ReminderService(await SharedPreferences.getInstance());
      addTearDown(reminders.dispose);
      const channel = MethodChannel('diligent_life/steps');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return {'supported': false};
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      Future<void> render(bool visible) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsScreen(
                reminders: reminders,
                visible: visible,
                onTracking: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(false);
      expect(calls, isEmpty);
      await render(true);
      expect(find.text('이 기기에서는 만보기를 지원하지 않아요.'), findsOneWidget);
      expect(calls, ['status']);
      await tester.pump(const Duration(minutes: 1));
      expect(calls, ['status']);
      await render(false);
      await render(true);
      expect(calls, ['status', 'status']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'portfolio steps follow the selected period without changing stored rows',
    (tester) async {
      final db = await tester.runAsync(() => database());
      addTearDown(() => db!.close());
      final now = DateTime.now();
      final old = DateTime(now.year, now.month - 1, 1);
      await tester.runAsync(() async {
        for (final (date, steps) in [(now, 4321), (old, 9999)]) {
          await db!.insert('daily_steps', {
            'date': dateKey(date),
            'steps': steps,
            'coverage': 'observed',
            'updatedAt': dateKey(date),
          });
        }
      });
      final original = await tester.runAsync(() => db!.query('daily_steps'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendsScreen(
              repository: MemoryRecords(),
              growth: GrowthRepository(db!),
              revision: 0,
            ),
          ),
        ),
      );
      Future<void> settleStorage() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await settleStorage();
      expect(find.text('4,321걸음'), findsOneWidget);
      await tester.tap(find.text('전체'));
      await settleStorage();
      expect(find.text('14,320걸음'), findsOneWidget);
      expect(await tester.runAsync(() => db.query('daily_steps')), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'workout entry survives growth loading and error without duplicate CTA',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = PendingGrowth();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MovementHomeSummary(
              repository: repo,
              visible: true,
              revision: 0,
              workout: FilledButton(
                onPressed: () => opened++,
                child: const Text('운동 시작'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('운동 시작'));
      repo.result.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('걸음과 성장 다시 불러오기'), findsOneWidget);
      await tester.tap(find.text('운동 시작'));
      expect(opened, 2);
      expect(find.text('운동 시작'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'home puts level and steps before CTA and limits preview to unfinished daily quests',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = PendingGrowth();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MovementHomeSummary(
                repository: repo,
                visible: true,
                revision: 0,
                workout: FilledButton(
                  onPressed: () {},
                  child: const Text('운동 시작'),
                ),
              ),
            ),
          ),
        ),
      );
      repo.result.complete(
        const GrowthSnapshot(
          days: [],
          xp: 0,
          unlockedTitles: {},
          achievements: [],
          quests: [
            GoalProgress('quest.daily.steps', '완료한 걸음', 5000, 5000, 30),
            GoalProgress('quest.daily.distance', '남은 거리', 100, 3000, 30),
            GoalProgress('quest.daily.active', '남은 시간', 10, 1800, 30),
            GoalProgress('quest.weekly.count', '주간 퀘스트', 1, 3, 60),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Lv. 1')).dy,
        lessThan(tester.getTopLeft(find.text('오늘 걸음')).dy),
      );
      expect(
        tester.getTopLeft(find.text('오늘 걸음')).dy,
        lessThan(tester.getTopLeft(find.text('운동 시작')).dy),
      );
      expect(find.text('완료한 걸음'), findsNothing);
      expect(find.text('주간 퀘스트'), findsNothing);
      expect(find.text('남은 거리'), findsOneWidget);
      expect(find.text('남은 시간'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'detail summary is below map and above scrubber, both handles keep recorded sample selection',
    (tester) async {
      final points = [
        for (var i = 0; i < 15; i++)
          point(37 + i * .0001, i * 2).withDistance(i * 10),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteScrubber(
                points: points,
                tileProvider: TestTiles(),
                summary: const Text('핵심 통계'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getBottomLeft(find.byType(ExerciseRoute)).dy,
        lessThan(tester.getTopLeft(find.text('핵심 통계')).dy),
      );
      expect(
        tester.getTopLeft(find.text('핵심 통계')).dy,
        lessThan(tester.getTopLeft(find.byType(Slider)).dy),
      );
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(.2, .8),
      );
      await tester.pump();
      final map = tester.widget<ExerciseRoute>(find.byType(ExerciseRoute));
      expect(map.selectedPoint, points[11]);
      expect(map.selectedSection!.points.first, points[3]);
      expect(map.selectedSection!.points.last, points[11]);
      expect(points.last.cumulativeMeters, 140);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 400.0, 600.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'theme choices remain separate, accessible and selectable: $brightness/$width/$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            SharedPreferences.setMockInitialValues({});
            final controller = ThemeController();
            final semantics = tester.ensureSemantics();
            await tester.pumpWidget(
              MaterialApp(
                theme: appTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpace.page),
                    child: ValueListenableBuilder<ThemeMode>(
                      valueListenable: controller,
                      builder: (context, mode, _) => ThemeSelector(
                        value: mode,
                        onChanged: controller.select,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final heading = tester.getRect(find.text('테마'));
            final system = tester.getRect(find.text('시스템 설정 따르기'));
            expect(
              system.top - heading.bottom,
              greaterThanOrEqualTo(AppSpace.large),
            );
            expect(
              find.byType(SegmentedButton<ThemeMode>),
              width >= 528 && scale == 1 ? findsOneWidget : findsNothing,
            );
            for (final option in ThemeSelector.options) {
              final label = find.text(option.$2);
              await tester.ensureVisible(label);
              await tester.tap(label);
              await tester.pumpAndSettle();
              expect(controller.value, option.$1);
              final restored = ThemeController();
              await restored.load();
              expect(restored.value, option.$1);
              restored.dispose();
              expect(tester.takeException(), isNull);
            }
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantics.dispose();
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
          },
        );
      }
    }
    testWidgets(
      'growth progress and locked rewards remain readable at font 2 on 320dp in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const LevelProgress(
                        data: GrowthSnapshot(
                          days: [],
                          xp: 1055,
                          quests: [],
                          achievements: [],
                          unlockedTitles: {},
                          titleId: 'title.five_km.v1',
                        ),
                      ),
                      GoalProgressView(
                        goal: const GoalProgress(
                          'achievement.test',
                          '누적 100,000걸음',
                          20,
                          100000,
                          150,
                        ),
                        achievement: true,
                        onShare: () {},
                      ),
                      GoalProgressView(
                        goal: const GoalProgress(
                          'quest.test',
                          '오늘 5,000걸음',
                          5000,
                          5000,
                          30,
                        ),
                        onShare: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('다음 레벨까지 45 XP'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.byTooltip('누적 100,000걸음 성취 카드'), findsNothing);
        expect(find.byTooltip('오늘 5,000걸음 성취 카드'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
