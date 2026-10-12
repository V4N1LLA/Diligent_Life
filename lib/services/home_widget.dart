import 'package:flutter/services.dart';

import '../models/growth.dart';

/// Disposable device-local presentation cache; deliberately excluded from backup.
class HomeWidget {
  static const channel = MethodChannel('diligent_life/home_widget');
  static Future<void> refresh() async {
    try {
      await channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Other platforms have no home widget.
    } on PlatformException {
      // Launcher availability never affects app lifecycle.
    }
  }

  static Future<void> publish(GrowthSnapshot snapshot, {String? title}) async {
    try {
      await channel.invokeMethod<void>('publish', {
        'level': snapshot.level,
        'title': title ?? snapshot.title,
        'questTarget': dailyQuests(const ActivityDay('')).first.target.toInt(),
      });
    } on MissingPluginException {
      // Non-Android platforms have no home widget.
    } on PlatformException {
      // Widget errors never affect persistence or progression.
    }
  }
}
