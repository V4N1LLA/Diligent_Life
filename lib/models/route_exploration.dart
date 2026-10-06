import '../models/exercise_session.dart';
import '../utils/gps.dart';

// A read-only view of accepted samples. It never interpolates a missing GPS fix.
class RouteExploration {
  RouteExploration(this.points) {
    for (var i = 0; i < points.length; i++) {
      double seconds = 0, meters = 0;
      if (i > 0) {
        final a = points[i - 1], b = points[i];
        final dt = b.timestamp.difference(a.timestamp).inMilliseconds / 1000;
        if (a.segment == b.segment &&
            dt > 0 &&
            dt <= TrackingPolicy.maxGapSeconds) {
          seconds = dt;
          // Recorded cumulative distance is authoritative when available.
          final x = a.cumulativeMeters, y = b.cumulativeMeters;
          meters = x != null && y != null
              ? (y - x).clamp(0, double.infinity)
              : metersBetween(a, b);
        }
      }
      times.add((times.lastOrNull ?? 0) + seconds);
      distances.add((distances.lastOrNull ?? 0) + meters);
    }
  }
  final List<RoutePoint> points;
  final List<double> times = [], distances = [];
  double get span => points.length < 2
      ? 0
      : points.last.timestamp
                .difference(points.first.timestamp)
                .inMilliseconds /
            1000;
  int indexAt(double fraction) {
    if (points.length < 2) return 0;
    final stamp =
        points.first.timestamp.millisecondsSinceEpoch +
        (span * 1000 * fraction).round();
    int low = 0, high = points.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (points[mid].timestamp.millisecondsSinceEpoch < stamp) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 &&
        (points[low].timestamp.millisecondsSinceEpoch - stamp) >
            (stamp - points[low - 1].timestamp.millisecondsSinceEpoch)) {
      return low - 1;
    }
    return low;
  }

  double seconds(int start, int end) => times[end] - times[start];
  double meters(int start, int end) => distances[end] - distances[start];
  double? speed(int index) {
    if (index == 0) return null;
    final sec = seconds(index - 1, index);
    return sec <= 0 ? null : meters(index - 1, index) / sec * 3.6;
  }
}
