import 'package:diligent_life/models/exercise_session.dart';
import 'package:diligent_life/utils/gps.dart';
import 'package:diligent_life/utils/portfolio_analysis.dart';

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
