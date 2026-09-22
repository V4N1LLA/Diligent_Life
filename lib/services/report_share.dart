import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/activity_report.dart';

// A location-free card uses the same report calculations as the detail screen.
Future<Uint8List> reportShareImage(ActivityReport report) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xfff7f8f4), BlendMode.src);
  double y = 48;
  void text(String value, double size, {bool bold = false, double gap = 20}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: const Color(0xff243e34),
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 788);
    painter.paint(canvas, Offset(56, y));
    y += painter.height + gap;
    painter.dispose();
  }

  text('Diligent Life · ${report.window.title}', 25);
  text(report.window.dates, 23, gap: 10);
  text('비교 ${report.window.previousDates}', 20, gap: 24);
  text(report.insight, 36, bold: true, gap: 24);
  if (report.window.partial) text('진행 중 · 이전 기간의 같은 경과 일수와 비교', 20, gap: 18);
  final a = report.current, b = report.previous;
  text('이전 기간 → 이번 기간', 23, bold: true);
  text(
    '기록 거리  ${(b.meters / 1000).toStringAsFixed(2)} → ${(a.meters / 1000).toStringAsFixed(2)} km  (${report.delta(a.meters, b.meters)})',
    25,
  );
  text(
    '총 기록 시간  ${(b.seconds / 60).toStringAsFixed(0)} → ${(a.seconds / 60).toStringAsFixed(0)}분  (${report.delta(a.seconds.toDouble(), b.seconds.toDouble())})',
    25,
  );
  text(
    '운동  ${b.count} → ${a.count}회  (${report.delta(a.count.toDouble(), b.count.toDouble())})',
    25,
  );
  final complete = a.calorieCount == a.count && b.calorieCount == b.count;
  text(
    '예상 kcal  ${b.calories?.round() ?? '—'} → ${a.calories?.round() ?? '—'}  (${report.delta(a.calories ?? 0, b.calories ?? 0, available: complete)})',
    25,
  );
  text(
    '정지 포함 총 시간 기준 kcal: 이전 ${b.calorieCount}/${b.count}회 · 이번 ${a.calorieCount}/${a.count}회',
    19,
  );
  final change = report.weightChange;
  text(
    change == null
        ? '몸무게 변화 · 데이터 부족'
        : '몸무게 변화  ${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg · ${report.weights.length}회 측정',
    25,
  );
  text('운동량과 몸무게는 같은 기간의 추세 비교이며 인과관계를 뜻하지 않아요.', 20);
  for (final speed in report.speeds) {
    text(
      '${speed.type.label} 평균 이동속도\n${speed.previous?.toStringAsFixed(1) ?? '데이터 부족'} → ${speed.current?.toStringAsFixed(1) ?? '데이터 부족'} km/h',
      23,
    );
  }
  // Position footer after content; dynamic height prevents extreme totals or
  // larger fallback fonts from clipping a valid card.
  final height = (y + 110).ceil().clamp(1200, 4000);
  y = height - 86;
  text('완료 GPS 기록 · 거리·kcal는 추정치\n경로 위치·요일·시각 등 생활 패턴 미포함', 19, gap: 0);
  final picture = recorder.endRecording();
  final image = await picture.toImage(900, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG encoding failed');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
