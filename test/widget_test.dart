import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/daily_record.dart';
import 'package:diligent_life/main.dart';
import 'package:diligent_life/screens/today_screen.dart';
import 'package:diligent_life/screens/trends_screen.dart';
import 'package:diligent_life/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diligent_life/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'record_repository_test.dart' show record;

class MemoryRecords implements RecordRepository {
  final records = <String, DailyRecord>{};
  bool failSave = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<DailyRecord?> forDate(String date) async => records[date];
  @override
  Future<void> save(DailyRecord record) async {
    if (failSave) throw StateError('disk full');
    records[record.date] = record;
  }

  @override
  Future<double?> latestWeight(String onOrBefore) async {
    final dates =
        records.keys
            .where(
              (d) =>
                  d.compareTo(onOrBefore) <= 0 && records[d]!.weightKg != null,
            )
            .toList()
          ..sort();
    return dates.isEmpty ? null : records[dates.last]!.weightKg;
  }

  @override
  Future<List<DailyRecord>> list({
    String? since,
    required String until,
  }) async =>
      records.values
          .where(
            (r) =>
                r.date.compareTo(until) <= 0 &&
                (since == null || r.date.compareTo(since) >= 0),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
}

void main() {
  late MemoryRecords repository;
  setUp(() => repository = MemoryRecords());

  Future<void> openToday(WidgetTester tester) async {
    await tester.pumpWidget(
      DiligentLifeApp(
        home: Scaffold(
          body: TodayScreen(repository: repository, onSaved: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  testWidgets('weight only can be saved and edited on the same date', (
    tester,
  ) async {
    await openToday(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '70.5');
    await save(tester);
    expect(find.text('기록을 저장했어요.'), findsOneWidget);
    expect((await repository.forDate(dateKey(DateTime.now())))!.weightKg, 70.5);
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '70.2');
    await save(tester);
    expect(await repository.list(until: dateKey(DateTime.now())), hasLength(1));
    expect((await repository.forDate(dateKey(DateTime.now())))!.weightKg, 70.2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('exercise uses previous weight without adding a measurement', (
    tester,
  ) async {
    await repository.save(
      record(
        dateKey(DateTime.now().subtract(const Duration(days: 1))),
        weight: 70,
      ),
    );
    await openToday(tester);
    await tester.enterText(find.byType(TextFormField).at(1), '30');
    await save(tester);
    final saved = (await repository.forDate(dateKey(DateTime.now())))!;
    expect(saved.weightKg, isNull);
    expect(saved.estimatedCalories, closeTo(102.9, .001));
  });
  testWidgets('empty save gives gentle feedback without writing data', (
    tester,
  ) async {
    await openToday(tester);
    await save(tester);
    expect(find.text('몸무게 또는 운동 시간을 입력해 주세요.'), findsOneWidget);
    expect(await repository.list(until: dateKey(DateTime.now())), isEmpty);
  });
  testWidgets('trends display an empty state', (tester) async {
    await tester.pumpWidget(
      DiligentLifeApp(
        home: Scaffold(body: TrendsScreen(repository: repository, revision: 0)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('아직 이 기간의 기록이 없어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single record charts render on a narrow dark screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await repository.save(record(dateKey(DateTime.now())));
    await tester.pumpWidget(
      DiligentLifeApp(
        home: Scaffold(body: TrendsScreen(repository: repository, revision: 0)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('70.0 kg'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('예상 소모 칼로리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text on a narrow screen still allows saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openToday(tester);
    await tester.enterText(find.byType(TextFormField).first, '68');
    await save(tester);
    expect((await repository.forDate(dateKey(DateTime.now())))!.weightKg, 68);
    expect(tester.takeException(), isNull);
  });
  testWidgets('numeric keyboards and next/done follow input order', (
    tester,
  ) async {
    await openToday(tester);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(
      fields[0].keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(fields[1].keyboardType, TextInputType.number);
    expect(
      fields[2].keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    await tester.enterText(find.byKey(const ValueKey('weight')), '70');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(fields[1].focusNode!.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(fields[2].focusNode!.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fields[2].focusNode!.hasFocus, isFalse);
  });

  testWidgets('exercise without any previous weight is not stored', (
    tester,
  ) async {
    await openToday(tester);
    await tester.enterText(find.byKey(const ValueKey('minutes')), '30');
    await save(tester);
    expect(repository.records, isEmpty);
    expect(find.text('칼로리 계산에 사용할 몸무게를 한 번 입력해 주세요.'), findsOneWidget);
  });

  for (final (field, value) in [
    ('weight', 'NaN'),
    ('weight', '0'),
    ('weight', 'Infinity'),
    ('minutes', 'abc'),
    ('minutes', '1.5'),
    ('minutes', '-1'),
    ('minutes', '1441'),
    ('distance', '-1'),
  ]) {
    testWidgets('invalid $field input $value cannot be saved', (tester) async {
      await openToday(tester);
      await tester.enterText(find.byKey(const ValueKey('weight')), '70');
      final target = find.byKey(ValueKey(field));
      await tester.ensureVisible(target);
      await tester.enterText(target, value);
      await save(tester);
      expect(repository.records, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'zero time shows zero calories and optional distance stays null',
    (tester) async {
      await openToday(tester);
      await tester.enterText(find.byKey(const ValueKey('weight')), '70,5');
      await tester.enterText(find.byKey(const ValueKey('minutes')), '0');
      await save(tester);
      final saved = repository.records.values.single;
      expect(saved.estimatedCalories, 0);
      expect(saved.distanceKm, isNull);
      expect(saved.weightKg, 70.5);
    },
  );

  testWidgets('failed save preserves inputs and retry succeeds', (
    tester,
  ) async {
    repository.failSave = true;
    await openToday(tester);
    await tester.enterText(find.byKey(const ValueKey('weight')), '71');
    await save(tester);
    expect(repository.records, isEmpty);
    expect(find.text('71'), findsOneWidget);
    repository.failSave = false;
    await save(tester);
    expect(repository.records.values.single.weightKg, 71);
  });

  testWidgets('30/year/all weight filters preserve measurement gaps', (
    tester,
  ) async {
    final now = dayOnly(DateTime.now());
    String ago(int days) =>
        dateKey(DateTime(now.year, now.month, now.day - days));
    for (final days in [0, 6, 7, 29, 30]) {
      await repository.save(
        record(
          ago(days),
          duration: days == 0 ? 0 : 30,
          calories: days == 0 ? 0 : 102.9,
          distance: null,
        ),
      );
    }
    await tester.pumpWidget(
      DiligentLifeApp(
        home: Scaffold(body: TrendsScreen(repository: repository, revision: 0)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 30일'));
    await tester.pumpAndSettle();
    List<FlSpot> points() => tester
        .widget<LineChart>(find.byType(LineChart).first)
        .data
        .lineBarsData
        .first
        .spots;
    expect(points().where((s) => !s.isNull()), hasLength(4));
    expect(points().where((s) => s.isNull()), hasLength(2));
    await tester.tap(find.text('최근 30일'));
    await tester.pumpAndSettle();
    expect(points().where((s) => !s.isNull()), hasLength(4));
    await tester.tap(find.text('전체'));
    await tester.pumpAndSettle();
    expect(points().where((s) => !s.isNull()), hasLength(5));
    final weightChart = tester
        .widget<LineChart>(find.byType(LineChart).first)
        .data;
    expect(weightChart.maxY - weightChart.minY, greaterThanOrEqualTo(2));
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(points().where((s) => !s.isNull()).every((s) => s.y == 70), isTrue);
  });
  for (final brightness in Brightness.values) {
    testWidgets('all tabs fit 320px at 2x text in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      SharedPreferences.setMockInitialValues({});
      final reminders = ReminderService(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        DiligentLifeApp(
          home: AppShell(repository: repository, reminders: reminders),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['포트폴리오', '설정', '오늘']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('몸무게').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      reminders.dispose();
    });
  }

  testWidgets(
    'small screen keyboard leaves save reachable and tab change dismisses focus',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      SharedPreferences.setMockInitialValues({});
      final reminders = ReminderService(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        DiligentLifeApp(
          home: AppShell(repository: repository, reminders: reminders),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('몸무게'));
      await tester.tap(find.text('몸무게'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('quick-weight')), '70');
      await tester.ensureVisible(find.text('몸무게 저장'));
      await tester.tap(find.text('몸무게 저장'));
      await tester.pumpAndSettle();
      expect(repository.records.values.single.weightKg, 70);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('설정'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      reminders.dispose();
    },
  );
  testWidgets('saved today opens as an edit with previous inputs', (
    tester,
  ) async {
    await repository.save(
      record(dateKey(DateTime.now()), weight: 69.4, distance: null),
    );
    await openToday(tester);
    expect(find.text('기록 수정하기'), findsOneWidget);
    expect(find.textContaining('저장된 기록'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('weight')))
          .controller!
          .text,
      '69.4',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('minutes')))
          .controller!
          .text,
      '30',
    );
  });
}
