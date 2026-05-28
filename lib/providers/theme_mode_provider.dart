import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier({Box<dynamic>? preferencesBox})
    : _preferencesBox = preferencesBox ?? Hive.box<dynamic>('uiPreferences'),
      super(_read(preferencesBox ?? Hive.box<dynamic>('uiPreferences')));

  static const _themeModeKey = 'themeMode';
  final Box<dynamic> _preferencesBox;

  static ThemeMode _read(Box<dynamic> box) {
    final value = box.get(_themeModeKey) as String?;
    return value == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) mode = ThemeMode.dark;
    state = mode;
    await _preferencesBox.put(
      _themeModeKey,
      mode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  Future<void> toggle() {
    return setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
