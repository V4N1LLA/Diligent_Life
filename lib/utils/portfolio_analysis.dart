import '../models/exercise_session.dart';
import 'gps.dart';
import 'movement_analysis.dart';

// A global map budget is shared across sessions. Keep every segment endpoint,
// even if many pauses mean exceeding the target; never draw across missing GPS.
List<RoutePoint> sampleOverviewRoute(List<RoutePoint> points, int target) {
  if (points.length <= target) return points;
  final stride = (points.length / target).ceil();
  return [
    for (var i = 0; i < points.length; i++)
      if (i == 0 ||
          i == points.length - 1 ||
          i % stride == 0 ||
          points[i - 1].segment != points[i].segment ||
          points[i + 1].segment != points[i].segment)
        points[i],
  ];
}

// Derived display data only. Originals are always retained in SQLite/backups.
class PortfolioAnalysis {
  const PortfolioAnalysis(this.route, this.fastest, {this.movement});
  final MovementAnalysis? movement;
  final List<RoutePoint> route;
  final SpeedSection? fastest;
  Map<String, Object?> toMap() => {
    'movement': movement?.toMap(),
    'route': route.map((p) => p.toMap(0)).toList(),
    'fastest': fastest == null
        ? null
        : {
            'points': fastest!.points.map((p) => p.toMap(0)).toList(),
            'meters': fastest!.meters,
            'seconds': fastest!.seconds,
          },
  };
  factory PortfolioAnalysis.fromMap(Map<String, dynamic> m) {
    List<RoutePoint> points(dynamic value) => (value as List)
        .map((p) => RoutePoint.fromMap(Map<String, Object?>.from(p as Map)))
        .toList();
    final best = m['fastest'] as Map?;
    return PortfolioAnalysis(
      points(m['route']),
      best == null
          ? null
          : SpeedSection(
              points(best['points']),
              (best['meters'] as num).toDouble(),
              (best['seconds'] as num).toDouble(),
            ),
      movement: m['movement'] == null
          ? null
          : MovementAnalysis.fromMap(
              Map<String, dynamic>.from(m['movement'] as Map),
            ),
    );
  }
}
