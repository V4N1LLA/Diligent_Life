import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/exercise_session.dart';
import '../utils/gps.dart';
import '../utils/dates.dart';

Future<Uint8List> exerciseShareImage(
  ExerciseSession session,
  List<RoutePoint> route, {
  required bool hideEndpoints,
  ui.Image? mapImage,
}) async {
  final points = hideEndpoints ? privateRoute(route) : route;
  if (points.isNotEmpty && mapImage == null) {
    throw StateError('A loaded private map is required');
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xfff7f8f4), BlendMode.src);
  void label(String value, double y, double size, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: const Color(0xff263c33),
          fontSize: size,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 608);
    painter.paint(canvas, Offset(56, y));
    painter.dispose();
  }

  label('Diligent Life', 40, 27, bold: true);
  label(
    '${dateKey(session.startedAt.toLocal())} · ${session.type.label}',
    84,
    22,
  );
  label(
    '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
    130,
    64,
    bold: true,
  );
  const mapRect = Rect.fromLTWH(40, 240, 640, 370);
  if (points.isNotEmpty) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(mapRect, const Radius.circular(24)),
    );
    canvas.drawImageRect(
      mapImage!,
      Rect.fromLTWH(
        0,
        0,
        mapImage.width.toDouble(),
        mapImage.height.toDouble(),
      ),
      mapRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  } else {
    canvas.drawRRect(
      RRect.fromRectAndRadius(mapRect, const Radius.circular(24)),
      Paint()..color = const Color(0xffe5ece5),
    );
    label(hideEndpoints ? '위치 보호를 위해 경로를 숨겼어요' : '저장된 경로가 없어요', 405, 24);
  }
  void metric(String name, String value, double x, double y) {
    canvas.save();
    canvas.translate(x, 0);
    label(name, y, 19);
    label(value, y + 31, 29, bold: true);
    canvas.restore();
  }

  metric('총 기록 시간', elapsedLabel(session.elapsedSeconds), 0, 636);
  metric('평균 페이스', paceLabel(session.paceSeconds), 330, 636);
  metric(
    '예상 소모',
    session.calories == null ? '— kcal' : '약 ${session.calories!.round()} kcal',
    0,
    731,
  );
  metric(
    '평균 속도',
    session.elapsedSeconds == 0
        ? '— km/h'
        : '${(session.distanceMeters / session.elapsedSeconds * 3.6).toStringAsFixed(1)} km/h',
    330,
    731,
  );
  label(
    hideEndpoints ? '시작·도착 주변 200m 숨김 · 표시는 공개 구간' : '전체 경로 · 시작과 도착 표시',
    836,
    19,
  );
  label('오늘의 움직임이 나만의 포트폴리오로', 871, 22, bold: true);
  label('기록 거리 · 시간·kcal는 정지 포함 / 수동 일시정지 제외', 907, 14);
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 930);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> shareExercise(
  ExerciseSession session,
  List<RoutePoint> points, {
  required bool hideEndpoints,
  required Rect origin,
  ui.Image? mapImage,
}) async {
  final bytes = await exerciseShareImage(
    session,
    points,
    hideEndpoints: hideEndpoints,
    mapImage: mapImage,
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png')],
      fileNameOverrides: ['diligent-life-${session.id}.png'],
      title: 'Diligent Life 운동 기록',
      sharePositionOrigin: origin,
    ),
  );
}
