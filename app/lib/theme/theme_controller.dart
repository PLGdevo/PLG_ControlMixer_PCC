import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// Tối / Sáng / Theo hệ thống và màu chủ đạo — lưu lại, áp dụng ngay (A3). Mặc định: Tối, xanh chanh.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  static const _accentKey = 'theme_accent';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  AccentColor _accent = AccentColor.lime;
  AccentColor get accent => _accent;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = ThemeMode.values.asNameMap()[prefs.getString(_key)] ?? ThemeMode.dark;
      final a = AccentColor.values.asNameMap()[prefs.getString(_accentKey)];
      _accent = a != null && a.forApp ? a : AccentColor.lime;
      notifyListeners();
    } catch (_) {
      // Không đọc được thì giữ mặc định
    }
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    await _put(_key, m.name);
  }

  Future<void> setAccent(AccentColor a) async {
    if (a == _accent) return;
    _accent = a;
    notifyListeners();
    await _put(_accentKey, a.name);
  }

  Future<void> _put(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }
}
