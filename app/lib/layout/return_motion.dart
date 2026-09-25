// Tính vị trí cần gạt khi tự về (H3b) — thuần, không phụ thuộc widget.
import '../models/control_layout.dart';

abstract final class ReturnMotion {
  /// Vị trí sau `elapsedMs` kể từ lúc thả tay ở `from` (%)
  static double valueAt(ReturnConfig cfg, double from, int elapsedMs) {
    if (!cfg.returnsFrom(from)) return from;
    if (elapsedMs < cfg.delayMs) return from;
    final target = cfg.targetPct.clamp(-100.0, 100.0).toDouble();
    if (cfg.durationMs <= 0) return target;
    final t = ((elapsedMs - cfg.delayMs) / cfg.durationMs).clamp(0.0, 1.0);
    final k = cfg.curve == ReturnCurve.easeOut ? 1 - (1 - t) * (1 - t) : t;
    return from + (target - from) * k;
  }

  /// Tổng thời gian tới khi đứng yên
  static int totalMs(ReturnConfig cfg) => cfg.delayMs + cfg.durationMs;

  /// Vị trí khi vào màn Lái: Giữ vị trí + Nhớ vị trí → giá trị đã lưu, còn lại → `targetPct`
  static double initial(ReturnConfig cfg, double? saved) =>
      cfg.mode == ReturnMode.hold && cfg.rememberOnExit && saved != null ? saved : cfg.targetPct;

  /// Vị trí khi thoát màn / vào sửa bố cục / app xuống nền.
  /// Kênh ga cấu hình Giữ vị trí bắt buộc về Center (0%).
  static double onExit(ReturnConfig cfg, {required bool isThrottle}) =>
      isThrottle && cfg.mode == ReturnMode.hold ? 0 : cfg.targetPct;

  /// Vị trí nghỉ (%) của kênh `ch` trên bố cục: cần gạt → `onExit` của trục gán kênh đó,
  /// phần tử khác hoặc chưa có phần tử → 0. Dùng để kiểm "ga đã thả" trước khi sửa bố cục (H5).
  static double restPct(ControlLayout layout, int ch, {required bool isThrottle}) {
    final it = layout.itemForChannel(ch);
    if (it == null || !it.kind.isStick) return 0;
    final cfg = (it.kind == ItemKind.stick2D && it.channelY == ch ? it.returnCfgY : it.returnCfg) ?? ReturnConfig();
    return onExit(cfg, isThrottle: isThrottle);
  }

  /// Vùng chết: |v| < dz → 0, phần còn lại co giãn lại về 0…100
  static double deadzone(double v, double dzPct) {
    if (dzPct <= 0) return v;
    final a = v.abs();
    if (a < dzPct) return 0;
    return v.sign * (a - dzPct) / (100 - dzPct) * 100;
  }
}
