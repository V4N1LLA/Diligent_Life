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

// Streaming >=5s windows match speedSections, including boundaries between pages.
class PortfolioAnalyzer {
  PortfolioAnalyzer({required this.stride, required this.maxKmh});
  final int stride;
  final double maxKmh;
  final _route = <RoutePoint>[];
  final _window = <RoutePoint>[];
  RoutePoint? _previous;
  SpeedSection? _fastest;
  int _index = 0, _segment = 0;
  double _meters = 0, _seconds = 0;

  void _flush() {
    if (_window.length > 1 && _seconds >= TrackingPolicy.smoothingSeconds) {
      final speed = SpeedSection(List.of(_window), _meters, _seconds);
      if (speed.kmh <= maxKmh &&
          (_fastest == null || speed.kmh > _fastest!.kmh)) {
        _fastest = speed;
      }
    }
    _window.clear();
    _meters = 0;
    _seconds = 0;
  }

  void add(RoutePoint p) {
    final previous = _previous;
    final dt = previous == null
        ? 0.0
        : p.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    final distance = previous == null ? 0.0 : metersBetween(previous, p);
    final gap =
        previous != null &&
        (p.segment != previous.segment ||
            dt <= 0 ||
            dt > TrackingPolicy.maxGapSeconds ||
            distance / dt > TrackingPolicy.absoluteMaxSpeed);
    if (gap) {
      _keep(previous);
      _segment++;
      _flush();
    }
    if (previous == null || gap || _index % stride == 0) _keep(p);
    if (_window.isNotEmpty) {
      _meters += distance;
      _seconds += dt;
    }
    _window.add(p);
    if (_seconds >= TrackingPolicy.smoothingSeconds) {
      _flush();
      _window.add(p);
    }
    _previous = p;
    _index++;
  }

  void _keep(RoutePoint p) {
    if (_route.isEmpty ||
        _route.last.timestamp != p.timestamp ||
        _route.last.segment != _segment) {
      _route.add(p.inSegment(_segment));
    }
  }

  PortfolioAnalysis finish() {
    if (_previous case final p?) _keep(p);
    _flush();
    return PortfolioAnalysis(_route, _fastest);
  }
}
