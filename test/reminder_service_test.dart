import 'package:diligent_life/services/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  final pending = <int, Map<String, Object?>>{};
  late ReminderService service;
  bool allowed = true;
  bool failSchedule = false;
  String zone = 'Asia/Seoul';
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    service = ReminderService(await SharedPreferences.getInstance());
    allowed = true;
    failSchedule = false;
    zone = 'Asia/Seoul';
    calls.clear();
    pending.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'requestNotificationsPermission':
            case 'areNotificationsEnabled':
              return allowed;
            case 'zonedSchedule':
              if (failSchedule) {
                throw PlatformException(code: 'schedule_failed');
              }
              final args = Map<String, Object?>.from(call.arguments as Map);
              pending[args['id'] as int] = args;
              return null;
            case 'cancel':
              pending.remove((call.arguments as Map)['id']);
              return null;
            case 'pendingNotificationRequests':
              return pending.keys
                  .map(
                    (id) => {
                      'id': id,
                      'title': 'Diligent Life',
                      'body': '오늘의 기록을 남겨볼까요?',
                      'payload': null,
                    },
                  )
                  .toList();
          }
          throw StateError('Unexpected call ${call.method}');
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezone, (_) async => zone);
  });
  tearDown(() {
    service.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezone, null);
  });
  test(
    'default OFF restore does not initialize or request permission',
    () async {
      await service.restore();
      expect(service.enabled, isFalse);
      expect(calls, isEmpty);
      expect(service.time, const TimeOfDay(hour: 20, minute: 0));
    },
  );
  test(
    'ON asks permission once; time change replaces ID; OFF cancels',
    () async {
      await service.update(enable: true);
      expect(service.error, isNull);
      expect(service.enabled, isTrue);
      await service.update(
        enable: true,
        selectedTime: const TimeOfDay(hour: 21, minute: 15),
      );
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
      expect(pending.keys, [1]);
      expect(pending[1]!['scheduledDateTime'], contains('21:15:00'));
      expect(pending[1]!['timeZoneName'], 'Asia/Seoul');
      await service.update(enable: false);
      expect(service.enabled, isFalse);
      expect(pending, isEmpty);
    },
  );
  test('denial leaves OFF without scheduling', () async {
    allowed = false;
    await service.update(enable: true);
    expect(service.enabled, isFalse);
    expect(service.error, isNotNull);
    expect(pending, isEmpty);
  });
  test(
    'changing time while OFF never requests permission or schedules',
    () async {
      await service.update(
        enable: false,
        selectedTime: const TimeOfDay(hour: 8, minute: 30),
      );
      expect(service.time.hour, 8);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        isEmpty,
      );
      expect(pending, isEmpty);
    },
  );
  test(
    'resume preserves a pending alarm; timezone change reschedules local hour',
    () async {
      await service.update(enable: true);
      calls.clear();
      await service.restore();
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      zone = 'America/New_York';
      await service.restore();
      expect(pending[1]!['timeZoneName'], zone);
      expect(pending[1]!['scheduledDateTime'], contains('20:00:00'));
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        isEmpty,
      );
    },
  );
  test('external permission revocation cancels pending reminder', () async {
    await service.update(enable: true);
    allowed = false;
    await service.restore();
    expect(service.enabled, isFalse);
    expect(pending, isEmpty);
  });
  test('failed scheduling never enables reminder', () async {
    failSchedule = true;
    await service.update(enable: true);
    expect(service.enabled, isFalse);
    expect(service.busy, isFalse);
    expect(service.error, isNotNull);
    expect(pending, isEmpty);
  });
}
