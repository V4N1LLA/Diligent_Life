import '../models/daily_record.dart';
import '../models/exercise_session.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';
import 'exercise_repository.dart';
import 'record_repository.dart';

enum PortfolioPeriod {
  recent('최근 30일'),
  month('월간'),
  year('연간'),
  all('전체');

  const PortfolioPeriod(this.label);
  final String label;
  DateTime? start(DateTime today) => switch (this) {
    recent => DateTime(today.year, today.month, today.day - 29),
    year => DateTime(today.year),
    all => null,
    month => DateTime(today.year, today.month),
  };
}

class PortfolioMonth {
  const PortfolioMonth(this.month, this.summary);
  final DateTime month;
  final MovementSummary summary;
}

class PortfolioData {
  const PortfolioData({
    required this.summary,
    required this.weights,
    required this.months,
    this.longest,
    this.longestTime,
    this.bestAverage,
    this.recent = const [],
    this.periodStart,
    this.periodEnd,
    this.fastestSession,
    this.fastest,
    this.representative,
    this.route = const [],
  });
  final MovementSummary summary;
  final List<DailyRecord> weights;
  final List<PortfolioMonth> months;
  final ExerciseSession? longest,
      longestTime,
      bestAverage,
      fastestSession,
      representative;
  final List<ExerciseSession> recent;
  final DateTime? periodStart, periodEnd;
  final SpeedSection? fastest;
  final List<RoutePoint> route;
  double? get weightChange => weights.length < 2
      ? null
      : weights.last.weightKg! - weights.first.weightKg!;
}

class PortfolioRepository {
  PortfolioRepository(this.records, this.exercises);
  final RecordRepository records;
  final ExerciseRepository? exercises;

  Future<PortfolioData> load(
    PortfolioPeriod period,
    DateTime now, {
    DateTime? anchor,
  }) async {
    final today = dayOnly(now.toLocal());
    final selected = dayOnly((anchor ?? today).toLocal());
    final from = period.start(
      period == PortfolioPeriod.recent ? today : selected,
    );
    final next = switch (period) {
      PortfolioPeriod.month => DateTime(selected.year, selected.month + 1),
      PortfolioPeriod.year => DateTime(selected.year + 1),
      _ => DateTime(today.year, today.month, today.day + 1),
    };
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final before = next.isAfter(tomorrow) ? tomorrow : next;
    final lastDay = DateTime(before.year, before.month, before.day - 1);
    final results = await Future.wait<Object>([
      records.list(
        since: from == null ? null : dateKey(from),
        until: dateKey(lastDay),
      ),
      exercises == null
          ? Future.value(<ExerciseSession>[])
          : exercises!.finishedBetween(from: from, before: before),
    ]);
    final sessions = results[1] as List<ExerciseSession>;
    final weights =
        (results[0] as List<DailyRecord>)
            .where((r) => r.weightKg != null)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final summary = MovementSummary.fromSessions(sessions);
    ExerciseSession? longest,
        longestTime,
        bestAverage,
        fastestSession,
        representative;
    SpeedSection? fastest;
    var representativeRoute = <RoutePoint>[];
    final monthly = <String, List<ExerciseSession>>{};
    // Only one route is retained for display; scan sessions longest-first so
    // missing routes can fall back to the next usable movement.
    final byDistance = [...sessions]
      ..sort((a, b) {
        final distance = b.distanceMeters.compareTo(a.distanceMeters);
        return distance != 0
            ? distance
            : b.elapsedSeconds.compareTo(a.elapsedSeconds);
      });
    for (final session in byDistance) {
      longest ??= session;
      if (session.elapsedSeconds > 0 &&
          (longestTime == null ||
              session.elapsedSeconds > longestTime.elapsedSeconds)) {
        longestTime = session;
      }
      final speed = averageKmh(session);
      if (speed != null &&
          (bestAverage == null || speed > averageKmh(bestAverage)!)) {
        bestAverage = session;
      }
      final local = session.startedAt.toLocal();
      monthly
          .putIfAbsent('${local.year}-${local.month}', () => [])
          .add(session);
      final analysis = await exercises!.portfolioAnalysis(session);
      final best = analysis.fastest;
      if (best != null && (fastest == null || best.kmh > fastest.kmh)) {
        fastest = best;
        fastestSession = session;
      }
      if (representative == null) {
        final points = analysis.route;
        if (points.length >= 2 && session.distanceMeters > 0) {
          representative = session;
          representativeRoute = points;
        }
      }
    }
    var first =
        from ?? (sessions.isEmpty ? today : sessions.first.startedAt.toLocal());
    if (from == null &&
        weights.isNotEmpty &&
        DateTime.parse(weights.first.date).isBefore(first)) {
      first = DateTime.parse(weights.first.date);
    }
    final months = <PortfolioMonth>[];
    for (
      var month = DateTime(lastDay.year, lastDay.month);
      !month.isBefore(DateTime(first.year, first.month));
      month = DateTime(month.year, month.month - 1)
    ) {
      months.add(
        PortfolioMonth(
          month,
          MovementSummary.fromSessions(
            monthly['${month.year}-${month.month}'] ?? [],
          ),
        ),
      );
    }
    return PortfolioData(
      summary: summary,
      weights: weights,
      months: months,
      longest: longest,
      longestTime: longestTime,
      bestAverage: bestAverage,
      recent: (List<ExerciseSession>.of(
        sessions,
      )..sort((a, b) => b.startedAt.compareTo(a.startedAt))).take(5).toList(),
      periodStart: from,
      periodEnd: lastDay,
      fastest: fastest,
      fastestSession: fastestSession,
      representative: representative,
      route: representativeRoute,
    );
  }
}

// Average speed includes all unpaused time. Near-zero distances are not records.
double? averageKmh(ExerciseSession s) {
  if (s.elapsedSeconds <= 0 || s.distanceMeters < 20) return null;
  final kmh = s.distanceMeters / s.elapsedSeconds * 3.6;
  return kmh <= TrackingPolicy.maxSpeed(s.type) * 3.6 ? kmh : null;
}
