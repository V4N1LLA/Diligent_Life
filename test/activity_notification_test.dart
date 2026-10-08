import 'dart:collection';

import 'package:diligent_life/main.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/exercise_screen.dart';
import 'package:diligent_life/services/activity_notifications.dart';
import 'package:diligent_life/services/exercise_recorder.dart';
import 'package:diligent_life/services/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_widget_test.dart' show MemoryExerciseRepository;
import 'widget_test.dart' show MemoryRecords;

class NoticeRecorder extends ExerciseRecorder {
  NoticeRecorder() : super(MemoryExerciseRepository());
  int pauses = 0, resumes = 0, seconds = 0;
  @override
  int get elapsedSeconds => seconds;
  void snapshot({
    SessionStatus status = SessionStatus.recording,
    int id = 1,
    double meters = 100,
  }) {
    session = ExerciseSession(
      id: id,
      startedAt: DateTime.utc(2026, 10, 8),
      updatedAt: DateTime.utc(2026, 10, 8),
      type: ExerciseType.lightWalk,
      status: status,
      distanceMeters: meters,
    );
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauses++;
    snapshot(status: SessionStatus.paused);
  }

  @override
  Future<void> resume() async {
    resumes++;
    snapshot();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('diligent_life/activity_notifications');
  final messages = <Map<dynamic, dynamic>?>[];
  final pending = Queue<Map<String, String>>();
  bool denied = false;
  setUp(() {
    messages.clear();
    pending.clear();
    denied = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'takeAction') {
            return pending.isEmpty ? null : pending.removeFirst();
          }
          if (call.method == 'workout') {
            if (denied) throw PlatformException(code: 'permission');
            messages.add(call.arguments as Map<dynamic, dynamic>?);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'compact clocks and pace include hours, empty route and average semantics',
    () {
      expect(notificationClock(29 * 60 + 12), '29:12');
      expect(notificationClock(3601), '1:00:01');
      final r = NoticeRecorder();
      r.seconds = 1800;
      r.snapshot(meters: 5000);
      expect(workoutNotificationDetail(r.live!), '5.00 km · 30:00\n06:00 /km');
      r.snapshot(meters: 0);
      expect(workoutNotificationDetail(r.live!), contains('페이스 —'));
      r.dispose();
    },
  );

  testWidgets(
    'GPS-like bursts coalesce; status flushes and idle/paused have no repeating timer',
    (tester) async {
      final r = NoticeRecorder();
      var elapsed = Duration.zero, sequence = 0;
      final c = ActivityNotificationController(
        r,
        onNavigate: (_) async {},
        elapsed: () => elapsed,
        tokenFactory: () => 'token-${++sequence}',
      )..start();
      addTearDown(() {
        c.dispose();
        r.dispose();
      });
      await tester.pump();
      expect(messages, [null]);
      r.snapshot();
      await tester.pump();
      final token = messages.last!['token'];
      messages.clear();
      for (var i = 1; i < 15; i++) {
        elapsed = Duration(seconds: i);
        r.seconds = i;
        r.snapshot(meters: 100 + i.toDouble());
      }
      await tester.pump();
      expect(messages, isEmpty);
      elapsed = const Duration(seconds: 15);
      await tester.pump(const Duration(seconds: 15));
      expect(messages, hasLength(1));
      expect(messages.single!['token'], token);
      expect(messages.single!['detail'], contains('0.11 km'));
      r.snapshot(status: SessionStatus.paused);
      await tester.pump();
      expect(messages.last!['recording'], false);
      expect(messages.last!['token'], isNot(token));
      final count = messages.length;
      await tester.pump(const Duration(hours: 1));
      expect(messages, hasLength(count));
      r.snapshot(status: SessionStatus.finished);
      await tester.pump();
      expect(messages.last, isNull);
      await tester.pump(const Duration(hours: 1));
      expect(messages.last, isNull);
    },
  );

  testWidgets(
    'duplicate, stale generation/session and restored-process controls are ignored',
    (tester) async {
      final r = NoticeRecorder();
      var sequence = 0;
      final destinations = <String>[];
      final c = ActivityNotificationController(
        r,
        onNavigate: (s) async => destinations.add(s),
        tokenFactory: () => 'generation-${++sequence}',
      )..start();
      addTearDown(() {
        c.dispose();
        r.dispose();
      });
      r.snapshot();
      await tester.pump();
      final first = messages.last!['token'] as String;
      await c.handleAction({'action': 'pause', 'token': first});
      await tester.pump();
      await c.handleAction({'action': 'pause', 'token': first});
      expect(r.pauses, 1);
      final paused = messages.last!['token'] as String;
      await c.handleAction({'action': 'resume', 'token': paused});
      await tester.pump();
      await c.handleAction({'action': 'pause', 'token': first});
      await c.handleAction({'action': 'resume', 'token': paused});
      expect(r.pauses, 1);
      expect(r.resumes, 1);
      final previousSession = messages.last!['token'] as String;
      r.snapshot(id: 2);
      await tester.pump();
      await c.handleAction({'action': 'pause', 'token': previousSession});
      await c.handleAction({'action': 'exercise', 'token': previousSession});
      await c.handleAction({'action': 'pause', 'token': ''});
      expect(r.pauses, 1);
      expect(destinations, isEmpty);
      await c.handleAction({'action': 'exercise', 'token': ''});
      await c.handleAction({'action': 'today', 'token': ''});
      await c.handleAction({'action': 'profile', 'token': ''});
      await c.handleAction({'action': 'growth', 'token': ''});
      expect(destinations, ['exercise', 'today', 'profile', 'growth']);
      expect(r.resumes, 1); // Exercise entry never starts recording.
      c.dispose();
      final restored = ActivityNotificationController(
        r,
        onNavigate: (_) async {},
        tokenFactory: () => 'restored',
      )..start();
      await tester.pump();
      await restored.handleAction({
        'action': 'pause',
        'token': previousSession,
      });
      expect(r.pauses, 1);
      restored.dispose();
    },
  );

  testWidgets(
    'permission failure does not poison subsequent updates; dispose cancels dirty trailing render',
    (tester) async {
      final r = NoticeRecorder();
      var elapsed = Duration.zero;
      final c = ActivityNotificationController(
        r,
        onNavigate: (_) async {},
        elapsed: () => elapsed,
      )..start();
      denied = true;
      r.snapshot();
      await tester.pump();
      expect(r.recording, true);
      expect(tester.takeException(), isNull);
      denied = false;
      r.snapshot(status: SessionStatus.paused);
      await tester.pump();
      expect(messages.last!['recording'], false);
      r.snapshot();
      await tester.pump();
      elapsed = const Duration(seconds: 1);
      r.snapshot(meters: 200);
      c.dispose();
      final count = messages.length;
      await tester.pump(const Duration(seconds: 60));
      expect(messages, hasLength(count));
      r.dispose();
    },
  );

  testWidgets(
    'cold notification exercise entry opens chooser without starting GPS, Today returns home',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final recorder = NoticeRecorder();
      pending.add({'action': 'exercise', 'token': ''});
      await tester.pumpWidget(
        DiligentLifeApp(
          home: AppShell(
            repository: MemoryRecords(),
            reminders: ReminderService(prefs),
            recorder: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseScreen), findsOneWidget);
      expect(recorder.active, false);
      pending.add({'action': 'today', 'token': ''});
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pending'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseScreen), findsNothing);
      expect(find.text('오늘의 움직임'), findsOneWidget);
      await tester.pumpWidget(const DiligentLifeApp(home: SizedBox()));
      recorder.dispose();
    },
  );
}
