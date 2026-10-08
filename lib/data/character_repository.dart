import 'package:sqflite/sqflite.dart';

import '../models/character.dart';
import '../models/growth.dart';
import 'growth_repository.dart';

/// UI-owned progression only. No sensors, timers or changes to XP entitlements.
class CharacterRepository {
  CharacterRepository(this.database);
  final Database database;

  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE character_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      progressKey TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL CHECK(kind IN ('unlock','equip','reward')),
      value TEXT NOT NULL,
      ruleVersion INTEGER NOT NULL CHECK(ruleVersion = 1),
      createdAt TEXT NOT NULL,
      seen INTEGER NOT NULL DEFAULT 0 CHECK(seen IN (0,1)))''');

  Future<CharacterSnapshot> refresh([DateTime? at]) async {
    final now = at ?? DateTime.now();
    final growth = await GrowthRepository(database).refresh(now);
    return database.transaction((txn) async {
      // Count validated cell rewards, not arbitrary restored exploration rows.
      final rows = await txn.query('xp_ledger', columns: ['rewardKey']);
      final regions = rows
          .where(
            (r) => (r['rewardKey'] as String).startsWith('exploration.cell:'),
          )
          .length;
      final saved = await txn.query('character_progress');
      final savedKeys = saved.map((r) => r['progressKey'] as String).toSet();
      Future<void> remember(String key, String kind, String value) async {
        if (!savedKeys.add(key)) return;
        await txn.insert('character_progress', {
          'progressKey': key,
          'kind': kind,
          'value': value,
          'ruleVersion': unlockRuleVersion,
          'createdAt': now.toUtc().toIso8601String(),
          'seen': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final c in cosmetics.where((c) => qualifies(c, growth, regions))) {
        await remember('unlock:${c.id}', 'unlock', c.id);
        if (c.requirement != '기본') {
          await remember(
            'reward:cosmetic:${c.id}',
            'reward',
            '새 외형 · ${c.name}',
          );
        }
      }
      // Historical users receive one current-level summary, never a popup cascade.
      final previous = saved.where(
        (r) => (r['progressKey'] as String).startsWith('reward:level:'),
      );
      final highest = previous.fold<int>(1, (level, row) {
        final n =
            int.tryParse((row['progressKey'] as String).split(':').last) ?? 1;
        return n > level ? n : level;
      });
      if (growth.level > highest) {
        await remember(
          'reward:level:${growth.level}',
          'reward',
          'Lv. ${growth.level} 달성',
        );
      }
      for (final a in growth.achievements.where((a) => a.complete)) {
        await remember('reward:${a.id}', 'reward', '업적 달성 · ${a.label}');
      }
      return _snapshot(txn, growth, regions);
    });
  }

  Future<CharacterSnapshot> _snapshot(
    DatabaseExecutor db,
    GrowthSnapshot growth,
    int regions,
  ) async {
    final rows = await db.query('character_progress', orderBy: 'id DESC');
    final unlocked = rows
        .where(
          (r) =>
              r['kind'] == 'unlock' &&
              r['progressKey'] == 'unlock:${r['value']}',
        )
        .map((r) => r['value'] as String)
        .toSet();
    final equipped = <CosmeticSlot, String>{};
    for (final slot in CosmeticSlot.values) {
      final value = rows
          .where(
            (r) =>
                r['progressKey'] == 'equip:${slot.name}' &&
                r['kind'] == 'equip',
          )
          .firstOrNull?['value'];
      if (value is String &&
          unlocked.contains(value) &&
          cosmetics.any((c) => c.id == value && c.slot == slot)) {
        equipped[slot] = value;
      }
    }
    return CharacterSnapshot(
      growth: growth,
      regions: regions,
      unlocked: unlocked,
      equipped: equipped,
      rewards: [
        for (final row in rows.where((r) => r['kind'] == 'reward'))
          ProfileReward(
            row['progressKey'] as String,
            row['value'] as String,
            row['seen'] == 1,
          ),
      ],
    );
  }

  Future<void> equip(String id) async {
    final c = cosmetics.where((c) => c.id == id).firstOrNull;
    if (c == null) throw ArgumentError('Unknown cosmetic');
    await database.transaction((txn) async {
      final unlocked = await txn.query(
        'character_progress',
        where: "progressKey = ? AND kind = 'unlock' AND value = ?",
        whereArgs: ['unlock:$id', id],
      );
      if (unlocked.isEmpty) throw ArgumentError('Locked cosmetic');
      await txn.insert('character_progress', {
        'progressKey': 'equip:${c.slot.name}',
        'kind': 'equip',
        'value': id,
        'ruleVersion': unlockRuleVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'seen': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> acknowledge(List<String> keys) =>
      database.transaction((txn) async {
        for (final key in keys) {
          await txn.update(
            'character_progress',
            {'seen': 1},
            where: "progressKey = ? AND kind = 'reward' AND seen = 0",
            whereArgs: [key],
          );
        }
      });
}
