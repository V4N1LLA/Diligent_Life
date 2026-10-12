import 'package:diligent_life/data/growth_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/services/home_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final calls = <Map<dynamic, dynamic>>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HomeWidget.channel, (call) async {
          calls.add(call.arguments as Map);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HomeWidget.channel, null);
  });
  Future<Database> open() => databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onCreate: RecordRepository.createSchema,
      version: 5,
    ),
  );
  test(
    'committed growth and equipped title publish a privacy-safe snapshot',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = GrowthRepository(db);
      await db.insert('xp_ledger', {
        'rewardKey': 'achievement.first_workout.v1',
        'xp': 250,
        'ruleVersion': 1,
        'earnedAt': '2026-10-08T00:00:00Z',
      });
      final before = await repo.refresh(DateTime(2026, 10, 8));
      expect(calls.last, {
        'level': before.level,
        'title': before.title,
        'questTarget': 5000,
      });
      await repo.equip('title.beginner.v1', before);
      expect(calls.last['title'], '첫 발걸음');
      expect(
        calls.last.keys,
        unorderedEquals(['level', 'title', 'questTarget']),
      );
      expect((await db.query('xp_ledger')).length, 1);
      expect(await db.getVersion(), 5);
    },
  );
  test('launcher failure cannot roll back or fail progression', () async {
    final db = await open();
    addTearDown(db.close);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HomeWidget.channel, (_) async {
          throw PlatformException(code: 'host_unavailable');
        });
    await db.insert('daily_steps', {
      'date': '2026-10-08',
      'steps': 5000,
      'coverage': 'observed',
      'updatedAt': '2026-10-08T00:00:00Z',
    });
    final repo = GrowthRepository(db);
    final first = await repo.refresh(DateTime(2026, 10, 8));
    final again = await repo.refresh(DateTime(2026, 10, 8));
    expect(again.xp, first.xp);
    expect((await db.query('daily_steps')).single['steps'], 5000);
  });
}
