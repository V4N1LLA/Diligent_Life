import 'dart:math' as math;

import 'daily_record.dart';
import 'exercise_session.dart';
import 'exercise_type.dart';
import '../utils/dates.dart';
import '../utils/movement_analysis.dart';
import '../utils/portfolio_analysis.dart';

enum ReportPeriod {
  week('주간'),
  month('월간'),
  year('연간');

  const ReportPeriod(this.label);
  final String label;
  DateTime start(DateTime day) => switch (this) {
    week => DateTime(day.year, day.month, day.day - day.weekday + 1),
    month => DateTime(day.year, day.month),
    year => DateTime(day.year),
  };
  DateTime shift(DateTime start, int delta) => switch (this) {
    week => DateTime(start.year, start.month, start.day + delta * 7),
    month => DateTime(start.year, start.month + delta),
    year => DateTime(start.year + delta),
  };
}

class ReportWindow {
  ReportWindow(this.period, DateTime anchor, DateTime now) {
    final today = dayOnly(now.toLocal());
    start = period.start(anchor.toLocal());
    final next = period.shift(start, 1);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    before = next.isBefore(tomorrow) ? next : tomorrow;
    if (!start.isBefore(before)) throw ArgumentError('Future report');
    partial = before.isBefore(next);
    previousStart = period.shift(start, -1);
    final days = DateTime.utc(
      before.year,
      before.month,
      before.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    final matched = DateTime(
      previousStart.year,
      previousStart.month,
      previousStart.day + days,
    );
    previousBefore = partial && matched.isBefore(start) ? matched : start;
  }
  final ReportPeriod period;
  late final DateTime start, before, previousStart, previousBefore;
  late final bool partial;
  static String range(DateTime from, DateTime before) =>
      '${dateKey(from)} — ${dateKey(DateTime(before.year, before.month, before.day - 1))}';
  String get title => '${period.label} 활동 리포트';
  String get dates => range(start, before);
  String get previousDates => range(previousStart, previousBefore);
}

class ReportEntry {
  ReportEntry(this.session, PortfolioAnalysis analysis)
    : movingMeters = analysis.movement?.meters ?? 0,
      movingSeconds = analysis.movement?.movingSeconds ?? 0,
      bests = analysis.movement?.bests ?? const [],
      route = sampleOverviewRoute(analysis.route, 64);
  final ExerciseSession session;
  final double movingMeters, movingSeconds;
  final List<DistanceBest> bests;
  final List<RoutePoint> route;
  double? get kmh => movingSeconds >= 60 && movingMeters >= 100
      ? movingMeters / movingSeconds * 3.6
      : null;
}

class ReportBucket {
  const ReportBucket(this.start, this.before, this.summary, this.meanWeight);
  final DateTime start, before;
  final MovementSummary summary;
  final double? meanWeight;
}

class SpeedComparison {
  const SpeedComparison(
    this.type,
    this.current,
    this.previous,
    this.currentCount,
    this.previousCount,
    this.weeks,
  );
  final ExerciseType type;
  final double? current, previous;
  final int currentCount, previousCount;
  final List<double?> weeks;
  bool get increasing =>
      weeks.every((v) => v != null) &&
      List.generate(3, (i) => weeks[i + 1]! > weeks[i]! + .05).every((v) => v);
}

class ReportRecord {
  const ReportRecord(
    this.label,
    this.entry,
    this.value,
    this.unit, {
    this.previous,
  });
  final String label, unit;
  final ReportEntry entry;
  final double value;
  final double? previous;
  String get formatted => unit == '초'
      ? '${value.toStringAsFixed(1)}초'
      : '${value.toStringAsFixed(unit == 'km' ? 2 : 1)} $unit';
}

class RouteGroup {
  RouteGroup(this.representative, this.cells) : entries = [representative];
  final ReportEntry representative;
  final Set<String> cells;
  final List<ReportEntry> entries;
}

// Approximate geographic overlap, not route identity. Sampled points enter 100m
// cells. Ignore direction, require similar length and 70% overlap in BOTH paths.
List<RouteGroup> frequentRoutes(List<ReportEntry> entries) {
  final groups = <RouteGroup>[];
  final index = <String, Set<int>>{};
  for (final e in entries) {
    if (e.route.length < 8 || e.movingMeters < 300) continue;
    final cells = <String>{};
    for (final p in e.route) {
      if (p.latitude.abs() > 80) continue;
      final lat = p.latitude * math.pi / 180;
      final lon = p.longitude * math.pi / 180;
      // Earth-centred cells avoid longitude wrap and latitude-dependent widths.
      cells.add(
        '${(6371000 * math.cos(lat) * math.cos(lon) / 100).floor()}:${(6371000 * math.cos(lat) * math.sin(lon) / 100).floor()}:${(6371000 * math.sin(lat) / 100).floor()}',
      );
    }
    if (cells.length < 4) continue;
    final candidates = <int>{for (final cell in cells) ...?index[cell]};
    RouteGroup? match;
    double bestScore = .7;
    for (final id in candidates) {
      final g = groups[id];
      final ratio = e.movingMeters / g.representative.movingMeters;
      if (ratio < .75 || ratio > 1.33) continue;
      final common = cells.intersection(g.cells).length;
      final score = math.min(common / cells.length, common / g.cells.length);
      if (score >= bestScore) {
        match = g;
        bestScore = score;
      }
    }
    if (match != null) {
      match.entries.add(e);
    } else {
      final id = groups.length;
      groups.add(RouteGroup(e, cells));
      for (final cell in cells) {
        index.putIfAbsent(cell, () => {}).add(id);
      }
    }
  }
  return groups.where((g) => g.entries.length >= 2).toList()
    ..sort((a, b) => b.entries.length.compareTo(a.entries.length));
}

class ActivityReport {
  ActivityReport({
    required this.window,
    required this.current,
    required this.previous,
    required this.weights,
    required this.buckets,
    required this.speeds,
    required this.records,
    required this.improvements,
    required this.routes,
    required this.representative,
    required this.pattern,
    required this.weekStarts,
  });
  final ReportWindow window;
  final MovementSummary current, previous;
  final List<DailyRecord> weights;
  final List<ReportBucket> buckets;
  final List<SpeedComparison> speeds;
  final List<ReportRecord> records, improvements;
  final List<RouteGroup> routes;
  final ReportEntry? representative;
  final String pattern;
  final List<DateTime> weekStarts;
  double? get weightChange => weights.length < 2
      ? null
      : weights.last.weightKg! - weights.first.weightKg!;
  bool get comparable => current.count >= 2 && previous.count >= 2;
  String get insight {
    if (!comparable || previous.meters <= 0) return '이전 기간과 변화를 비교하기에는 데이터 부족';
    final percent = (current.meters - previous.meters) / previous.meters * 100;
    if (percent.abs() < .5) return '이전 기간과 총 이동거리가 비슷합니다.';
    return '이전 기간보다 총 이동거리가 ${percent.abs().toStringAsFixed(0)}% ${percent > 0 ? '증가' : '감소'}했습니다.';
  }

  String delta(double now, double old, {bool available = true}) {
    if (!available || !comparable) return '데이터 부족';
    if (old <= 0) return now > 0 ? '이전 값 0 · 증감률 계산 불가' : '변화 없음';
    final percent = (now - old) / old * 100;
    return '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';
  }
}

ActivityReport buildActivityReport(
  ReportWindow window,
  List<ReportEntry> history,
  List<DailyRecord> allWeights,
) {
  final ordered =
      history
          .where(
            (e) =>
                e.session.status == SessionStatus.finished &&
                e.session.startedAt.isBefore(window.before),
          )
          .toList()
        ..sort((a, b) {
          final t = a.session.startedAt.compareTo(b.session.startedAt);
          return t == 0 ? a.session.id.compareTo(b.session.id) : t;
        });
  List<ReportEntry> between(DateTime from, DateTime before) => ordered
      .where(
        (e) =>
            !e.session.startedAt.isBefore(from) &&
            e.session.startedAt.isBefore(before),
      )
      .toList();
  final current = between(window.start, window.before);
  final previous = between(window.previousStart, window.previousBefore);
  final weights =
      allWeights
          .where(
            (r) =>
                r.weightKg != null &&
                r.date.compareTo(dateKey(window.start)) >= 0 &&
                r.date.compareTo(dateKey(window.before)) < 0,
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  MovementSummary summary(List<ReportEntry> entries) =>
      MovementSummary.fromSessions(entries.map((e) => e.session));
  final buckets = <ReportBucket>[];
  for (var from = window.start; from.isBefore(window.before);) {
    final next = switch (window.period) {
      ReportPeriod.week => DateTime(from.year, from.month, from.day + 1),
      ReportPeriod.month => DateTime(from.year, from.month, from.day + 7),
      ReportPeriod.year => DateTime(from.year, from.month + 1),
    };
    final before = next.isBefore(window.before) ? next : window.before;
    final measurements = weights
        .where(
          (r) =>
              r.date.compareTo(dateKey(from)) >= 0 &&
              r.date.compareTo(dateKey(before)) < 0,
        )
        .toList();
    buckets.add(
      ReportBucket(
        from,
        before,
        summary(between(from, before)),
        measurements.isEmpty
            ? null
            : measurements.fold<double>(0, (v, r) => v + r.weightKg!) /
                  measurements.length,
      ),
    );
    from = before;
  }
  // Four completed calendar weeks, so a partial current week cannot imply a trend.
  final weekEnd = ReportPeriod.week.start(window.before);
  final weeks = [
    for (var i = 4; i >= 1; i--) ReportPeriod.week.shift(weekEnd, -i),
  ];
  final speeds = <SpeedComparison>[];
  for (final type in ExerciseType.values) {
    List<ReportEntry> eligible(List<ReportEntry> values) =>
        values.where((e) => e.session.type == type && e.kmh != null).toList();
    double? speed(List<ReportEntry> values) {
      final items = eligible(values);
      if (items.length < 2) return null;
      return items.fold<double>(0, (v, e) => v + e.movingMeters) /
          items.fold<double>(0, (v, e) => v + e.movingSeconds) *
          3.6;
    }

    final a = eligible(current), b = eligible(previous);
    if (a.isEmpty && b.isEmpty) continue;
    speeds.add(
      SpeedComparison(
        type,
        speed(current),
        speed(previous),
        a.length,
        b.length,
        [
          for (final start in weeks)
            speed(between(start, ReportPeriod.week.shift(start, 1))),
        ],
      ),
    );
  }
  final winners = <String, ReportRecord>{};
  final improvements = <ReportRecord>[];
  for (final e in ordered) {
    void record(
      String key,
      String label,
      double value,
      String unit, {
      bool lower = false,
    }) {
      if (value <= 0 || !value.isFinite) return;
      final old = winners[key];
      if (old == null ||
          (lower ? value < old.value - 1e-6 : value > old.value + 1e-6)) {
        final r = ReportRecord(label, e, value, unit, previous: old?.value);
        winners[key] = r;
        if (old != null && !e.session.startedAt.isBefore(window.start)) {
          improvements.add(r);
        }
      }
    }

    record('distance', '최장 거리', e.session.distanceMeters / 1000, 'km');
    record('time', '최장 시간', e.session.elapsedSeconds / 60, '분');
    if (e.kmh case final speed?) {
      record(
        'speed/${e.session.type.name}',
        '${e.session.type.label} 평균 이동속도',
        speed,
        'km/h',
      );
    }
    for (final b in e.bests) {
      record(
        '${e.session.type.name}/${b.meters}',
        '${e.session.type.label} 빠른 ${b.meters}m',
        b.seconds,
        '초',
        lower: true,
      );
    }
  }
  final weekdays = List.filled(7, 0),
      slots = List.filled(4, 0),
      pairs = <int, int>{};
  for (final e in current) {
    final t = e.session.startedAt.toLocal();
    final slot = t.hour < 6
        ? 0
        : t.hour < 12
        ? 1
        : t.hour < 18
        ? 2
        : 3;
    weekdays[t.weekday - 1]++;
    slots[slot]++;
    pairs.update((t.weekday - 1) * 4 + slot, (n) => n + 1, ifAbsent: () => 1);
  }
  const days = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  const times = ['새벽(0–6시)', '오전(6–12시)', '오후(12–18시)', '저녁(18–24시)'];
  String top(List<int> counts, List<String> labels) {
    final max = counts.reduce(math.max);
    return [
      for (var i = 0; i < counts.length; i++)
        if (counts[i] == max) labels[i],
    ].join('·');
  }

  var pattern = '요일·시간대 경향을 보기에는 데이터 부족';
  if (current.length >= 4 &&
      current
              .map((e) => dateKey(e.session.startedAt.toLocal()))
              .toSet()
              .length >=
          3) {
    pattern =
        '가장 많이 운동한 요일: ${top(weekdays, days)}\n가장 잦은 시작 시간대: ${top(slots, times)}';
    final maxPair = pairs.values.reduce(math.max);
    final leaders = pairs.entries.where((p) => p.value == maxPair).toList();
    if (maxPair >= 3 && leaders.length == 1) {
      final key = leaders.single.key;
      pattern +=
          '\n${days[key ~/ 4]} ${times[key % 4]}에 가장 자주 운동했습니다. ($maxPair회)';
    }
  }
  final ranked = [...current]
    ..sort((a, b) {
      final distance = b.movingMeters.compareTo(a.movingMeters);
      if (distance != 0) return distance;
      final duration = b.session.elapsedSeconds.compareTo(
        a.session.elapsedSeconds,
      );
      return duration != 0 ? duration : a.session.id.compareTo(b.session.id);
    });
  return ActivityReport(
    window: window,
    current: summary(current),
    previous: summary(previous),
    weights: weights,
    buckets: buckets,
    speeds: speeds,
    records: winners.values.toList(),
    improvements: improvements.reversed.take(5).toList(),
    routes: frequentRoutes(current).take(3).toList(),
    representative: ranked.firstOrNull,
    pattern: pattern,
    weekStarts: weeks,
  );
}
