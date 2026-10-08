import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:diligent_life/data/backup_repository.dart';
import 'package:diligent_life/data/character_repository.dart';
import 'package:diligent_life/data/growth_repository.dart';
import 'package:diligent_life/data/record_repository.dart';
import 'package:diligent_life/models/character.dart';
import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/models/exercise_type.dart';
import 'package:diligent_life/screens/profile_screen.dart';
import 'package:diligent_life/services/profile_share.dart';
import 'package:diligent_life/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LoadedCharacter extends CharacterRepository {
  LoadedCharacter(super.database, this.data);
  final CharacterSnapshot data;
  @override
  Future<CharacterSnapshot> refresh([DateTime? at]) async => data;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 10, 8, 12);
  Future<Database> open([int version = 5]) => databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: false,
      onCreate: RecordRepository.createSchema,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
    ),
  );
  Future<void> seed(Database db) async {
    await db.insert('daily_steps', {
      'date': '2026-10-08',
      'steps': 5500,
      'coverage': 'observed',
      'updatedAt': now.toIso8601String(),
    });
    await db.insert(
      'exercise_sessions',
      ExerciseSession(
        id: 1,
        startedAt: now,
        updatedAt: now,
        type: ExerciseType.lightWalk,
        status: SessionStatus.finished,
        elapsedSeconds: 1800,
        distanceMeters: 50000,
      ).toMap(),
    );
    for (var i = 0; i < 10; i++) {
      final id = 'wm17.${65000 + i}.50000.v1';
      await db.insert('exploration_events', {
        'eventKey': 'exploration:$id',
        'regionId': id,
        'modelVersion': 1,
        'discoveredAt': now.toUtc().toIso8601String(),
      });
    }
  }

  Future<void> clean(File f) => f.parent.delete(recursive: true);

  test('profile refresh preserves XP and raw data; concurrent unlocks and inbox are unique', () async {
    final db = await open();
    addTearDown(db.close);
    await seed(db);
    final before = await GrowthRepository(db).refresh(now);
    final ledger = await db.query('xp_ledger');
    final repo = CharacterRepository(db);
    final profile = await repo.refresh(now);
    await Future.wait(List.generate(8, (_) => repo.refresh(now)));
    expect((await repo.refresh(now)).growth.xp, before.xp);
    expect(await db.query('xp_ledger'), ledger);
    expect(profile.regions, 10);
    expect(profile.steps, 5500);
    expect(
      profile.unlocked,
      containsAll([
        'frame.walking.v1',
        'emblem.explorer.v1',
        'background.dawn.v1',
      ]),
    );
    final rows = await db.query('character_progress');
    expect(rows.map((r) => r['progressKey']).toSet().length, rows.length);
    expect(
      (await db.query('exercise_sessions')).single['distanceMeters'],
      50000,
    );
    expect(await db.query('raw_route_points'), isEmpty);
  });
  test('locked/unknown cosmetics cannot equip; persisted unlocks survive source deletion', () async {
    final db = await open();
    addTearDown(db.close);
    final repo = CharacterRepository(db);
    await repo.refresh(now);
    await expectLater(repo.equip('frame.level.v1'), throwsArgumentError);
    await expectLater(repo.equip('unknown'), throwsArgumentError);
    await seed(db);
    await repo.refresh(now);
    await repo.equip('frame.walking.v1');
    await db.delete('exercise_sessions');
    final restored = await CharacterRepository(db).refresh(now);
    expect(restored.selection(CosmeticSlot.frame), 'frame.walking.v1');
  });
  test('level 5/10 boundaries and already earned achievements unlock without extra XP', () async {
    final db = await open();
    addTearDown(db.close);
    final repo = CharacterRepository(db);
    await db.insert('xp_ledger', {
      'rewardKey': 'fixture.v1',
      'xp': 1099,
      'ruleVersion': 1,
      'earnedAt': now.toUtc().toIso8601String(),
    });
    expect(
      (await repo.refresh(now)).unlocked,
      isNot(contains('accent.purple.v1')),
    );
    await db.update('xp_ledger', {'xp': 1100});
    expect((await repo.refresh(now)).unlocked, contains('accent.purple.v1'));
    await db.update('xp_ledger', {'xp': 3599});
    expect(
      (await repo.refresh(now)).unlocked,
      isNot(contains('frame.level.v1')),
    );
    await db.update('xp_ledger', {'xp': 3600});
    final data = await repo.refresh(now);
    expect(data.unlocked, contains('frame.level.v1'));
    expect(data.growth.xp, 3600);
    expect(data.rewards.where((r) => r.key == 'reward:level:10').length, 1);
  });
  test(
    'acknowledgement is idempotent and persists across repository restart',
    () async {
      final db = await open();
      addTearDown(db.close);
      await seed(db);
      final repo = CharacterRepository(db);
      final data = await repo.refresh(now);
      expect(data.unread, greaterThan(0));
      final keys = data.rewards.map((r) => r.key).toList();
      await repo.acknowledge(keys);
      await repo.acknowledge(keys);
      expect((await CharacterRepository(db).refresh(now)).unread, 0);
    },
  );
  for (final old in [1, 4]) {
    test(
      'schema $old to 5 adds only character storage and preserves existing rows',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'character-migration',
        );
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/db';
        var db = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: old,
            singleInstance: false,
            onCreate: RecordRepository.createSchema,
          ),
        );
        if (old == 4) await seed(db);
        final before = old == 4 ? await db.query('exercise_sessions') : [];
        await db.close();
        db = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 5,
            singleInstance: false,
            onUpgrade: RecordRepository.upgradeSchema,
          ),
        );
        addTearDown(db.close);
        expect(await db.getVersion(), 5);
        expect(await db.query('exercise_sessions'), before);
        expect(await db.query('character_progress'), isEmpty);
        await CharacterRepository(db).refresh(now);
      },
    );
  }
  test('v3 backup roundtrip keeps cosmetics, equipment, read rewards and all existing tables', () async {
    final db = await open();
    addTearDown(db.close);
    await seed(db);
    final repo = CharacterRepository(db);
    final data = await repo.refresh(now);
    await repo.equip('emblem.explorer.v1');
    await repo.acknowledge([data.rewards.first.key]);
    final before = await db.query('character_progress', orderBy: 'id');
    final file = await BackupRepository(db).export();
    addTearDown(() => clean(file));
    expect(jsonDecode(file.readAsLinesSync().first)['version'], 3);
    final target = await open();
    addTearDown(target.close);
    final backup = await BackupRepository(target).prepare(file);
    addTearDown(backup.dispose);
    await BackupRepository(target).replace(backup);
    for (final table in [
      ...backupTables,
      ...growthBackupTables,
      ...characterBackupTables,
    ]) {
      expect(
        await target.query(table, orderBy: 'id'),
        await db.query(table, orderBy: 'id'),
        reason: table,
      );
    }
    expect(
      (await CharacterRepository(target).refresh(now))
          .selection(CosmeticSlot.emblem),
      'emblem.explorer.v1',
    );
    expect(await target.query('character_progress', orderBy: 'id'), before);
  });
  for (final version in [3, 4]) {
    test(
      'legacy schema $version backup restores into 5 without stale character state',
      () async {
        final source = await open(version);
        addTearDown(source.close);
        if (version == 4) await seed(source);
        final f = await BackupRepository(source).export();
        addTearDown(() => clean(f));
        final db = await open();
        addTearDown(db.close);
        await seed(db);
        final repo = CharacterRepository(db);
        await repo.refresh(now);
        await repo.equip('frame.walking.v1');
        final backups = BackupRepository(db);
        final staged = await backups.prepare(f);
        addTearDown(staged.dispose);
        await backups.replace(staged);
        expect(await db.query('character_progress'), isEmpty);
        expect(
          (await repo.refresh(now)).selection(CosmeticSlot.frame),
          'frame.none.v1',
        );
      },
    );
  }
  test(
    'malformed cosmetic backup is rejected before replacing live data',
    () async {
      final source = await open();
      addTearDown(source.close);
      await source.insert('character_progress', {
        'progressKey': 'equip:frame',
        'kind': 'equip',
        'value': 'accent.purple.v1',
        'ruleVersion': 1,
        'createdAt': now.toIso8601String(),
        'seen': 1,
      });
      final file = await BackupRepository(source).export();
      addTearDown(() => clean(file));
      final target = await open();
      addTearDown(target.close);
      await seed(target);
      final before = await target.query('exercise_sessions');
      await expectLater(
        BackupRepository(target).prepare(file),
        throwsFormatException,
      );
      expect(await target.query('exercise_sessions'), before);
    },
  );
  test(
    'restored locked equipment without matching unlock falls back safely',
    () async {
      final db = await open();
      addTearDown(db.close);
      await db.insert('character_progress', {
        'progressKey': 'equip:frame',
        'kind': 'equip',
        'value': 'frame.level.v1',
        'ruleVersion': 1,
        'createdAt': now.toIso8601String(),
        'seen': 1,
      });
      expect(
        (await CharacterRepository(db).refresh(now))
            .selection(CosmeticSlot.frame),
        'frame.none.v1',
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'profile $brightness at 320dp font 2 has no overflow and locked options are disabled',
      (tester) async {
        final db = (await tester.runAsync(open))!;
        addTearDown(db.close);
        final data = (await tester.runAsync(
          () => CharacterRepository(db).refresh(now),
        ))!;
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: ProfileScreen(repository: LoadedCharacter(db, data)),
          ),
        );
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump();
        }
        expect(find.text('나의 프로필'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('라일락'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final locked = tester.widget<ListTile>(
          find.ancestor(of: find.text('라일락'), matching: find.byType(ListTile)),
        );
        expect(locked.onTap, isNull);
        expect(locked.enabled, isFalse);
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text('라일락'),
                  matching: find.byType(ListTile),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        for (var i = 0; i < 22; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -350));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'profile share $brightness is 720 square and contains only allowlisted stats',
      (tester) async {
        final db = (await tester.runAsync(open))!;
        addTearDown(db.close);
        await tester.runAsync(() => seed(db));
        final data = (await tester.runAsync(
          () => CharacterRepository(db).refresh(now),
        ))!;
        expect(profileShareLabels(data), hasLength(5));
        expect(profileShareLabels(data).join(), isNot(contains('wm17')));
        expect(profileShareLabels(data).join(), isNot(contains('kg')));
        final bytes = await tester.runAsync(
          () => profileShareImage(data, brightness),
        );
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(bytes!);
          final image = (await codec.getNextFrame()).image;
          expect(image.width, 720);
          expect(image.height, 720);
          image.dispose();
          codec.dispose();
        });
      },
    );
  }
}
