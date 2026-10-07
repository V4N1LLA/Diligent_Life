import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/exercise_session.dart';
import '../utils/gps.dart';

Color speedColor(double kmh) => kmh < 4
    ? const Color(0xff527d6b)
    : kmh < 7
    ? const Color(0xff527fa3)
    : const Color(0xff8560aa);
LatLng routeLocation(RoutePoint p) => LatLng(p.latitude, p.longitude);

// Immutable completed chunks retain flutter_map's geometry caches. Only the
// open tail (at most 128 edges) and newly completed speed windows are rebuilt.
// This is display geometry; no recorded points or analysis inputs are changed.
class RoutePolylineCache {
  List<RoutePoint>? _source;
  List<SpeedSection>? _sections;
  bool _overview = false;
  final _completed = <Polyline>[];
  final _speedLines = <Polyline>[];
  final _tail = <LatLng>[];
  final _speedWindow = <RoutePoint>[];
  int? _segment;
  double _meters = 0, _seconds = 0;
  List<Polyline> lines = const [];

  void sync(
    List<RoutePoint> points, {
    List<SpeedSection>? sections,
    bool overview = false,
    bool incremental = false,
  }) {
    if (identical(points, _source) &&
        identical(sections, _sections) &&
        overview == _overview) {
      return;
    }
    final previous = _source;
    final append =
        incremental &&
        previous != null &&
        previous.isNotEmpty &&
        points.length > previous.length &&
        identical(points.first, previous.first) &&
        identical(points[previous.length - 1], previous.last) &&
        identical(sections, _sections) &&
        overview == _overview;
    final start = append ? previous.length : 0;
    if (!append) {
      _completed.clear();
      _speedLines.clear();
      _tail.clear();
      _speedWindow.clear();
      _segment = null;
      _meters = _seconds = 0;
    }
    for (final point in points.skip(start)) {
      if (_segment != null && point.segment != _segment) {
        _freezeTail();
        _tail.clear();
      }
      _segment = point.segment;
      _tail.add(routeLocation(point));
      if (_tail.length == 129) {
        _freezeTail();
        final last = _tail.last;
        _tail.clear();
        _tail.add(last); // Shared endpoint; no gap between adjacent chunks.
      }
      if (!overview && sections == null) _addSpeed(point);
    }
    if (!overview && sections != null && !append) {
      _speedLines.addAll(sections.map(_speedLine));
    }
    lines = List.unmodifiable([
      ..._completed,
      if (_tail.length > 1) _baseLine(_tail),
      ..._speedLines,
    ]);
    _source = points;
    _sections = sections;
    _overview = overview;
  }

  Polyline _baseLine(List<LatLng> points) => Polyline(
    points: List.unmodifiable(points),
    color: const Color(0xff527d6b),
    strokeWidth: 5,
  );

  void _freezeTail() {
    if (_tail.length > 1) _completed.add(_baseLine(_tail));
  }

  Polyline _speedLine(SpeedSection s) => Polyline(
    points: s.points.map(routeLocation).toList(growable: false),
    color: speedColor(s.kmh),
    strokeWidth: 5,
  );

  // Same boundaries and sums as speedSections, without rescanning old points.
  void _addSpeed(RoutePoint p) {
    if (_speedWindow.isNotEmpty) {
      final previous = _speedWindow.last;
      final dt =
          p.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
      final distance = metersBetween(previous, p);
      if (p.segment != previous.segment ||
          dt <= 0 ||
          dt > TrackingPolicy.maxGapSeconds ||
          distance / dt > TrackingPolicy.absoluteMaxSpeed) {
        _flushSpeed();
      } else {
        _meters += distance;
        _seconds += dt;
      }
    }
    _speedWindow.add(p);
    if (_seconds >= TrackingPolicy.smoothingSeconds) {
      _flushSpeed();
      _speedWindow.add(p);
    }
  }

  void _flushSpeed() {
    if (_speedWindow.length > 1 &&
        _seconds >= TrackingPolicy.smoothingSeconds) {
      _speedLines.add(
        _speedLine(
          SpeedSection(List.unmodifiable(_speedWindow), _meters, _seconds),
        ),
      );
    }
    _speedWindow.clear();
    _meters = _seconds = 0;
  }
}
