import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<Uint8List> achievementShareImage(
  String headline,
  String detail, {
  required Brightness brightness,
  bool portrait = false,
}) async {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xff10251b) : const Color(0xfff7f8f4);
  final foreground = dark ? const Color(0xffe1eee5) : const Color(0xff263c33);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(background, BlendMode.src);
  void label(String text, double y, double size) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: foreground,
          fontSize: size,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 600);
    p.paint(canvas, Offset(60, y));
    p.dispose();
  }

  label('Diligent Life', 60, 28);
  label('나의 움직임이 쌓이는 중', 150, 25);
  label(headline, 230, 48);
  label(detail, 380, 27);
  label('나만의 속도로, 한 걸음씩', portrait ? 800 : 620, 22);
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, portrait ? 900 : 720);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
