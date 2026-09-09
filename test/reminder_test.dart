import 'package:diligent_life/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  data.initializeTimeZones();
  final seoul = tz.getLocation('Asia/Seoul');
  test('upcoming time is scheduled today', () {
    final next = nextReminder(tz.TZDateTime(seoul, 2026, 9, 9, 19), 20, 0);
    expect(next, tz.TZDateTime(seoul, 2026, 9, 9, 20));
  });
  test('equal/past time advances across year boundary', () {
    final next = nextReminder(tz.TZDateTime(seoul, 2026, 12, 31, 20), 20, 0);
    expect(next, tz.TZDateTime(seoul, 2027, 1, 1, 20));
  });
  test('daylight saving keeps the selected wall clock hour', () {
    final ny = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(ny, 2026, 3, 7, 21);
    final next = nextReminder(now, 20, 0);
    expect(next.hour, 20);
    expect(next.day, 8);
    expect(next.difference(now).inHours, 22);
  });
}
