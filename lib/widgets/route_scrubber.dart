import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/exercise_session.dart';
import '../models/route_exploration.dart';
import '../utils/gps.dart';
import '../theme/app_theme.dart';
import 'activity_style.dart';
import 'exercise_route.dart';

class RouteScrubber extends StatefulWidget {
  const RouteScrubber({
    super.key,
    required this.points,
    this.tileProvider,
    this.summary,
  });
  final List<RoutePoint> points;
  final Widget? summary;
  final TileProvider? tileProvider;
  @override
  State<RouteScrubber> createState() => _RouteScrubberState();
}

class _RouteScrubberState extends State<RouteScrubber> {
  late RouteExploration _route;
  double _value = 0;
  RangeValues _range = const RangeValues(0, 1);
  bool _select = false;
  int _hapticBucket = -1;
  DateTime? _lastHaptic;
  @override
  void initState() {
    super.initState();
    _route = RouteExploration(widget.points);
  }

  @override
  void didUpdateWidget(RouteScrubber old) {
    super.didUpdateWidget(old);
    if (!identical(old.points, widget.points)) {
      _route = RouteExploration(widget.points);
      _value = 0;
      _range = const RangeValues(0, 1);
    }
  }

  void _feedback(double value) {
    final bucket = (value * 20).floor();
    final now = DateTime.now();
    if (bucket != _hapticBucket &&
        (_lastHaptic == null ||
            now.difference(_lastHaptic!).inMilliseconds >= 150)) {
      _hapticBucket = bucket;
      _lastHaptic = now;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('저장된 GPS 경로가 없어요.'),
          if (widget.summary != null) widget.summary!,
        ],
      );
    }
    final index = _route.indexAt(_value),
        start = _route.indexAt(_range.start),
        end = _route.indexAt(_range.end);
    final seconds = _route.seconds(start, end),
        meters = _route.meters(start, end);
    final speed = _route.speed(index);
    final selected = _select && end > start
        ? SpeedSection(points.sublist(start, end + 1), meters, seconds)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExerciseRoute(
          points: points,
          height: 280,
          tileProvider: widget.tileProvider,
          selectedPoint: points[index],
          selectedSection: selected,
        ),
        if (widget.summary != null) ...[
          const SizedBox(height: AppSpace.section),
          widget.summary!,
        ],
        const ActivitySection('움직임 살펴보기'),
        Text(_select ? '양쪽 손잡이로 구간을 골라보세요.' : '바를 움직이면 기록된 시점의 위치를 보여줘요.'),
        const SizedBox(height: AppSpace.large),
        ActivitySurface(
          child: Wrap(
            spacing: AppSpace.large,
            runSpacing: AppSpace.medium,
            children: [
              _PositionMetric(
                '지도 속 위치',
                '${(_route.distances[index] / 1000).toStringAsFixed(2)} km',
              ),
              _PositionMetric(
                '시작 후',
                elapsedLabel(
                  points[index].timestamp
                      .difference(points.first.timestamp)
                      .inSeconds,
                ),
              ),
              _PositionMetric(
                '페이스',
                speed != null && speed > 0 ? paceLabel(3600 / speed) : '—',
              ),
            ],
          ),
        ),
        if (points.length > 1 && _route.span > 0) ...[
          if (_select)
            RangeSlider(
              values: _range,
              labels: RangeLabels(
                '${(_range.start * _route.span / 60).toStringAsFixed(1)}분',
                '${(_range.end * _route.span / 60).toStringAsFixed(1)}분',
              ),
              semanticFormatterCallback: (v) =>
                  '기록 시작 후 ${(v * _route.span / 60).toStringAsFixed(1)}분',
              onChanged: (value) {
                _feedback(value.end);
                setState(() {
                  _range = value;
                  _value = value.end;
                });
              },
            )
          else
            Slider(
              value: _value,
              semanticFormatterCallback: (v) =>
                  '기록 시작 후 ${(v * _route.span / 60).toStringAsFixed(1)}분',
              onChanged: (value) {
                _feedback(value);
                setState(() => _value = value);
              },
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('구간 선택'),
            value: _select,
            onChanged: (v) => setState(() => _select = v),
          ),
        ],
        if (_select)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.large),
            child: Text(
              '선택 구간 ${(meters / 1000).toStringAsFixed(2)}km · ${elapsedLabel(seconds.round())}\n평균 ${seconds > 0 ? (meters / seconds * 3.6).toStringAsFixed(1) : '—'}km/h · ${meters > 0 && seconds > 0 ? paceLabel(seconds / meters * 1000) : '—'}',
            ),
          ),
        if (!_select)
          Text(
            '시작 후 ${elapsedLabel(points[index].timestamp.difference(points.first.timestamp).inSeconds)} · ${(_route.distances[index] / 1000).toStringAsFixed(2)}km · ${speed == null ? '속도 정보 없음' : '${speed.toStringAsFixed(1)}km/h'}',
          ),
        const SizedBox(height: AppSpace.large),
        Text('속도의 흐름', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpace.medium),
        SizedBox(
          height: 64,
          child: CustomPaint(
            painter: _ScrubPainter(
              _route,
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.medium),
        const Text(
          '기록된 GPS만 표시해요. 수신 공백·일시정지 구간은 연결하거나 시간·거리를 더하지 않아요.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _PositionMetric extends StatelessWidget {
  const _PositionMetric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: AppSpace.tiny),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

class _ScrubPainter extends CustomPainter {
  _ScrubPainter(this.route, this.color, this.grid);
  final RouteExploration route;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = grid,
    );
    if (route.span <= 0) return;
    final stride = math.max(1, (route.points.length / 300).ceil());
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var i = 1; i < route.points.length; i += stride) {
      final speed = route.speed(i);
      if (speed == null) continue;
      final x =
          route.points[i].timestamp
              .difference(route.points.first.timestamp)
              .inMilliseconds /
          1000 /
          route.span *
          size.width;
      final h = (speed / 20).clamp(0, 1) * size.height;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrubPainter old) =>
      old.route != route || old.color != color || old.grid != grid;
}
