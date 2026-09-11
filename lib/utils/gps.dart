import 'dart:math' as math;

import '../models/exercise_session.dart';
import '../models/exercise_type.dart';

class TrackingPolicy {
  static const version = 2;
  static const maxAccuracy = 30.0;
  static const maxGapSeconds = 30;
  static const smoothingSeconds = 5;
  static const absoluteMaxSpeed = 12.0;
  static double maxSpeed(ExerciseType type) => switch (type) {
    ExerciseType.lightWalk || ExerciseType.briskWalk => 3.5,
    ExerciseType.jogging => 6.0,
    ExerciseType.running || ExerciseType.other => absoluteMaxSpeed,
  };
}

double metersBetween(RoutePoint a, RoutePoint b) {
  const radians = math.pi / 180;
  final lat = (b.latitude - a.latitude) * radians;
  final lon = (b.longitude - a.longitude) * radians;
  final h =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(a.latitude * radians) *
          math.cos(b.latitude * radians) *
          math.pow(math.sin(lon / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
}

class GpsFilter {
  GpsFilter({this.maxSpeed = TrackingPolicy.absoluteMaxSpeed});
  final double maxSpeed;
  RoutePoint? _anchor;
  RoutePoint? _previousFix;
  bool _gap = false;
  String decision = 'accepted';
  int get segment => _segment;
  DateTime? _latestTimestamp;
  int _segment = 0;
  double addedMeters = 0;
  void breakSegment() {
    _anchor = null;
    _previousFix = null;
    _gap = false;
    _segment++;
  }

  RoutePoint? accept(RoutePoint point, DateTime now) {
    addedMeters = 0;
    decision = 'quality';
    if (!point.latitude.isFinite ||
        point.latitude.abs() > 90 ||
        !point.longitude.isFinite ||
        point.longitude.abs() > 180 ||
        !point.accuracy.isFinite ||
        point.accuracy <= 0 ||
        point.accuracy > TrackingPolicy.maxAccuracy ||
        now.difference(point.timestamp).inSeconds > 15 ||
        point.timestamp.difference(now).inSeconds > 5 ||
        (_latestTimestamp != null &&
            !point.timestamp.isAfter(_latestTimestamp!))) {
      return null;
    }
    _latestTimestamp = point.timestamp;
    final fix = _previousFix;
    _previousFix = point;
    if (fix != null) {
      final dt =
          point.timestamp.difference(fix.timestamp).inMilliseconds / 1000;
      if (dt <= TrackingPolicy.maxGapSeconds &&
          metersBetween(fix, point) / dt > maxSpeed) {
        _gap = true;
        decision = 'implausible_speed';
        return null;
      }
    }
    final previous = _anchor;
    if (previous != null) {
      final seconds =
          point.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
      if (seconds > TrackingPolicy.maxGapSeconds || _gap) {
        breakSegment();
      } else {
        final distance = metersBetween(previous, point);
        // Reject implausible human running speeds and stationary GPS jitter.
        if (distance / seconds > maxSpeed) {
          _gap = true;
          decision = 'implausible_speed';
          return null;
        }
        if (distance <
            math.max(4, (previous.accuracy + point.accuracy) * .35)) {
          decision = 'stationary_noise';
          return null;
        }
        addedMeters = distance;
      }
    }
    decision = 'accepted';
    _previousFix = point;
    return _anchor = point.inSegment(_segment);
  }
}

class SpeedSection {
  const SpeedSection(this.points, this.meters, this.seconds);
  final List<RoutePoint> points;
  final double meters, seconds;
  double get kmh => seconds <= 0 ? 0 : meters / seconds * 3.6;
  double? get paceSeconds => meters < 1 ? null : seconds / meters * 1000;
}

// Non-overlapping >=5 second windows; never smooth across a pause or GPS gap.
// Distance/time weighting avoids averaging noisy one-second speed readings.
List<SpeedSection> speedSections(List<RoutePoint> points) {
  final result = <SpeedSection>[];
  var window = <RoutePoint>[];
  double meters = 0, seconds = 0;
  void flush() {
    if (window.length > 1 && seconds >= TrackingPolicy.smoothingSeconds) {
      result.add(SpeedSection(List.unmodifiable(window), meters, seconds));
    }
    window = [];
    meters = 0;
    seconds = 0;
  }

  for (final p in points) {
    if (window.isNotEmpty) {
      final previous = window.last;
      final dt =
          p.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
      final distance = metersBetween(previous, p);
      if (p.segment != previous.segment ||
          dt <= 0 ||
          dt > TrackingPolicy.maxGapSeconds ||
          distance / dt > TrackingPolicy.absoluteMaxSpeed) {
        flush();
      } else {
        meters += distance;
        seconds += dt;
      }
    }
    window.add(p);
    if (seconds >= TrackingPolicy.smoothingSeconds) {
      flush();
      window.add(p);
    }
  }
  flush();
  return result;
}

// Remove every visit near either endpoint (including loops), and split the
// remaining path so a line cannot reconnect across a hidden section.
List<RoutePoint> privateRoute(
  List<RoutePoint> points, {
  double radiusMeters = 200,
}) {
  if (points.isEmpty) return [];
  final result = <RoutePoint>[];
  int segment = 0;
  RoutePoint? previous;
  bool gap = true;
  for (final point in points) {
    if (metersBetween(points.first, point) <= radiusMeters ||
        metersBetween(points.last, point) <= radiusMeters) {
      gap = true;
      continue;
    }
    if (gap ||
        previous?.segment != point.segment ||
        (previous != null &&
            (_edgeNear(previous, point, points.first, radiusMeters) ||
                _edgeNear(previous, point, points.last, radiusMeters)))) {
      segment++;
    }
    result.add(point.inSegment(segment));
    previous = point;
    gap = false;
  }
  return result;
}

// A sparse edge may cross a protected circle even when both fixes are outside.
// Local metric projection is conservative at the 200m privacy scale.
bool _edgeNear(RoutePoint a, RoutePoint b, RoutePoint center, double radius) {
  final cosLat = math.cos(center.latitude * math.pi / 180);
  double x(RoutePoint p) =>
      ((p.longitude - center.longitude + 540) % 360 - 180) * 111195 * cosLat;
  double y(RoutePoint p) => (p.latitude - center.latitude) * 111195;
  final ax = x(a), ay = y(a), dx = x(b) - x(a), dy = y(b) - y(a);
  final length2 = dx * dx + dy * dy;
  final t = length2 == 0
      ? 0.0
      : (-(ax * dx + ay * dy) / length2).clamp(0.0, 1.0);
  return math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)) <=
      radius + 1;
}

String elapsedLabel(int seconds) =>
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
    '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:'
    '${(seconds % 60).toString().padLeft(2, '0')}';
String paceLabel(double? seconds) => seconds == null || !seconds.isFinite
    ? '—'
    : '${seconds.round() ~/ 60}:${(seconds.round() % 60).toString().padLeft(2, '0')} /km';
