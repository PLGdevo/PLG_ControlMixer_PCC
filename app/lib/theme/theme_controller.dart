import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tối / Sáng / Theo hệ thống — lưu lại, áp dụng ngay (A3). Mặc định: Tối.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = ThemeMode.values.asNameMap()[prefs.getString(_key)] ?? ThemeMode.dark;
      notifyListeners();
    } catch (_) {
      // Không đọc được thì giữ mặc định
    }
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, m.name);
    } catch (_) {}
  }
}
