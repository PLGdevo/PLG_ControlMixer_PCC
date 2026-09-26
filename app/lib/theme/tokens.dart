// Token màu, bo góc, khoảng cách — theo mẫu Figma "Digital Agency (Dark Theme)".
// Màn hình và widget chỉ lấy màu qua `context.tokens`, không viết mã màu trực tiếp.
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/lang.dart';

/// Dải Green gốc (màu thương hiệu)
abstract final class Green {
  static const g50 = Color(0xFF9EFF00);
  static const g60 = Color(0xFFB1FF33);
  static const g70 = Color(0xFFC5FF66);
  static const g80 = Color(0xFFD8FF99);
  static const g90 = Color(0xFFECFFCC);
  static const g95 = Color(0xFFF5FFE5);
  static const g97 = Color(0xFFF9FFF0);
  static const g99 = Color(0xFFFDFFFA);
}

/// Dải Grey gốc
abstract final class Grey {
  static const g10 = Color(0xFF191919);
  static const g15 = Color(0xFF262626);
  static const g20 = Color(0xFF333333);
  static const g30 = Color(0xFF4C4C4D);
  static const g35 = Color(0xFF59595A);
  static const g40 = Color(0xFF656567);
  static const g60 = Color(0xFF98989A);
  static const g90 = Color(0xFFE6E6E6);
}

abstract final class Radii {
  static const card = 16.0;
  static const field = 12.0;
  static const pill = 999.0;
}

/// Lưới khoảng cách bước 4
abstract final class Gap {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.textBody,
    required this.textMuted,
    required this.disabled,
    required this.accent,
    required this.accentFill,
    required this.accentFillPressed,
    required this.onAccentFill,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.ok,
    required this.warn,
    required this.bad,
    required this.idle,
  });

  final Color bg, surface, surface2, line;
  final Color text, textBody, textMuted, disabled;
  final Color accent, accentFill, accentFillPressed, onAccentFill;
  final Color accentContainer, onAccentContainer;
  final Color ok, warn, bad, idle;

  static const dark = AppTokens(
    bg: Grey.g10,
    surface: Grey.g15,
    surface2: Grey.g20,
    line: Grey.g20,
    text: Colors.white,
    textBody: Grey.g90,
    textMuted: Grey.g60,
    disabled: Grey.g35,
    accent: Green.g50,
    accentFill: Green.g50,
    accentFillPressed: Green.g60,
    onAccentFill: Grey.g10,
    accentContainer: Color(0x1F9EFF00), // Green 50 @ 12%
    onAccentContainer: Green.g70,
    ok: Color(0xFF4CAF50),
    warn: Color(0xFFFFC107),
    bad: Color(0xFFF44336),
    idle: Grey.g60,
  );

  static const light = AppTokens(
    bg: Green.g99,
    surface: Colors.white,
    surface2: Green.g97,
    line: Grey.g90,
    text: Grey.g10,
    textBody: Grey.g30,
    textMuted: Grey.g35,
    disabled: Grey.g60,
    // Green 50 trên nền trắng chỉ ~1.3:1 → chữ/icon nhấn dùng bản tối hơn (~6.8:1)
    accent: Color(0xFF3D6600),
    accentFill: Green.g50,
    accentFillPressed: Green.g60,
    onAccentFill: Grey.g10,
    accentContainer: Green.g90,
    onAccentContainer: Grey.g10,
    ok: Color(0xFF2E7D32),
    warn: Color(0xFFB26A00),
    bad: Color(0xFFC62828),
    idle: Grey.g35,
  );

  /// Bộ token theo màu chủ đạo. Xanh chanh dùng đúng bảng gốc; màu khác suy ra từ `fill` và `deep`.
  static AppTokens of(AccentColor a, Brightness b) {
    final base = b == Brightness.dark ? dark : light;
    if (a == AccentColor.lime) return base;
    Color mix(Color x, Color y, double t) => Color.lerp(x, y, t)!;
    final fill = a.fill;
    // Chữ trên nền nút: chọn đen hoặc trắng, bên nào tương phản hơn
    double contrast(Color x, Color y) {
      final lx = x.computeLuminance(), ly = y.computeLuminance();
      return (max(lx, ly) + 0.05) / (min(lx, ly) + 0.05);
    }

    final onFill = contrast(fill, Grey.g10) >= contrast(fill, Colors.white) ? Grey.g10 : Colors.white;
    final dark_ = b == Brightness.dark;
    return AppTokens(
      bg: dark_ ? base.bg : mix(Colors.white, fill, 0.02),
      surface: base.surface,
      surface2: dark_ ? base.surface2 : mix(Colors.white, fill, 0.06),
      line: base.line,
      text: base.text,
      textBody: base.textBody,
      textMuted: base.textMuted,
      disabled: base.disabled,
      accent: dark_ ? fill : a.deep,
      accentFill: fill,
      accentFillPressed: mix(fill, Colors.white, 0.2),
      onAccentFill: onFill,
      accentContainer: dark_ ? fill.withAlpha(0x1F) : mix(Colors.white, fill, 0.2),
      onAccentContainer: dark_ ? mix(fill, Colors.white, 0.4) : Grey.g10,
      ok: base.ok,
      warn: base.warn,
      bad: base.bad,
      idle: base.idle,
    );
  }

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      line: l(line, other.line),
      text: l(text, other.text),
      textBody: l(textBody, other.textBody),
      textMuted: l(textMuted, other.textMuted),
      disabled: l(disabled, other.disabled),
      accent: l(accent, other.accent),
      accentFill: l(accentFill, other.accentFill),
      accentFillPressed: l(accentFillPressed, other.accentFillPressed),
      onAccentFill: l(onAccentFill, other.onAccentFill),
      accentContainer: l(accentContainer, other.accentContainer),
      onAccentContainer: l(onAccentContainer, other.onAccentContainer),
      ok: l(ok, other.ok),
      warn: l(warn, other.warn),
      bad: l(bad, other.bad),
      idle: l(idle, other.idle),
    );
  }
}

/// Màu nhấn: màu chủ đạo của app và màu riêng của từng phần tử trên màn Lái.
/// Đỏ / vàng chỉ dùng cho phần tử (vd nút còi đỏ), không làm màu chủ đạo để không lẫn với báo lỗi (bad) / cảnh báo (warn).
enum AccentColor {
  lime('Xanh chanh', 'Lime', Green.g50, Color(0xFF3D6600)),
  blue('Xanh dương', 'Blue', Color(0xFF4DA3FF), Color(0xFF0B5CAD)),
  teal('Xanh ngọc', 'Teal', Color(0xFF1DE9B6), Color(0xFF00695C)),
  purple('Tím', 'Purple', Color(0xFFB388FF), Color(0xFF6A3FC4)),
  pink('Hồng', 'Pink', Color(0xFFFF6FB5), Color(0xFFB0206B)),
  orange('Cam', 'Orange', Color(0xFFFF9A1F), Color(0xFFA34E00)),
  red('Đỏ', 'Red', Color(0xFFFF5A5F), Color(0xFFB3261E), forApp: false),
  yellow('Vàng', 'Yellow', Color(0xFFFFD60A), Color(0xFF7A5C00), forApp: false);

  const AccentColor(this._vi, this._en, this.fill, this.deep, {this.forApp = true});
  final String _vi, _en;

  /// Chọn được làm màu chủ đạo của app (Cài đặt); màu còn lại chỉ dùng cho phần tử
  final bool forApp;

  static List<AccentColor> get appChoices => values.where((a) => a.forApp).toList();

  /// Nền nút / điểm nhấn; đủ sáng để đọc được trên nền tối (≥ 4.5:1)
  final Color fill;

  /// Chữ / icon nhấn trên nền sáng (≥ 4.5:1 trên nền trắng)
  final Color deep;

  String get label => tr(_vi, _en);
}

extension TokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
}
