import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diligent_life/main.dart';
import 'package:diligent_life/screens/settings_screen.dart';
import 'package:diligent_life/screens/today_home.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/screens/report_screen.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/services/reminder_service.dart';
import 'package:diligent_life/theme/app_theme.dart';

import 'widget_test.dart' show MemoryRecords;
import 'exercise_widget_test.dart' show MemoryExerciseRepository;
import 'exercise_test.dart' show FakeLocation;
import 'report_widget_test.dart' show Reports;
import 'portfolio_test.dart' show PortfolioExercises;

import 'package:diligent_life/screens/all_time_map_screen.dart';

void main() {
  testWidgets(
    'All-time Map failure offers retry without an empty-state claim',
    (tester) async {
      final repo = PortfolioExercises()..fail = true;
      await tester.pumpWidget(
        DiligentLifeApp(home: AllTimeMapScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('운동을 기록하면 지나온 길이 여기에 모여요.'), findsNothing);
      repo.fail = false;
      await tester.tap(find.text('지도를 불러오지 못했어요. 다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('운동을 기록하면 지나온 길이 여기에 모여요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'release accessibility: today, exercise, settings and report in $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();

        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final reminders = ReminderService(prefs);
        final location = FakeLocation();
        final recorder = ExerciseRecorder(
          MemoryExerciseRepository(),
          location: location,
        );
        final records = MemoryRecords();
        final screens = <Widget>[
          Scaffold(
            body: TodayHome(
              repository: records,
              recorder: recorder,
              revision: 0,
              onSaved: () {},
              openExercise: () {},
            ),
          ),
          ExerciseScreen(recorder: recorder, records: records),
          Scaffold(
            body: SettingsScreen(reminders: reminders, onBackup: () {}),
          ),
          ReportScreen(
            repository: Reports()..empty = true,
            now: DateTime(2026, 9, 22),
          ),
        ];
        for (final screen in screens) {
          await tester.pumpWidget(
            DiligentLifeApp(
              home: Theme(data: appTheme(brightness), child: screen),
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
        semantics.dispose();
        recorder.dispose();
        reminders.dispose();
        await location.controller.close();
        await location.service.close();
      },
    );
  }
}
