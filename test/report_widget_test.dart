import 'package:diligent_life/data/report_repository.dart';
import 'package:diligent_life/models/activity_report.dart';
import 'package:diligent_life/screens/report_screen.dart';
import 'package:diligent_life/screens/portfolio_share_screen.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_report_test.dart' show entry;
import 'exercise_map_test.dart' show TestTiles;

class Reports implements ReportRepository {
  bool fail = false;
  bool empty = false;
  int invalidated = 0;
  ReportPeriod? lastPeriod;
  DateTime? lastAnchor;
  @override
  void invalidate() {
    invalidated++;
  }

  @override
  Future<ActivityReport> load(
    ReportPeriod period,
    DateTime anchor,
    DateTime now,
  ) async {
    lastPeriod = period;
    lastAnchor = anchor;
    if (fail) throw StateError('read failed');
    return buildActivityReport(
      ReportWindow(period, anchor, now),
      empty
          ? []
          : [
              entry(1, DateTime(2026, 8, 1)),
              entry(2, DateTime(2026, 8, 2)),
              entry(3, DateTime(2026, 9, 1), meters: 1180),
              entry(4, DateTime(2026, 9, 2), meters: 1180),
            ],
      [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'report periods and populated sections fit 320px at 2x in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = Reports();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ReportScreen(repository: repo, now: DateTime(2026, 9, 15)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('18% 증가'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('주간'));
        await tester.pumpAndSettle();
        expect(repo.lastPeriod, ReportPeriod.week);
        await tester.tap(find.byTooltip('이전 리포트'));
        await tester.pumpAndSettle();
        expect(repo.lastAnchor, DateTime(2026, 9, 7));
        await tester.tap(find.text('연간'));
        await tester.pumpAndSettle();
        expect(repo.lastPeriod, ReportPeriod.year);
        await tester.scrollUntilVisible(find.text('리포트 이미지 공유'), 250);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('failed report can retry and empty data remains usable', (
    tester,
  ) async {
    final repo = Reports()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ReportScreen(repository: repo, now: DateTime(2026, 9, 15)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('리포트를 불러오지 못했어요. 다시 시도'), findsOneWidget);
    repo
      ..fail = false
      ..empty = true;
    await tester.tap(find.text('리포트를 불러오지 못했어요. 다시 시도'));
    await tester.pumpAndSettle();
    expect(find.textContaining('비교하기에는 데이터 부족'), findsOneWidget);
    await tester.tap(find.byTooltip('리포트 새로고침'));
    await tester.pumpAndSettle();
    expect(repo.invalidated, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'report share preview retries and discloses weight without sharing location',
    (tester) async {
      bool fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PortfolioShareScreen.report(
            title: '주간 활동 리포트',
            image: () async {
              if (fail) throw StateError('encode failed');
              return TestTiles().image.bytes;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('카드 생성 다시 시도'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('카드 생성 다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('리포트 공유'), findsOneWidget);
      expect(find.textContaining('몸무게 변화가 포함'), findsOneWidget);
      expect(find.textContaining('경로 위치는 포함하지'), findsOneWidget);
      expect(find.text('이미지 공유'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
