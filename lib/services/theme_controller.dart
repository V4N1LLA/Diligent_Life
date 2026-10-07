import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString('themeMode'),
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> select(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name);
    value = mode;
  }
}

final themeController = ThemeController();
