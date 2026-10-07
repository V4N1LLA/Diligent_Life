import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'achievement_share.dart';

// Count-only card: never render a map, cell ID, route, address or timestamp.
Future<Uint8List> explorationShareImage({
  required int total,
  required int discovered,
  required bool workout,
  required Brightness brightness,
}) => achievementShareImage(
  '나의 발자취가 넓어졌어요',
  '${workout ? '이번 운동' : '이번 달'} 새 지역 $discovered곳\n총 $total개 지역 탐험',
  brightness: brightness,
);
