import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/exercise_session.dart';
import '../utils/movement_analysis.dart';
import 'exercise_route.dart';

String analysisDuration(double seconds) {
  final value = seconds.round();
  return '${value ~/ 60}분 ${value % 60}초';
}

class MovementAnalysisPanel extends StatefulWidget {
  const MovementAnalysisPanel({
    super.key,
    required this.session,
    required this.load,
    this.tileProvider,
    this.summary,
  });
  final ExerciseSession session;
  final Future<MovementAnalysis> Function(bool recalculate) load;
  final TileProvider? tileProvider;
  final Widget? summary;
  @override
  State<MovementAnalysisPanel> createState() => _MovementAnalysisPanelState();
}

class _MovementAnalysisPanelState extends State<MovementAnalysisPanel> {
  late Future<MovementAnalysis> _data;
  final _map = GlobalKey();
  int? _selected;
  @override
  void initState() {
    super.initState();
    _reload(false);
  }

  void _reload(bool force) {
    _selected = null;
    _data = Future.sync(() => widget.load(force));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MovementAnalysis>(
    future: _data,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final data = snapshot.data;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (snapshot.hasError)
            const Text('분석을 불러오지 못했어요. 다시 계산해 주세요.')
          else if (data != null) ...[
            const SizedBox(height: 12),
            ExerciseRoute(
              key: _map,
              points: data.route,
              height: 280,
              tileProvider: widget.tileProvider,
              sections: [
                for (final s in data.sections)
                  if (s.kind == MovementKind.moving) s.speed,
              ],
              selectedPoint: _selected == null
                  ? null
                  : data.sections[_selected!].points.first,
              selectedSection: _selected == null
                  ? null
                  : data.sections[_selected!].speed,
            ),
            const SizedBox(height: 20),
            if (widget.summary != null) ...[
              widget.summary!,
              const SizedBox(height: 32),
            ],
            Text('시간에 따른 속도', style: Theme.of(context).textTheme.titleMedium),
            const Text('km/h · 기록 시작 후 시간 · 빈 구간은 미분류'),
            const SizedBox(height: 8),
            if (data.sections.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('분석할 연속 GPS가 아직 부족해요.'),
              )
            else ...[
              Semantics(
                label: '시간과 속도 그래프. 아래 이전·다음 구간 버튼으로도 선택할 수 있어요.',
                child: GestureDetector(
                  key: const ValueKey('movement-speed-chart'),
                  onTapDown: (details) {
                    final box = context.findRenderObject()! as RenderBox;
                    final span = _span(data, widget.session);
                    final seconds =
                        (details.localPosition.dx / box.size.width).clamp(
                          0.0,
                          1.0,
                        ) *
                        span;
                    final index = data.sections.indexWhere(
                      (s) =>
                          seconds >= _offset(s.start, widget.session) &&
                          seconds <= _offset(s.end, widget.session),
                    );
                    setState(() => _selected = index < 0 ? null : index);
                  },
                  child: SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _SpeedPainter(
                        data,
                        widget.session,
                        _selected,
                        Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('0분'),
                  Text(
                    '${(_span(data, widget.session) / 60).toStringAsFixed(1)}분',
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                children: [
                  for (final label in ['< 4 km/h', '4–7 km/h', '≥ 7 km/h'])
                    Text(
                      label,
                      style: TextStyle(
                        color: speedColor(
                          label.startsWith('<')
                              ? 3
                              : label.startsWith('4')
                              ? 5
                              : 8,
                        ),
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: '이전 구간',
                    onPressed: (_selected ?? 0) <= 0
                        ? null
                        : () => setState(() => _selected = _selected! - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: '다음 구간',
                    onPressed: (_selected ?? -1) >= data.sections.length - 1
                        ? null
                        : () =>
                              setState(() => _selected = (_selected ?? -1) + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  if (_selected != null)
                    TextButton(
                      onPressed: () => Scrollable.ensureVisible(
                        _map.currentContext!,
                        duration: const Duration(milliseconds: 250),
                      ),
                      child: const Text('지도에서 구간 보기'),
                    ),
                ],
              ),
              if (_selected case final index?) ...[
                Text(
                  '${analysisDuration(_offset(data.sections[index].start, widget.session))}–${analysisDuration(_offset(data.sections[index].end, widget.session))} · ${data.sections[index].kind == MovementKind.stopped ? '자동 정지' : '${data.sections[index].kmh.toStringAsFixed(1)} km/h'}',
                ),
                if (data.sections[index].kind == MovementKind.moving)
                  Text(
                    '구간 페이스 ${analysisDuration(data.sections[index].seconds * 1000 / data.sections[index].meters)} /km',
                  ),
              ] else
                const Text('그래프를 누르면 해당 구간과 지도 위치를 볼 수 있어요.'),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                _metric(context, '이동 시간', analysisDuration(data.movingSeconds)),
                _metric(
                  context,
                  '정지 시간',
                  data.rawAvailable
                      ? analysisDuration(data.stoppedSeconds)
                      : '확인 불가',
                ),
                _metric(
                  context,
                  '평균 이동속도',
                  '${data.averageMovingKmh?.toStringAsFixed(1) ?? '—'} km/h',
                ),
                _metric(
                  context,
                  '최고 유효속도',
                  '${data.fastest?.kmh.toStringAsFixed(1) ?? '—'} km/h',
                ),
                _metric(
                  context,
                  '유효 이동거리',
                  '${(data.meters / 1000).toStringAsFixed(2)} km',
                ),
                if (data.unknownSeconds > .5)
                  _metric(
                    context,
                    '미분류 시간',
                    analysisDuration(data.unknownSeconds),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('가장 빠른 구간', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final distance in [100, 500, 1000])
              Builder(
                builder: (context) {
                  final best = data.bests
                      .where((b) => b.meters == distance)
                      .firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${distance == 1000 ? '1km' : '${distance}m'}  ·  ${best == null ? '연속 이동 기록이 더 필요해요' : '${analysisDuration(best.seconds)} · ${analysisDuration(best.paceSeconds)} /km'}',
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            Text(
              data.rawAvailable
                  ? '좌표를 부드럽게 보정한 약 6–12초 구간 평균이에요. 10초 이상 정지가 확인된 구간은 거리에서 제외해요.'
                  : '원본 GPS가 없는 과거 기록은 저장된 경로로 분석해요. 정지 시간은 복원할 수 없어요.',
            ),
            const Text(
              '신호 공백·제외 구간·짧은 불확실 구간은 미분류예요. 수동 일시정지는 기록 시간에 포함되지 않아요. 운동 종류의 속도 범위를 벗어난 이동은 제외하지만 느린 차량을 구별할 수는 없어요.',
            ),
            const Text('재분석 결과는 기록 당시 수치와 다를 수 있어요. 원본과 공유 수치는 그대로 보존해요.'),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: loading ? null : () => setState(() => _reload(true)),
              icon: const Icon(Icons.refresh),
              label: const Text('원본으로 다시 계산'),
            ),
          ),
        ],
      );
    },
  );

  Widget _metric(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

double _offset(DateTime time, ExerciseSession session) =>
    time.difference(session.startedAt).inMicroseconds / 1e6;
double _span(MovementAnalysis data, ExerciseSession session) => math.max(
  1,
  math.max(
    data.sections.isEmpty ? 0 : _offset(data.sections.last.end, session),
    session.endedAt == null
        ? session.elapsedSeconds.toDouble()
        : _offset(session.endedAt!, session),
  ),
);

class _SpeedPainter extends CustomPainter {
  _SpeedPainter(this.data, this.session, this.selected, this.grid);
  final MovementAnalysis data;
  final ExerciseSession session;
  final int? selected;
  final Color grid;
  @override
  void paint(Canvas canvas, Size size) {
    final span = _span(data, session);
    final maxKmh = math.max(8.0, (data.fastest?.kmh ?? 0) * 1.2);
    final paint = Paint()
      ..strokeWidth = 1
      ..color = grid;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      final label = TextPainter(
        text: TextSpan(
          text: (maxKmh * (1 - i / 4)).toStringAsFixed(0),
          style: TextStyle(fontSize: 10, color: grid),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y.clamp(0, size.height - label.height)));
    }
    // Draw windows separately: never interpolate a line over unavailable GPS.
    for (var i = 0; i < data.sections.length; i++) {
      final s = data.sections[i];
      final x1 = _offset(s.start, session) / span * size.width;
      final x2 = _offset(s.end, session) / span * size.width;
      final y = (size.height - 3) * (1 - s.kmh / maxKmh);
      if (i == selected) {
        canvas.drawRect(
          Rect.fromLTRB(x1, 0, x2, size.height),
          Paint()..color = speedColor(s.kmh).withValues(alpha: .18),
        );
      }
      canvas.drawLine(
        Offset(x1, y),
        Offset(x2, y),
        Paint()
          ..strokeWidth = i == selected ? 5 : 3
          ..color = speedColor(s.kmh),
      );
    }
  }

  @override
  bool shouldRepaint(_SpeedPainter old) =>
      old.data != data ||
      old.selected != selected ||
      old.grid != grid ||
      old.session != session;
}
