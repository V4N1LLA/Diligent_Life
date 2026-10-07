import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'exercise_session.dart';
import '../utils/gps.dart';
import '../utils/movement_analysis.dart';

const explorationRuleVersion = 1;

// Standard Web Mercator z17 cells: 306m at the equator, ~244m in Seoul.
// Version and projection are part of the ID; no address or exact fix is stored.
class ExplorationCell {
  const ExplorationCell(this.x, this.y, {this.zoom = 17});
  final int x, y, zoom;
  String get id => 'wm$zoom.$x.$y.v1';
  static ExplorationCell? parse(String id) {
    final m = RegExp(r'^wm17\.(\d+)\.(\d+)\.v1$').firstMatch(id);
    if (m == null) return null;
    final x = int.tryParse(m[1]!), y = int.tryParse(m[2]!);
    if (x == null || y == null || x >= 1 << 17 || y >= 1 << 17) {
      return null;
    }
    final cell = ExplorationCell(x, y);
    return cell.id == id ? cell : null;
  }

  static ExplorationCell at(
    double latitude,
    double longitude, {
    int zoom = 17,
  }) {
    final n = 1 << zoom;
    final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    final x = ((longitude + 180) / 360 * n).floor().clamp(0, n - 1);
    final y =
        ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n)
            .floor()
            .clamp(0, n - 1);
    return ExplorationCell(x, y, zoom: zoom);
  }

  LatLng corner(int dx, int dy) {
    final n = 1 << zoom;
    final v = math.pi * (1 - 2 * (y + dy) / n);
    return LatLng(
      math.atan((math.exp(v) - math.exp(-v)) / 2) * 180 / math.pi,
      (x + dx) / n * 360 - 180,
    );
  }

  List<LatLng> get polygon => [
    corner(0, 0),
    corner(1, 0),
    corner(1, 1),
    corner(0, 1),
  ];

  // A fix whose accuracy circle touches the boundary cannot prove cell entry.
  bool containsConfidently(RoutePoint p) {
    final nw = corner(0, 0), se = corner(1, 1);
    final scale = 111195 * math.cos(p.latitude * math.pi / 180);
    final edge = [
      (p.longitude - nw.longitude) * scale,
      (se.longitude - p.longitude) * scale,
      (nw.latitude - p.latitude) * 111195,
      (p.latitude - se.latitude) * 111195,
    ].reduce(math.min);
    return edge > p.accuracy + 5;
  }
}

class ExplorationSummary {
  const ExplorationSummary(this.cells, this.monthCount, this.newIds);
  final List<ExplorationCell> cells;
  final int monthCount;
  final Set<String> newIds;
}

// Run only after a finished workout, in an isolate. No inferred edge crossings.
Set<String> qualifyingCells(
  ExerciseSession session,
  List<Map<String, Object?>> raw,
  MovementAnalysis analysis,
) {
  final trusted = analysis.sections
      .where((s) => s.kind == MovementKind.moving && s.recordEligible)
      .toList();
  final result = <String>{};
  int window = 0, samples = 0;
  RoutePoint? previous, first;
  String? cellId;
  double meters = 0;
  void reset() {
    previous = first = null;
    cellId = null;
    meters = 0;
    samples = 0;
  }

  for (final row in raw) {
    final stamp = DateTime.tryParse(row['timestamp'] as String? ?? '');
    if (stamp == null) {
      reset();
      continue;
    }
    while (window < trusted.length && stamp.isAfter(trusted[window].end)) {
      window++;
    }
    final lat = row['latitude'],
        lon = row['longitude'],
        accuracy = row['accuracy'];
    final speed = row['rawSpeed'];
    if (window == trusted.length ||
        stamp.isBefore(trusted[window].start) ||
        !['accepted', 'stationary_noise'].contains(row['decision']) ||
        lat is! num ||
        !lat.isFinite ||
        lat.abs() > 85 ||
        lon is! num ||
        !lon.isFinite ||
        lon.abs() > 180 ||
        accuracy is! num ||
        !accuracy.isFinite ||
        accuracy <= 0 ||
        accuracy > 15 ||
        speed is! num ||
        !speed.isFinite ||
        speed < AnalysisPolicy.movingSpeed(session.type) ||
        speed > AnalysisPolicy.maxSpeed(session.type)) {
      reset();
      continue;
    }
    final p = RoutePoint.fromMap(row);
    final cell = ExplorationCell.at(p.latitude, p.longitude);
    if (!cell.containsConfidently(p)) {
      reset();
      continue;
    }
    final dt = previous == null
        ? 0.0
        : p.timestamp.difference(previous!.timestamp).inMicroseconds / 1e6;
    final distance = previous == null ? 0.0 : metersBetween(previous!, p);
    if (previous == null ||
        cell.id != cellId ||
        p.segment != previous!.segment ||
        dt <= 0 ||
        dt > AnalysisPolicy.maxGapSeconds ||
        distance / dt > AnalysisPolicy.maxSpeed(session.type)) {
      reset();
      first = p;
      cellId = cell.id;
    } else {
      meters += math.min(
        distance,
        math.min(previous!.rawSpeed!, p.rawSpeed!) * dt,
      );
    }
    samples++;
    previous = p;
    if (samples >= 3 &&
        meters >= 60 &&
        p.timestamp.difference(first!.timestamp).inSeconds >= 20 &&
        metersBetween(first!, p) >= 50) {
      result.add(cell.id);
    }
  }
  return result;
}
