import 'dart:math' as math;

import '../models/exercise_session.dart';
import '../models/exercise_type.dart';
import 'gps.dart';

class AnalysisPolicy {
  static const version = 2;
  static const windowSeconds = 6.0;
  static const stopSeconds = 10.0;
  static const maxGapSeconds = 15.0;
  static double maxSpeed(ExerciseType type) => switch (type) {
    ExerciseType.lightWalk => 3.0,
    ExerciseType.briskWalk => 3.5,
    ExerciseType.jogging => 5.0,
    ExerciseType.running || ExerciseType.other => 12.0,
  };
  static double movingSpeed(ExerciseType type) => switch (type) {
    ExerciseType.lightWalk || ExerciseType.briskWalk => .45,
    _ => .6,
  };
}

enum MovementKind { moving, stopped }

class MovementSection {
  const MovementSection(
    this.points,
    this.meters,
    this.kind, {
    this.recordEligible = true,
    this.sensorKmh,
    this.coordinateKmh,
  });
  final bool recordEligible;
  final double? sensorKmh, coordinateKmh;
  final List<RoutePoint> points;
  final double meters;
  final MovementKind kind;
  DateTime get start => points.first.timestamp;
  DateTime get end => points.last.timestamp;
  double get seconds => end.difference(start).inMicroseconds / 1e6;
  double get kmh => seconds <= 0 ? 0 : meters / seconds * 3.6;
  SpeedSection get speed => SpeedSection(points, meters, seconds);
  Map<String, Object?> toMap() => {
    'points': points.map((p) => p.toMap(0)).toList(),
    'meters': meters,
    'kind': kind.name,
    'recordEligible': recordEligible,
    'sensorKmh': sensorKmh,
    'coordinateKmh': coordinateKmh,
  };
  factory MovementSection.fromMap(Map<String, dynamic> m) => MovementSection(
    _points(m['points']),
    (m['meters'] as num).toDouble(),
    MovementKind.values.byName(m['kind'] as String),
    recordEligible: m['recordEligible'] as bool? ?? false,
    sensorKmh: (m['sensorKmh'] as num?)?.toDouble(),
    coordinateKmh: (m['coordinateKmh'] as num?)?.toDouble(),
  );
}

List<RoutePoint> _points(dynamic values) => (values as List)
    .map((p) => RoutePoint.fromMap(Map<String, Object?>.from(p as Map)))
    .toList();

class DistanceBest {
  const DistanceBest(
    this.meters,
    this.start,
    this.end, {
    this.points = const [],
  });
  final List<RoutePoint> points;
  // A conservative GPS uncertainty floor, not a statistical confidence interval.
  double get improvementSeconds {
    final accuracy = points.fold<double>(
      math.max(start.accuracy, end.accuracy),
      (v, p) => math.max(v, p.accuracy),
    );
    return math.max(
      2,
      math.max(seconds * .02, 2 * accuracy * seconds / meters),
    );
  }

  final int meters;
  final RoutePoint start, end;
  double get seconds =>
      end.timestamp.difference(start.timestamp).inMicroseconds / 1e6;
  double get paceSeconds => seconds * 1000 / meters;
  Map<String, Object?> toMap() => {
    'meters': meters,
    'start': start.toMap(0),
    'points': points.map((p) => p.toMap(0)).toList(),
    'end': end.toMap(0),
  };
  factory DistanceBest.fromMap(Map<String, dynamic> m) => DistanceBest(
    m['meters'] as int,
    RoutePoint.fromMap(Map<String, Object?>.from(m['start'] as Map)),
    RoutePoint.fromMap(Map<String, Object?>.from(m['end'] as Map)),
    points: m['points'] == null ? const [] : _points(m['points']),
  );
}

class MovementAnalysis {
  const MovementAnalysis({
    required this.sections,
    required this.bests,
    required this.elapsedSeconds,
    required this.rawAvailable,
    required this.rejectedSamples,
    this.sampleCount = 0,
    this.meanAccuracy,
    this.filterDecisions = const {},
    this.splits = const [],
    this.halves = const [],
  });
  final List<MovementSection> sections;
  final List<DistanceBest> bests;
  final int elapsedSeconds, rejectedSamples, sampleCount;
  final double? meanAccuracy;
  final Map<String, int> filterDecisions;
  final List<MovementLap> splits, halves;
  int get lowConfidenceSections => sections
      .where((s) => s.kind == MovementKind.moving && !s.recordEligible)
      .length;
  List<MovementSection> get stops =>
      sections.where((s) => s.kind == MovementKind.stopped).toList();
  int get stopCount {
    int count = 0;
    DateTime? end;
    for (final s in stops) {
      if (end != s.start) count++;
      end = s.end;
    }
    return count;
  }

  double get longestStop {
    double longest = 0, seconds = 0;
    DateTime? end;
    for (final s in stops) {
      seconds = end == s.start ? seconds + s.seconds : s.seconds;
      longest = math.max(longest, seconds);
      end = s.end;
    }
    return longest;
  }

  List<double> get speedDistribution {
    final bins = List.filled(3, 0.0);
    for (final s in sections.where((s) => s.kind == MovementKind.moving)) {
      bins[s.kmh < 4
              ? 0
              : s.kmh < 7
              ? 1
              : 2] +=
          s.seconds;
    }
    return bins;
  }

  String get qualityLabel => !rawAvailable || sampleCount == 0
      ? '원본 없음'
      : unknownSeconds / math.max(1, elapsedSeconds) > .2 ||
            rejectedSamples / sampleCount > .1 ||
            (meanAccuracy ?? 100) > 20
      ? '주의'
      : lowConfidenceSections > 0 ||
            unknownSeconds / math.max(1, elapsedSeconds) > .05
      ? '일부 불확실'
      : '양호';
  final bool rawAvailable;
  double get movingSeconds => sections
      .where((s) => s.kind == MovementKind.moving)
      .fold(0, (v, s) => v + s.seconds);
  double get stoppedSeconds => sections
      .where((s) => s.kind == MovementKind.stopped)
      .fold(0, (v, s) => v + s.seconds);
  double get unknownSeconds =>
      math.max(0, elapsedSeconds - movingSeconds - stoppedSeconds);
  double get meters => sections.fold(0, (v, s) => v + s.meters);
  double? get averageMovingKmh =>
      movingSeconds > 0 ? meters / movingSeconds * 3.6 : null;
  MovementSection? get fastest {
    MovementSection? best;
    for (final section in sections) {
      if (section.kind == MovementKind.moving &&
          section.seconds >= AnalysisPolicy.windowSeconds &&
          section.recordEligible &&
          (best == null || section.kmh > best.kmh)) {
        best = section;
      }
    }
    return best;
  }

  List<RoutePoint> get route => [for (final s in sections) ...s.points];
  Map<String, Object?> toMap() => {
    'version': AnalysisPolicy.version,
    'sections': sections.map((s) => s.toMap()).toList(),
    'bests': bests.map((b) => b.toMap()).toList(),
    'elapsedSeconds': elapsedSeconds,
    'rawAvailable': rawAvailable,
    'rejectedSamples': rejectedSamples,
    'sampleCount': sampleCount,
    'meanAccuracy': meanAccuracy,
    'filterDecisions': filterDecisions,
    'splits': splits.map((s) => s.toMap()).toList(),
    'halves': halves.map((s) => s.toMap()).toList(),
  };
  factory MovementAnalysis.fromMap(Map<String, dynamic> m) => MovementAnalysis(
    sections: (m['sections'] as List)
        .map(
          (s) => MovementSection.fromMap(Map<String, dynamic>.from(s as Map)),
        )
        .toList(),
    bests: (m['bests'] as List)
        .map((b) => DistanceBest.fromMap(Map<String, dynamic>.from(b as Map)))
        .toList(),
    elapsedSeconds: m['elapsedSeconds'] as int,
    rawAvailable: m['rawAvailable'] as bool,
    rejectedSamples: m['rejectedSamples'] as int,
    sampleCount: m['sampleCount'] as int? ?? 0,
    meanAccuracy: (m['meanAccuracy'] as num?)?.toDouble(),
    filterDecisions: Map<String, int>.from(m['filterDecisions'] as Map? ?? {}),
    splits: [
      for (final s in m['splits'] as List? ?? []) MovementLap.fromMap(s),
    ],
    halves: [
      for (final s in m['halves'] as List? ?? []) MovementLap.fromMap(s),
    ],
  );
}

// Streaming quality gates + centred three-fix median + six-second geometry
// windows. Rejected raw decisions are re-evaluated; before_segment is never used.
class MovementAnalyzer {
  MovementAnalyzer(this.session, {required this.rawAvailable});
  final ExerciseSession session;
  final bool rawAvailable;
  final _median = <RoutePoint>[];
  final _window = <RoutePoint>[];
  final _pendingStops = <MovementSection>[];
  final _sections = <MovementSection>[];
  RoutePoint? _previous;
  DateTime? _latest;
  int _segment = 0, _rejected = 0;
  double _covered = 0, _accuracyTotal = 0;
  int _samples = 0, _accuracyCount = 0;
  final _decisions = <String, int>{};
  final _rawWindow = <RoutePoint>[];

  void addRow(Map<String, Object?> row) {
    final lat = row['latitude'],
        lon = row['longitude'],
        accuracy = row['accuracy'];
    _samples++;
    final decision = row['decision'] as String? ?? 'legacy';
    _decisions.update(decision, (n) => n + 1, ifAbsent: () => 1);
    if (accuracy is num && accuracy.isFinite && accuracy > 0) {
      _accuracyTotal += accuracy;
      _accuracyCount++;
    }
    final timestamp = DateTime.tryParse(row['timestamp'] as String? ?? '');
    final received = DateTime.tryParse(row['receivedAt'] as String? ?? '');
    if (row['decision'] == 'before_segment' ||
        timestamp == null ||
        lat is! num ||
        !lat.isFinite ||
        lat.abs() > 90 ||
        lon is! num ||
        !lon.isFinite ||
        lon.abs() > 180 ||
        accuracy is! num ||
        !accuracy.isFinite ||
        accuracy <= 0 ||
        accuracy > TrackingPolicy.maxAccuracy ||
        timestamp.isBefore(session.startedAt) ||
        (session.endedAt != null && timestamp.isAfter(session.endedAt!)) ||
        (received != null &&
            (received.difference(timestamp).inMilliseconds > 15000 ||
                timestamp.difference(received).inMilliseconds > 5000))) {
      _rejected++;
      _break();
      _previous = null;
      return;
    }
    if (_latest != null && !timestamp.isAfter(_latest!)) {
      _rejected++;
      return;
    }
    _latest = timestamp;
    final p = RoutePoint(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      timestamp: timestamp,
      accuracy: accuracy.toDouble(),
      segment: row['segment'] as int,
      rawSpeed:
          row['rawSpeed'] is num &&
              (row['rawSpeed'] as num).isFinite &&
              (row['rawSpeed'] as num) >= 0 &&
              (row['rawSpeed'] as num) <= TrackingPolicy.absoluteMaxSpeed
          ? (row['rawSpeed'] as num).toDouble()
          : null,
    );
    final previous = _previous;
    _previous = p;
    if (previous != null) {
      final dt =
          p.timestamp.difference(previous.timestamp).inMicroseconds / 1e6;
      // The recorder starts a new segment when its stationary distance anchor
      // ages past 30s. That is not a GPS outage. Join only corroborated stationary
      // fixes in a session whose wall/active clocks prove there was no pause.
      // Historical sessions with any pause retain all segment boundaries.
      final noPause =
          session.endedAt != null &&
          (session.endedAt!.difference(session.startedAt).inMicroseconds / 1e6 -
                      session.elapsedSeconds)
                  .abs() <=
              1.1;
      final stationaryBoundary =
          rawAvailable &&
          noPause &&
          p.rawSpeed != null &&
          previous.rawSpeed != null &&
          p.rawSpeed! < .3 &&
          previous.rawSpeed! < .3 &&
          metersBetween(previous, p) <=
              ((previous.accuracy + p.accuracy) * .25).clamp(3.0, 8.0);
      if ((p.segment != previous.segment && !stationaryBoundary) ||
          dt > AnalysisPolicy.maxGapSeconds) {
        _break();
      } else if (metersBetween(previous, p) / dt >
          math.max(12.0, AnalysisPolicy.maxSpeed(session.type) * 3)) {
        // Activity limits apply after smoothing, not to noisy one-fix speeds.
        // Keep comparing consecutive fixes during sustained vehicle travel; do
        // not accept a new distance anchor just because the previous was rejected.
        _rejected++;
        _break();
        return;
      } else if (_median.isEmpty && _window.isEmpty) {
        _pushMedian(previous);
      }
    }
    _pushMedian(p);
  }

  void _pushMedian(RoutePoint p) {
    _rawWindow.add(p);
    if (_median.isEmpty) {
      _median.add(p);
      _push(p);
      return;
    }
    _median.add(p);
    if (_median.length == 3) {
      final center = _median[1];
      double median(double Function(RoutePoint) f) {
        final values = _median.map(f).toList()..sort();
        return values[1];
      }

      // Unwrap longitude around the middle fix for date-line crossings.
      final lon = median(
        (v) =>
            center.longitude +
            ((v.longitude - center.longitude + 540) % 360 - 180),
      );
      _push(
        RoutePoint(
          latitude: median((v) => v.latitude),
          longitude: (lon + 540) % 360 - 180,
          timestamp: center.timestamp,
          accuracy: median((v) => v.accuracy),
          segment: center.segment,
          rawSpeed: center.rawSpeed,
        ),
      );
      _median.removeAt(0);
    }
  }

  void _push(RoutePoint point) {
    final p = point.inSegment(_segment);
    if (_window.isNotEmpty && !_window.last.timestamp.isBefore(p.timestamp)) {
      return;
    }
    _window.add(p);
    final seconds =
        _window.last.timestamp
            .difference(_window.first.timestamp)
            .inMicroseconds /
        1e6;
    if (seconds >= AnalysisPolicy.windowSeconds) {
      final displacement = metersBetween(_window.first, _window.last);
      // At mediocre accuracy, extend plausible slow movement before deciding
      // it is stationary. This avoids repeatedly discarding a short slow walk.
      if (seconds < 12 &&
          displacement < _noiseRadius &&
          displacement / seconds >= AnalysisPolicy.movingSpeed(session.type)) {
        return;
      }
      _flushWindow();
      _window.add(p.inSegment(_segment));
    }
  }

  double get _noiseRadius {
    final accuracy = (_window.map((p) => p.accuracy).toList()
      ..sort())[_window.length ~/ 2];
    return (accuracy * .5).clamp(3.0, 8.0);
  }

  void _flushWindow() {
    if (_window.length < 2) {
      _window.clear();
      return;
    }
    final seconds =
        _window.last.timestamp
            .difference(_window.first.timestamp)
            .inMicroseconds /
        1e6;
    final sensorValues = _window
        .map((p) => p.rawSpeed)
        .whereType<double>()
        .toList();
    final sensorQuiet =
        sensorValues.length == _window.length &&
        sensorValues.every((v) => v < .3);
    final sensorStopped =
        sensorQuiet &&
        metersBetween(_window.first, _window.last) <= _noiseRadius;
    final sensorMoving =
        sensorValues.length == _window.length &&
        sensorValues.every(
          (v) => v >= AnalysisPolicy.movingSpeed(session.type),
        );
    final stationaryTail =
        _pendingStops.isNotEmpty &&
        sensorStopped &&
        metersBetween(_window.first, _window.last) <= _noiseRadius;
    if ((seconds < AnalysisPolicy.windowSeconds && !stationaryTail) ||
        _covered + seconds > session.elapsedSeconds + .001) {
      _window.clear();
      _flushStops();
      _segment++;
      return;
    }
    double distance = 0;
    for (var i = 1; i < _window.length; i++) {
      distance += metersBetween(_window[i - 1], _window[i]);
    }
    final displacement = metersBetween(_window.first, _window.last);
    final noiseRadius = _noiseRadius;
    final moving =
        !sensorQuiet &&
        displacement >= noiseRadius &&
        displacement / seconds >= AnalysisPolicy.movingSpeed(session.type);
    final plausible =
        distance / seconds <= AnalysisPolicy.maxSpeed(session.type);
    if (!plausible) {
      _flushStops();
      _segment++;
    } else if (moving) {
      if (_pendingStops.isNotEmpty) {
        _flushStops();
        _segment++;
      }
      final raw = _rawWindow
          .where(
            (p) =>
                !p.timestamp.isBefore(_window.first.timestamp) &&
                !p.timestamp.isAfter(_window.last.timestamp),
          )
          .toList();
      double sensorMeters = 0, sensorSeconds = 0, coordinateMeters = 0;
      for (var i = 1; i < raw.length; i++) {
        final a = raw[i - 1], b = raw[i];
        final dt = b.timestamp.difference(a.timestamp).inMicroseconds / 1e6;
        coordinateMeters += metersBetween(a, b);
        if (a.rawSpeed != null && b.rawSpeed != null) {
          sensorMeters += (a.rawSpeed! + b.rawSpeed!) * .5 * dt;
          sensorSeconds += dt;
        }
      }
      final sensor = sensorSeconds >= seconds * .8
          ? sensorMeters / sensorSeconds
          : null;
      final coordinate = raw.length < 2
          ? null
          : coordinateMeters /
                (raw.last.timestamp
                        .difference(raw.first.timestamp)
                        .inMicroseconds /
                    1e6);
      final smooth = distance / seconds;
      final accuracy = _window.map((p) => p.accuracy).reduce(math.max);
      final trusted =
          rawAvailable &&
          sensor != null &&
          coordinate != null &&
          accuracy <= 15 &&
          sensor >= AnalysisPolicy.movingSpeed(session.type) &&
          (smooth - sensor).abs() <= math.max(.3, sensor * .2) &&
          (coordinate - sensor).abs() <= math.max(.5, sensor * .35);
      _sections.add(
        MovementSection(
          _window.map((p) => p.inSegment(_segment)).toList(),
          distance,
          MovementKind.moving,
          recordEligible: trusted,
          sensorKmh: sensor == null ? null : sensor * 3.6,
          coordinateKmh: coordinate == null ? null : coordinate * 3.6,
        ),
      );
    } else if (sensorMoving ||
        (sensorQuiet && !sensorStopped) ||
        (!sensorStopped &&
            displacement / seconds >=
                AnalysisPolicy.movingSpeed(session.type))) {
      // Directional movement still inside the accuracy radius is uncertain.
      _flushStops();
      _segment++;
    } else {
      // Legacy accepted-only routes lack stationary fixes: never infer stops
      // from their sparse path or from a GPS outage.
      if (rawAvailable) {
        _pendingStops.add(
          MovementSection(
            [_window.first, _window.last],
            0,
            MovementKind.stopped,
          ),
        );
      } else {
        _flushStops();
        _segment++;
      }
    }
    _covered += seconds;
    final end = _window.last.timestamp;
    _rawWindow.removeWhere((p) => p.timestamp.isBefore(end));
    _window.clear();
  }

  void _flushStops() {
    if (_pendingStops.isNotEmpty) {
      final seconds = _pendingStops.fold<double>(0, (v, s) => v + s.seconds);
      if (seconds >= AnalysisPolicy.stopSeconds) {
        _segment++;
        _sections.add(
          MovementSection(
            [
              _pendingStops.first.points.first.inSegment(_segment),
              _pendingStops.last.points.last.inSegment(_segment),
            ],
            0,
            MovementKind.stopped,
          ),
        );
      }
      _pendingStops.clear();
    }
  }

  void _break() {
    if (_median.isNotEmpty) _push(_median.last);
    _flushWindow();
    _flushStops();
    _median.clear();
    _rawWindow.clear();
    _window.clear();
    _segment++;
  }

  MovementAnalysis finish() {
    _break();
    // Records use all smoothed vertices; only cached display geometry is sampled.
    final bests = fastestDistances(_sections, requireConfidence: true);
    final total = _sections.fold<double>(0, (v, s) => v + s.meters);
    final display = [
      for (final s in _sections)
        MovementSection(
          s.points.length <= 3
              ? s.points
              : [s.points.first, s.points[s.points.length ~/ 2], s.points.last],
          s.meters,
          s.kind,
          recordEligible: s.recordEligible,
          sensorKmh: s.sensorKmh,
          coordinateKmh: s.coordinateKmh,
        ),
    ];
    return MovementAnalysis(
      sections: List.unmodifiable(display),
      bests: bests,
      elapsedSeconds: session.elapsedSeconds,
      rawAvailable: rawAvailable,
      rejectedSamples: _rejected,
      sampleCount: _samples,
      meanAccuracy: _accuracyCount == 0
          ? null
          : _accuracyTotal / _accuracyCount,
      filterDecisions: Map.unmodifiable(_decisions),
      splits: [
        for (final meters in [500.0, 1000.0])
          ...movementLaps(_sections, meters),
      ],
      halves: total <= 0 ? const [] : movementLaps(_sections, total / 2),
    );
  }
}

// Piecewise-linear time/distance interpolation. A minimum occurs when either
// endpoint is a cumulative-distance vertex; test both sets in O(n) per target.
List<DistanceBest> fastestDistances(
  List<MovementSection> sections, {
  bool requireConfidence = false,
}) {
  final bests = <int, DistanceBest>{};
  var run = <RoutePoint>[];
  void flush() {
    if (run.length < 2) {
      run = [];
      return;
    }
    final cumulative = <double>[0];
    for (var i = 1; i < run.length; i++) {
      cumulative.add(cumulative.last + metersBetween(run[i - 1], run[i]));
    }
    for (final target in [100, 500, 1000]) {
      if (cumulative.last < target) continue;
      for (final endAnchored in [false, true]) {
        int other = 1;
        for (var i = 0; i < run.length; i++) {
          final distance = cumulative[i] + (endAnchored ? -target : target);
          if (distance < 0 || distance > cumulative.last) continue;
          while (other < cumulative.length - 1 &&
              cumulative[other] < distance) {
            other++;
          }
          final span = cumulative[other] - cumulative[other - 1];
          if (span <= 0) continue;
          final p = interpolatePoint(
            run[other - 1],
            run[other],
            (distance - cumulative[other - 1]) / span,
          );
          final candidate = DistanceBest(
            target,
            endAnchored ? p : run[i],
            endAnchored ? run[i] : p,
          );
          if (candidate.seconds > 0 &&
              (bests[target] == null ||
                  candidate.seconds < bests[target]!.seconds)) {
            final path = [
              candidate.start,
              ...run.where(
                (p) =>
                    p.timestamp.isAfter(candidate.start.timestamp) &&
                    p.timestamp.isBefore(candidate.end.timestamp),
              ),
              candidate.end,
            ];
            final stride = math.max(1, (path.length / 120).ceil());
            bests[target] = DistanceBest(
              target,
              candidate.start,
              candidate.end,
              points: [
                for (var j = 0; j < path.length - 1; j += stride) path[j],
                path.last,
              ],
            );
          }
        }
      }
    }
    run = [];
  }

  for (final s in sections) {
    if (s.kind != MovementKind.moving ||
        (requireConfidence && !s.recordEligible)) {
      flush();
      continue;
    }
    if (run.isNotEmpty &&
        (run.last.segment != s.points.first.segment ||
            run.last.timestamp != s.start)) {
      flush();
    }
    for (final p in s.points) {
      if (run.isEmpty || run.last.timestamp != p.timestamp) run.add(p);
    }
  }
  flush();
  return [
    for (final target in [100, 500, 1000])
      if (bests[target] != null) bests[target]!,
  ];
}

RoutePoint interpolatePoint(RoutePoint a, RoutePoint b, double fraction) =>
    RoutePoint(
      latitude: a.latitude + (b.latitude - a.latitude) * fraction,
      longitude:
          (a.longitude +
                  ((b.longitude - a.longitude + 540) % 360 - 180) * fraction +
                  540) %
              360 -
          180,
      timestamp: a.timestamp.add(
        Duration(
          microseconds:
              (b.timestamp.difference(a.timestamp).inMicroseconds * fraction)
                  .round(),
        ),
      ),
      accuracy: math.max(a.accuracy, b.accuracy),
      segment: a.segment,
    );

// Splits and halves use valid moving distance/time only. Missing/stopped time is
// not interpolated into a pace. A boundary crossing is explicitly flagged.
class MovementLap {
  const MovementLap(
    this.targetMeters,
    this.index,
    this.meters,
    this.seconds, {
    this.interrupted = false,
    this.partial = false,
  });
  final double targetMeters, meters, seconds;
  final int index;
  final bool interrupted, partial;
  double get kmh => seconds > 0 ? meters / seconds * 3.6 : 0;
  double? get paceSeconds => meters > 0 ? seconds / meters * 1000 : null;
  Map<String, Object?> toMap() => {
    'target': targetMeters,
    'index': index,
    'meters': meters,
    'seconds': seconds,
    'interrupted': interrupted,
    'partial': partial,
  };
  factory MovementLap.fromMap(Map<String, dynamic> m) => MovementLap(
    (m['target'] as num).toDouble(),
    m['index'] as int,
    (m['meters'] as num).toDouble(),
    (m['seconds'] as num).toDouble(),
    interrupted: m['interrupted'] as bool,
    partial: m['partial'] as bool,
  );
}

List<MovementLap> movementLaps(List<MovementSection> sections, double target) {
  if (!target.isFinite || target <= 0) return [];
  final result = <MovementLap>[];
  double meters = 0, seconds = 0;
  bool interrupted = false;
  RoutePoint? last;
  for (final section in sections) {
    if (section.kind != MovementKind.moving) {
      if (meters > .000001) interrupted = true;
      continue;
    }
    if (last != null &&
        (last.timestamp != section.start ||
            last.segment != section.points.first.segment) &&
        meters > .000001) {
      interrupted = true;
    }
    for (var i = 1; i < section.points.length; i++) {
      final a = section.points[i - 1], b = section.points[i];
      var distance = metersBetween(a, b);
      var time = b.timestamp.difference(a.timestamp).inMicroseconds / 1e6;
      if (distance <= 1e-9) {
        seconds += time;
        continue;
      }
      while (distance > 1e-9) {
        final take = math.min(target - meters, distance);
        final dt = time * take / distance;
        meters += take;
        seconds += dt;
        distance -= take;
        time -= dt;
        if (meters >= target - 1e-6) {
          result.add(
            MovementLap(
              target,
              result.length + 1,
              meters,
              seconds,
              interrupted: interrupted,
            ),
          );
          meters = 0;
          seconds = 0;
          interrupted = false;
        }
      }
    }
    last = section.points.last;
  }
  if (meters > 1e-6) {
    result.add(
      MovementLap(
        target,
        result.length + 1,
        meters,
        seconds,
        interrupted: interrupted,
        partial: true,
      ),
    );
  } else if (seconds > 0 && result.isNotEmpty) {
    final last = result.removeLast();
    result.add(
      MovementLap(
        last.targetMeters,
        last.index,
        last.meters,
        last.seconds + seconds,
        interrupted: last.interrupted,
        partial: last.partial,
      ),
    );
  }
  return result;
}
