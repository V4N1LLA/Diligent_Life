import '../models/daily_record.dart';
import '../models/exercise_session.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';
import 'exercise_repository.dart';
import 'record_repository.dart';

enum PortfolioPeriod {
  recent('최근 30일'),
  year('올해'),
  all('전체');

  const PortfolioPeriod(this.label);
  final String label;
  DateTime? start(DateTime today) => switch (this) {
    recent => DateTime(today.year, today.month, today.day - 29),
    year => DateTime(today.year),
    all => null,
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
    this.fastestSession,
    this.fastest,
    this.representative,
    this.route = const [],
  });
  final MovementSummary summary;
  final List<DailyRecord> weights;
  final List<PortfolioMonth> months;
  final ExerciseSession? longest, fastestSession, representative;
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
  // Completed sessions are immutable. Keep one small section per session,
  // not all raw points; deleted IDs are pruned on the next period load.
  final _fastest = <int, SpeedSection?>{};

  Future<PortfolioData> load(PortfolioPeriod period, DateTime now) async {
    final today = dayOnly(now.toLocal());
    final from = period.start(today);
    final before = DateTime(today.year, today.month, today.day + 1);
    final results = await Future.wait<Object>([
      records.list(
        since: from == null ? null : dateKey(from),
        until: dateKey(today),
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
    final ids = sessions.map((s) => s.id).toSet();
    _fastest.removeWhere((id, _) => !ids.contains(id));
    ExerciseSession? longest, fastestSession, representative;
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
      final local = session.startedAt.toLocal();
      monthly
          .putIfAbsent('${local.year}-${local.month}', () => [])
          .add(session);
      List<RoutePoint>? points;
      if (!_fastest.containsKey(session.id)) {
        points = await exercises!.analysisRoute(session.id);
        SpeedSection? best;
        for (final section in speedSections(points)) {
          if (section.kmh <= TrackingPolicy.maxSpeed(session.type) * 3.6 &&
              (best == null || section.kmh > best.kmh)) {
            best = section;
          }
        }
        _fastest[session.id] = best;
      }
      final best = _fastest[session.id];
      if (best != null && (fastest == null || best.kmh > fastest.kmh)) {
        fastest = best;
        fastestSession = session;
      }
      if (representative == null) {
        points ??= await exercises!.analysisRoute(session.id);
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
      var month = DateTime(today.year, today.month);
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
      fastest: fastest,
      fastestSession: fastestSession,
      representative: representative,
      route: representativeRoute,
    );
  }
}
