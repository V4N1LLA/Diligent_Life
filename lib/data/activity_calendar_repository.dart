import 'package:sqflite/sqflite.dart';

import '../models/activity_calendar.dart';
import '../models/exercise_session.dart';
import '../models/exploration.dart';
import '../models/growth.dart';
import '../utils/dates.dart';

/// Read-only projections: no persisted aggregates, GPS reads or reward writes.
/// SQLite localtime follows the device timezone, just like startedAt.toLocal().
/// Workouts belong wholly to their local start day (existing growth policy).
class ActivityCalendarRepository {
  ActivityCalendarRepository(this.database);
  final Database database;
  static final _catalog = {
    for (final a in [...achievements([], 0), ...explorationAchievements(0)])
      a.id: a,
  };
  static final _achievementKeys = _catalog.keys.map((k) => "'$k'").join(',');
  // SQLite rounds fractional seconds to milliseconds. Strip the fraction before
  // conversion so 23:59:59.999999 cannot roll into the following local day.
  // Older growth backups may contain offsets or local (zone-less) ISO times.
  static String _wholeStamp(String column) =>
      "CASE WHEN substr($column,20,1) = '.' THEN substr($column,1,19) || "
      "ltrim(substr($column,20), '.0123456789') ELSE $column END";
  static String _epoch(String column) =>
      "CAST(CASE WHEN $column LIKE '%Z' OR substr($column,20) LIKE '%+%' "
      "OR substr($column,20) LIKE '%-%' THEN strftime('%s', ${_wholeStamp(column)}) "
      "ELSE strftime('%s', ${_wholeStamp(column)}, 'utc') END AS INTEGER)";
  static String _localDay(String column) =>
      "strftime('%Y-%m-%d', ${_epoch(column)}, 'unixepoch', 'localtime')";
  static String _utcKey(DateTime at) =>
      at.toUtc().toIso8601String().replaceAll('Z', '');
  static const _cells =
      '''SELECT regionId, discoveredAt
    FROM exploration_events WHERE modelVersion = $explorationRuleVersion
    AND eventKey = 'exploration:' || regionId''';

  Future<(CalendarMonth, CalendarMonth)> month(DateTime month, DateTime now) =>
      database.transaction((db) async {
        final start = DateTime(month.year, month.month);
        final previous = DateTime(start.year, start.month - 1);
        final days = await _range(
          db,
          previous,
          DateTime(start.year, start.month + 1),
          now,
        );
        CalendarMonth part(DateTime at) => CalendarMonth(at, {
          for (final entry in days.entries)
            if (entry.key.startsWith(dateKey(at).substring(0, 7)))
              entry.key: entry.value,
        });
        return (part(start), part(previous));
      });

  Future<CalendarDay> day(DateTime day, DateTime now) =>
      database.transaction((db) async {
        final start = DateTime(day.year, day.month, day.day);
        final data = await _range(
          db,
          start,
          DateTime(start.year, start.month, start.day + 1),
          now,
        );
        return data[dateKey(start)] ?? CalendarDay(dateKey(start));
      });

  Future<Map<String, CalendarDay>> _range(
    DatabaseExecutor db,
    DateTime from,
    DateTime until,
    DateTime now,
  ) async {
    final start = dateKey(from),
        end = dateKey(until),
        today = dateKey(now.toLocal());
    final lower = _utcKey(from);
    final upper = _utcKey(until);
    final instant = _utcKey(now);
    final fromSeconds = from.millisecondsSinceEpoch ~/ 1000;
    final untilSeconds = until.millisecondsSinceEpoch ~/ 1000;
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final result = <String, CalendarDay>{};
    CalendarDay get(String date) => result[date] ?? CalendarDay(date);
    for (final r in await db.rawQuery(
      '''SELECT date, steps FROM daily_steps
      WHERE date >= ? AND date < ? AND date <= ? AND steps > 0''',
      [start, end, today],
    )) {
      final date = r['date'] as String;
      result[date] = CalendarDay(date, steps: r['steps'] as int);
    }
    for (final r in await db.rawQuery(
      '''SELECT ${_localDay('startedAt')} AS date,
      COUNT(*) AS workouts, SUM(distanceMeters) AS meters, SUM(elapsedSeconds) AS seconds
      FROM exercise_sessions WHERE status = 'finished' AND rtrim(startedAt, 'Z') >= ?
      AND rtrim(startedAt, 'Z') < ? AND rtrim(startedAt, 'Z') <= ? GROUP BY date''',
      [lower, upper, instant],
    )) {
      final date = r['date'] as String, old = get(date);
      result[date] = CalendarDay(
        date,
        steps: old.steps,
        workouts: r['workouts'] as int,
        meters: (r['meters'] as num).toDouble(),
        seconds: r['seconds'] as int,
      );
    }
    for (final r in await db.rawQuery(
      '''SELECT regionId, discoveredAt
      FROM ($_cells) WHERE ${_epoch('discoveredAt')} >= ? AND ${_epoch('discoveredAt')} < ? AND ${_epoch('discoveredAt')} <= ?''',
      [fromSeconds, untilSeconds, nowSeconds],
    )) {
      final at = DateTime.tryParse(r['discoveredAt'] as String)?.toLocal();
      if (at == null || at.isAfter(now)) continue;
      if (ExplorationCell.parse(r['regionId'] as String) == null) continue;
      final date = dateKey(at), old = get(date);
      result[date] = CalendarDay(
        date,
        steps: old.steps,
        workouts: old.workouts,
        meters: old.meters,
        seconds: old.seconds,
        regions: old.regions + 1,
      );
    }
    void milestone(String date, String label) {
      final old = get(date);
      result[date] = CalendarDay(
        date,
        steps: old.steps,
        workouts: old.workouts,
        meters: old.meters,
        seconds: old.seconds,
        regions: old.regions,
        milestones: [...old.milestones, label],
      );
    }

    for (final r in await db.rawQuery(
      '''SELECT rewardKey, earnedAt
      FROM xp_ledger WHERE rewardKey IN ($_achievementKeys) AND ${_epoch('earnedAt')} >= ?
      AND ${_epoch('earnedAt')} < ? AND ${_epoch('earnedAt')} <= ?''',
      [fromSeconds, untilSeconds, nowSeconds],
    )) {
      final at = DateTime.parse(r['earnedAt'] as String).toLocal();
      if (at.isAfter(now)) continue;
      final date = dateKey(at);
      final a = _catalog[r['rewardKey']]!;
      milestone(date, '업적 · ${a.label}');
      final title = titles[a.titleId];
      if (title != null) milestone(date, '타이틀 · $title');
    }
    // These are observed/recorded milestones, not reconstructed level-up times.
    // Never duplicate achievements from the character reward inbox.
    for (final r in await db.rawQuery(
      '''SELECT progressKey, createdAt
      FROM character_progress WHERE kind = 'reward' AND ruleVersion = 1
      AND progressKey LIKE 'reward:level:%' AND ${_epoch('createdAt')} >= ?
      AND ${_epoch('createdAt')} < ? AND ${_epoch('createdAt')} <= ?''',
      [fromSeconds, untilSeconds, nowSeconds],
    )) {
      final at = DateTime.parse(r['createdAt'] as String).toLocal();
      if (at.isAfter(now)) continue;
      final level = int.tryParse((r['progressKey'] as String).split(':').last);
      if (level != null && level > 1) {
        milestone(dateKey(at), 'Lv. $level 확인');
      }
    }
    return result;
  }

  /// Keyset pagination by local day. No OFFSET and no raw route/session list.
  Future<TimelinePage> timeline(
    DateTime now, {
    String? before,
    int limit = 20,
  }) => database.transaction((db) async {
    if (limit < 1 || limit > 60) throw ArgumentError.value(limit, 'limit');
    final today = dateKey(now.toLocal());
    final instant = now.millisecondsSinceEpoch ~/ 1000;
    final dates = await db.rawQuery(
      '''SELECT DISTINCT date FROM (
          SELECT date FROM daily_steps WHERE steps > 0
          UNION SELECT ${_localDay('startedAt')} FROM exercise_sessions
            WHERE status = 'finished' AND ${_epoch('startedAt')} <= ?
          UNION SELECT ${_localDay('discoveredAt')} FROM ($_cells) WHERE ${_epoch('discoveredAt')} <= ?
          UNION SELECT ${_localDay('earnedAt')} FROM xp_ledger
            WHERE rewardKey IN ($_achievementKeys) AND ${_epoch('earnedAt')} <= ?
          UNION SELECT ${_localDay('createdAt')} FROM character_progress
            WHERE kind = 'reward' AND ruleVersion = 1 AND progressKey LIKE 'reward:level:%'
            AND ${_epoch('createdAt')} <= ?
        ) WHERE date <= ? AND date < ? ORDER BY date DESC LIMIT ?''',
      [
        instant,
        instant,
        instant,
        instant,
        today,
        before ?? '9999-12-31',
        limit + 1,
      ],
    );
    final selected = dates.take(limit).map((r) => r['date'] as String).toList();
    if (selected.isEmpty) return const TimelinePage([], null);
    final oldest = DateTime.parse(selected.last),
        newest = DateTime.parse(selected.first);
    final all = await _range(
      db,
      oldest,
      DateTime(newest.year, newest.month, newest.day + 1),
      now,
    );
    return TimelinePage([
      for (final date in selected)
        if (all[date]?.hasActivity ?? false) all[date]!,
    ], dates.length > limit ? selected.last : null);
  });

  Future<List<ExerciseSession>> sessions(DateTime day, DateTime now) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = await database.query(
      'exercise_sessions',
      where: "status = 'finished' AND rtrim(startedAt, 'Z') >= ? AND rtrim(startedAt, 'Z') < ? AND rtrim(startedAt, 'Z') <= ?",
      whereArgs: [_utcKey(start), _utcKey(end), _utcKey(now)],
      orderBy: "rtrim(startedAt, 'Z') DESC, id DESC",
    );
    return rows.map(ExerciseSession.fromMap).toList();
  }
}
