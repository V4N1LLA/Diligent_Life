import 'package:flutter/material.dart';

import '../models/character.dart';

/// Same local vector artwork on screen and in the exported card.
void paintProfileAvatar(
  Canvas canvas,
  Rect bounds,
  CharacterSnapshot data,
  Brightness brightness,
) {
  final purple = data.selection(CosmeticSlot.accent) == 'accent.purple.v1';
  final dark = brightness == Brightness.dark;
  final accent = purple ? const Color(0xff947ab8) : const Color(0xff6d9482);
  final dawn = data.selection(CosmeticSlot.background) == 'background.dawn.v1';
  canvas.save();
  canvas.translate(bounds.left, bounds.top);
  canvas.scale(bounds.width / 160, bounds.height / 160);
  final background = dawn
      ? (dark ? const Color(0xff3b304a) : const Color(0xffeee5f4))
      : (dark ? const Color(0xff263c34) : const Color(0xffe5eee7));
  canvas.drawCircle(const Offset(80, 80), 74, Paint()..color = background);
  final frame = data.selection(CosmeticSlot.frame);
  if (frame != 'frame.none.v1') {
    canvas.drawCircle(
      const Offset(80, 80),
      76,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (frame == 'frame.walking.v1') {
      for (final x in [65.0, 80.0, 95.0]) {
        canvas.drawCircle(Offset(x, 151), 3, Paint()..color = accent);
      }
    }
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(42, 88, 76, 48),
      const Radius.circular(25),
    ),
    Paint()..color = accent,
  );
  canvas.drawCircle(
    const Offset(80, 62),
    25,
    Paint()..color = dark ? const Color(0xffe3dfd7) : const Color(0xfffbfaf7),
  );
  // A quiet human silhouette, not a pet or an exaggerated game character.
  canvas.drawArc(
    const Rect.fromLTWH(61, 41, 38, 36),
    3.14,
    3.14,
    true,
    Paint()..color = dark ? const Color(0xff37473e) : const Color(0xff3f554a),
  );
  final emblem = data.selection(CosmeticSlot.emblem);
  if (emblem != 'emblem.none.v1') {
    canvas.drawCircle(
      const Offset(126, 123),
      19,
      Paint()..color = dark ? const Color(0xffdfd0ed) : const Color(0xff75609a),
    );
    final p = Path();
    if (emblem == 'emblem.explorer.v1') {
      p
        ..moveTo(126, 110)
        ..lineTo(134, 131)
        ..lineTo(126, 126)
        ..lineTo(118, 131)
        ..close();
    } else {
      p
        ..moveTo(116, 123)
        ..lineTo(123, 130)
        ..lineTo(136, 116);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = dark ? const Color(0xff38264f) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }
  canvas.restore();
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.data, this.size = 144});
  final CharacterSnapshot data;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '나의 아바타, ${[for (final slot in CosmeticSlot.values) cosmetics.firstWhere((c) => c.id == data.selection(slot)).name].join(', ')}',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AvatarPainter(data, Theme.of(context).brightness),
      ),
    ),
  );
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.data, this.brightness);
  final CharacterSnapshot data;
  final Brightness brightness;
  @override
  void paint(Canvas canvas, Size size) =>
      paintProfileAvatar(canvas, Offset.zero & size, data, brightness);
  @override
  bool shouldRepaint(_AvatarPainter old) =>
      brightness != old.brightness ||
      CosmeticSlot.values.any(
        (s) => data.selection(s) != old.data.selection(s),
      );
}
