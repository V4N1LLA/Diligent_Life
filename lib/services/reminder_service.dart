import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

tz.TZDateTime nextReminder(tz.TZDateTime now, int hour, int minute) {
  var next = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  if (!next.isAfter(now)) {
    next = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day + 1,
      hour,
      minute,
    );
  }
  return next;
}

class ReminderService extends ChangeNotifier {
  ReminderService(this.preferences);
  final SharedPreferences preferences;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool busy = false;
  String? error;
  bool get enabled => preferences.getBool('reminder_enabled') ?? false;
  TimeOfDay get time => TimeOfDay(
    hour: preferences.getInt('reminder_hour') ?? 20,
    minute: preferences.getInt('reminder_minute') ?? 0,
  );

  Future<void> _initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> _allowed({required bool request}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      return (request
              ? await android.requestNotificationsPermission()
              : await android.areNotificationsEnabled()) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()!;
      if (request) {
        return await ios.requestPermissions(
              alert: true,
              sound: true,
              badge: false,
            ) ??
            false;
      }
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  Future<void> _schedule(
    TimeOfDay selected, {
    bool onlyIfMissing = false,
  }) async {
    final local = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(local.identifier));
    if (onlyIfMissing &&
        preferences.getString('reminder_timezone') == local.identifier &&
        (await _plugin.pendingNotificationRequests()).any(
          (item) => item.id == 1,
        )) {
      // Preserve today's possibly delayed inexact alarm when resuming the app.
      return;
    }
    await _plugin.zonedSchedule(
      id: 1,
      title: 'Diligent Life',
      body: '오늘의 기록을 남겨볼까요?',
      scheduledDate: nextReminder(
        tz.TZDateTime.now(tz.local),
        selected.hour,
        selected.minute,
      ),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_record',
          '매일 기록 알림',
          channelDescription: '설정한 시간에 기록을 알려드려요.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentBadge: false),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    if (!await preferences.setString('reminder_timezone', local.identifier)) {
      throw StateError('Could not persist reminder timezone');
    }
  }

  // Called at startup/resume, including after system permission/timezone changes.
  Future<void> restore() async {
    if (busy || !enabled) return;
    busy = true;
    notifyListeners();
    try {
      await _initialize();
      if (await _allowed(request: false)) {
        await _schedule(time, onlyIfMissing: true);
        error = null;
      } else {
        await _plugin.cancel(id: 1);
        await preferences.setBool('reminder_enabled', false);
        error = '기기 설정에서 알림 권한을 확인해 주세요.';
      }
    } catch (_) {
      error = '알림을 준비하지 못했어요. 설정에서 다시 시도해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> update({required bool enable, TimeOfDay? selectedTime}) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    final previousTime = time;
    final wasEnabled = enabled;
    try {
      await _initialize();
      final selected = selectedTime ?? time;
      if (enable) {
        if (!await _allowed(request: !wasEnabled)) {
          await _plugin.cancel(id: 1);
          await preferences.setBool('reminder_enabled', false);
          error = '알림 권한이 꺼져 있어요. 기기 설정에서 허용한 뒤 다시 켜주세요.';
          return;
        }
        await _schedule(selected);
      } else {
        await _plugin.cancel(id: 1);
      }
      if (!await preferences.setInt('reminder_hour', selected.hour) ||
          !await preferences.setInt('reminder_minute', selected.minute) ||
          !await preferences.setBool('reminder_enabled', enable)) {
        throw StateError('Could not persist reminder settings');
      }
    } catch (_) {
      error = '알림 설정을 저장하지 못했어요. 다시 시도해 주세요.';
      try {
        if (wasEnabled) {
          await _schedule(previousTime);
        } else {
          await _plugin.cancel(id: 1);
        }
        await preferences.setInt('reminder_hour', previousTime.hour);
        await preferences.setInt('reminder_minute', previousTime.minute);
        await preferences.setBool('reminder_enabled', wasEnabled);
      } catch (_) {
        error = '알림 상태를 확인하지 못했어요. 다시 설정해 주세요.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
