// Ngôn ngữ app: Tiếng Việt / English. Chuỗi hiển thị viết cặp `tr('tiếng Việt', 'English')` ngay tại chỗ dùng.
// Đổi ngôn ngữ thì RcApp dựng lại toàn bộ cây widget, các màn đang mở giữ nguyên.
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLang {
  vi('VN', 'Tiếng Việt'),
  en('EN', 'English');

  const AppLang(this.short, this.nativeName);

  /// Nhãn ngắn trên nút chọn ngôn ngữ
  final String short;

  /// Tên ngôn ngữ viết bằng chính ngôn ngữ đó
  final String nativeName;

  Locale get locale => Locale(name);
}

/// Chuỗi theo ngôn ngữ đang chọn
String tr(String vi, String en) => LangController.instance.lang == AppLang.en ? en : vi;

/// Ngôn ngữ đang chọn — lưu lại, áp dụng ngay. Mặc định: Tiếng Việt.
/// Một bản dùng chung cả app vì `tr()` được gọi cả trong model (thông báo lỗi, nhãn enum).
class LangController extends ChangeNotifier {
  LangController._();

  static final instance = LangController._();
  static const _key = 'app_lang';

  AppLang _lang = AppLang.vi;
  AppLang get lang => _lang;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lang = AppLang.values.asNameMap()[prefs.getString(_key)] ?? AppLang.vi;
      notifyListeners();
    } catch (_) {
      // Không đọc được thì giữ mặc định
    }
  }

  Future<void> setLang(AppLang l) async {
    if (l == _lang) return;
    _lang = l;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, l.name);
    } catch (_) {}
  }
}
