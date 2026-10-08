import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/activity_calendar.dart';
import '../widgets/activity_style.dart';

/// Allowlisted monthly totals only; no routes, locations, weight or daily data.
List<String> monthlyShareLabels(CalendarMonth month) => [
  '${month.month.year}년 ${month.month.month}월',
  '${stepLabel(month.steps)} 걸음',
  '${(month.meters / 1000).toStringAsFixed(1)} km 운동',
  '${month.workouts}회 운동',
  '${month.regions}개 지역 발견',
  if (month.highlight != null) month.highlight!,
];

Future<Uint8List> monthlyShareImage(
  CalendarMonth month,
  Brightness brightness,
) async {
  final dark = brightness == Brightness.dark;
  final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
  canvas.drawColor(
    dark ? const Color(0xff17251e) : const Color(0xfff7f8f4),
    BlendMode.src,
  );
  void text(String label, double y, double size, {Color? color}) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color:
              color ??
              (dark ? const Color(0xffe1eee5) : const Color(0xff263c33)),
          fontSize: size,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(minWidth: 600, maxWidth: 600);
    painter.paint(canvas, Offset(60, y));
    painter.dispose();
  }

  final labels = monthlyShareLabels(month);
  text('Diligent Life', 64, 24);
  text(labels[0], 150, 32);
  text('이번 달의 움직임', 212, 26);
  text(labels[1], 306, 48);
  for (var i = 2; i < labels.length; i++) {
    text(labels[i], 410 + (i - 2) * 72, i == 5 ? 24 : 30);
  }
  text('나만의 속도로 쌓아온 기록', 806, 23);
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 900);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
