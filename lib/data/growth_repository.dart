import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../models/growth.dart';
import '../models/exploration.dart';
import '../utils/dates.dart';

class GrowthRepository {
  GrowthRepository(this.database);
  final Database database;
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE daily_steps (
      id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE,
      steps INTEGER NOT NULL CHECK(steps >= 0),
      uncertainSteps INTEGER NOT NULL DEFAULT 0 CHECK(uncertainSteps >= 0 AND uncertainSteps <= steps), coverage TEXT NOT NULL,
      updatedAt TEXT NOT NULL)''');
    // Hardware cursor is local to this device and NEVER restored from a backup.
    await db.execute(
      '''CREATE TABLE step_cursor (
      id INTEGER PRIMARY KEY CHECK(id = 1), boot INTEGER NOT NULL,
      counter INTEGER NOT NULL, sample INTEGER NOT NULL, date TEXT NOT NULL)''',
    );
    await db.execute('''CREATE TABLE xp_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT, rewardKey TEXT NOT NULL UNIQUE,
      xp INTEGER NOT NULL CHECK(xp >= 0), ruleVersion INTEGER NOT NULL,
      earnedAt TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE growth_profile (
      id INTEGER PRIMARY KEY CHECK(id = 1), titleId TEXT)''');
    // Exploration can reference a stable source ID without copying GPS coordinates.
    await db.execute('''CREATE TABLE exploration_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, eventKey TEXT NOT NULL UNIQUE,
      regionId TEXT NOT NULL, sourceSessionId INTEGER,
      modelVersion INTEGER NOT NULL, discoveredAt TEXT NOT NULL)''');
  }

  Future<GrowthSnapshot> refresh(DateTime now) async {
    return database.transaction((txn) async {
      final today = dateKey(now);
      final days = <String, ActivityDay>{};
      for (final r in await txn.query(
        'daily_steps',
        where: 'date <= ?',
        whereArgs: [today],
        orderBy: 'date',
      )) {
        days[r['date'] as String] = ActivityDay(
          r['date'] as String,
          steps: r['steps'] as int,
          confirmedSteps: (r['steps'] as int) - (r['uncertainSteps'] as int),
        );
      }
      double longest = 0;
      for (final r in await txn.query(
        'exercise_sessions',
        where: "status = 'finished'",
        columns: ['startedAt', 'distanceMeters', 'elapsedSeconds'],
      )) {
        final date = dateKey(
          DateTime.parse(r['startedAt'] as String).toLocal(),
        );
        if (date.compareTo(today) > 0) continue;
        final old = days[date] ?? ActivityDay(date);
        final meters = (r['distanceMeters'] as num).toDouble();
        longest = math.max(longest, meters);
        days[date] = ActivityDay(
          date,
          steps: old.steps,
          confirmedSteps: old.confirmedSteps,
          meters: old.meters + meters,
          seconds: old.seconds + (r['elapsedSeconds'] as int),
          workouts: old.workouts + 1,
        );
      }
      // Increment an existing entitlement, never re-award it after deletion/edit.
      final savedRewards = {
        for (final row in await txn.query('xp_ledger'))
          row['rewardKey'] as String: row['xp'] as int,
      };
      Future<void> award(String key, int entitlement) async {
        final existing = savedRewards[key];
        if (existing == null) {
          if (entitlement > 0) {
            await txn.insert('xp_ledger', {
              'rewardKey': key,
              'xp': entitlement,
              'ruleVersion': xpRuleVersion,
              'earnedAt': now.toUtc().toIso8601String(),
            });
          }
        } else if (entitlement > existing) {
          await txn.update(
            'xp_ledger',
            {'xp': entitlement},
            where: 'rewardKey = ?',
            whereArgs: [key],
          );
        }
      }

      final explorationDays = <String, int>{};
      final regions = <String>{};
      for (final row in await txn.query('exploration_events', orderBy: 'id')) {
        final id = row['regionId'] as String;
        final at = DateTime.tryParse(row['discoveredAt'] as String)?.toLocal();
        if (row['modelVersion'] != explorationRuleVersion ||
            row['eventKey'] != 'exploration:$id' ||
            ExplorationCell.parse(id) == null ||
            at == null ||
            at.isAfter(now) ||
            !regions.add(id)) {
          continue;
        }
        final date = dateKey(at);
        explorationDays[date] = (explorationDays[date] ?? 0) + 1;
        await award('exploration.cell:$id:v1', 10);
      }
      for (final entry in explorationDays.entries) {
        final quest = explorationQuest(entry.value);
        if (quest.complete) {
          await award('${quest.id}:${entry.key}', quest.reward);
        }
      }
      final weeks = <String, int>{};
      for (final d in days.values) {
        await award('activity:${d.date}:v1', d.baseXp);
        for (final q in dailyQuests(d)) {
          if (q.complete) await award('${q.id}:${d.date}', q.reward);
        }
        final date = DateTime.parse(d.date);
        final monday = dateKey(
          DateTime(date.year, date.month, date.day - date.weekday + 1),
        );
        weeks[monday] = (weeks[monday] ?? 0) + d.workouts;
      }
      for (final w in weeks.entries) {
        if (w.value >= 3) {
          await award('quest.weekly.workouts_3.v1:${w.key}', 80);
        }
      }
      final all = [
        ...achievements(days.values.toList(), longest),
        ...explorationAchievements(regions.length),
      ];
      for (final a in all) {
        if (a.complete) await award(a.id, a.reward);
      }
      final ledger = await txn.query('xp_ledger');
      final keys = ledger.map((r) => r['rewardKey'] as String).toSet();
      final unlocked = {
        for (final a in all)
          if (keys.contains(a.id)) a.titleId!,
      };
      final profile = await txn.query('growth_profile', limit: 1);
      final monday = dateKey(
        DateTime(now.year, now.month, now.day - now.weekday + 1),
      );
      return GrowthSnapshot(
        days: days.values.toList()..sort((a, b) => a.date.compareTo(b.date)),
        xp: ledger.fold<int>(0, (sum, r) => sum + (r['xp'] as int)),
        quests: [
          ...dailyQuests(days[today] ?? ActivityDay(today)),
          explorationQuest(explorationDays[today] ?? 0),
          GoalProgress(
            'quest.weekly.workouts_3.v1',
            '이번 주 운동 3회',
            (weeks[monday] ?? 0).toDouble(),
            3,
            80,
          ),
        ],
        achievements: [
          for (final a in all)
            GoalProgress(
              a.id,
              a.label,
              keys.contains(a.id) ? math.max(a.value, a.target) : a.value,
              a.target,
              a.reward,
              titleId: a.titleId,
            ),
        ],
        unlockedTitles: unlocked,
        titleId: profile.firstOrNull?['titleId'] as String?,
      );
    });
  }

  Future<void> equip(String? id, GrowthSnapshot snapshot) async {
    if (id != null && !snapshot.unlockedTitles.contains(id)) {
      throw ArgumentError('Locked title');
    }
    await database.insert('growth_profile', {
      'id': 1,
      'titleId': id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
