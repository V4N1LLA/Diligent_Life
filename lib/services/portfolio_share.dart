import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/portfolio_repository.dart';
import '../utils/dates.dart';
import '../utils/gps.dart';

Future<Uint8List> portfolioShareImage(PortfolioData data, String title) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const ink = Color(0xff243e34), sage = Color(0xff527d6b);
  canvas.drawColor(const Color(0xfff7f8f4), BlendMode.src);
  void text(
    String value,
    double x,
    double y,
    double size, {
    bool bold = false,
    double width = 788,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: ink,
          fontSize: size,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    painter.paint(canvas, Offset(x, y));
    painter.dispose();
  }

  text('Diligent Life', 56, 46, 24);
  text(title, 56, 100, 42, bold: true);
  text(
    '${data.periodStart == null ? '첫 기록' : dateKey(data.periodStart!)} — ${dateKey(data.periodEnd!)}',
    56,
    164,
    22,
  );
  text('차곡차곡 쌓인 나의 움직임', 56, 218, 26);
  text(
    '${(data.summary.meters / 1000).toStringAsFixed(2)} km',
    56,
    258,
    68,
    bold: true,
  );
  void metric(String label, String value, double x, double y) {
    text(label, x, y, 21, width: 370);
    text(value, x, y + 34, 31, bold: true, width: 370);
  }

  metric('운동 횟수', '${data.summary.count}회', 56, 366);
  metric('총 운동 시간', elapsedLabel(data.summary.seconds), 466, 366);
  metric(
    '예상 소모 칼로리',
    data.summary.calories == null
        ? '— kcal'
        : '약 ${data.summary.calories!.round()} kcal',
    56,
    474,
  );
  final change = data.weightChange;
  metric(
    '몸무게 변화',
    change == null
        ? '측정 기록이 더 필요해요'
        : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
    466,
    474,
  );
  text('월별 움직임 · 거리', 56, 590, 25, bold: true);
  final months = data.months.reversed.toList();
  final displayed = months.length > 12
      ? months.sublist(months.length - 12)
      : months;
  final max = displayed.fold<double>(
    1,
    (v, m) => m.summary.meters > v ? m.summary.meters : v,
  );
  final step = 788 / (displayed.isEmpty ? 1 : displayed.length);
  for (var i = 0; i < displayed.length; i++) {
    final m = displayed[i];
    final h = 150 * m.summary.meters / max;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(56 + step * i + 5, 810 - h, step - 10, h < 2 ? 2 : h),
        const Radius.circular(3),
      ),
      Paint()..color = sage,
    );
    text('${m.month.month}월', 56 + step * i + 5, 830, 17, width: step);
  }
  text('몸무게의 흐름 · 실제 측정일만', 56, 895, 23, bold: true);
  final weights = data.weights;
  if (weights.isEmpty) {
    text('아직 측정한 기록이 없어요.', 56, 943, 22);
  } else {
    final min =
        weights.map((r) => r.weightKg!).reduce((a, b) => a < b ? a : b) - 1;
    final max =
        weights.map((r) => r.weightKg!).reduce((a, b) => a > b ? a : b) + 1;
    double day(String date) =>
        DateTime.parse('${date}T00:00:00Z').millisecondsSinceEpoch /
        Duration.millisecondsPerDay;
    final first = day(weights.first.date), last = day(weights.last.date);
    Offset? previous;
    double? previousDay;
    for (final r in weights) {
      final d = day(r.date);
      final point = Offset(
        last == first ? 450 : 56 + (d - first) / (last - first) * 788,
        1030 - (r.weightKg! - min) / (max - min) * 90,
      );
      if (previous != null && d - previousDay! <= 1) {
        canvas.drawLine(
          previous,
          point,
          Paint()
            ..color = sage
            ..strokeWidth = 3,
        );
      }
      canvas.drawCircle(point, 4, Paint()..color = sage);
      previous = point;
      previousDay = d;
    }
    text(
      '${weights.first.weightKg!.toStringAsFixed(1)} → ${weights.last.weightKg!.toStringAsFixed(1)} kg · ${weights.length}회 측정',
      56,
      1048,
      20,
    );
  }
  text('완료한 GPS 운동 · 거리·kcal는 추정치', 56, 1110, 19);
  text(
    'kcal 계산 가능 ${data.summary.calorieCount}/${data.summary.count}회 · 경로 위치 미포함',
    56,
    1143,
    19,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, 1200);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
