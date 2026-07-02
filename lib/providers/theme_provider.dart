import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// テーマ設定（ライト / ダーク=夜の広場 / システム追従）。
/// SharedPreferencesに永続化される。
class ThemeController extends Notifier<ThemeMode> {
  static const _prefKey = 'theme_mode_v1';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_prefKey);
    if (idx != null && idx >= 0 && idx < ThemeMode.values.length) {
      state = ThemeMode.values[idx];
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, mode.index);
  }
}

final themeProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
