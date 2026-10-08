import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/character.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/activity_style.dart';

/// Explicit allowlist. No coordinates, weight, dates, internal IDs or raw data.
List<String> profileShareLabels(CharacterSnapshot data) => [
  'Lv. ${data.growth.level}',
  data.growth.title,
  '${stepLabel(data.steps)}걸음',
  '${(data.meters / 1000).toStringAsFixed(1)} km 운동',
  '${data.regions}개 지역 탐험',
];

Future<Uint8List> profileShareImage(
  CharacterSnapshot data,
  Brightness brightness,
) async {
  final dark = brightness == Brightness.dark;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final ink = dark ? const Color(0xffe1eee5) : const Color(0xff263c33);
  canvas.drawColor(
    dark ? const Color(0xff17251e) : const Color(0xfff7f8f4),
    BlendMode.src,
  );
  void text(String value, double y, double size) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: ink,
          fontSize: size,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(minWidth: 600, maxWidth: 600);
    p.paint(canvas, Offset(60, y));
    p.dispose();
  }

  text('Diligent Life · 나의 프로필', 42, 23);
  paintProfileAvatar(
    canvas,
    const Rect.fromLTWH(260, 94, 200, 200),
    data,
    brightness,
  );
  final labels = profileShareLabels(data);
  text(labels[0], 318, 46);
  text(labels[1], 380, 28);
  for (var i = 2; i < labels.length; i++) {
    text(labels[i], 450 + (i - 2) * 50, 27);
  }
  text('나만의 속도로, 한 걸음씩', 650, 21);
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 720);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
