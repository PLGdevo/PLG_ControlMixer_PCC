// Phép tính thuần trên lưới bố cục (H1/H2/H5): bám ô, chồng lấn, giới hạn, đường gióng.
import 'dart:math';

import '../l10n/lang.dart';
import '../models/control_layout.dart';

class GridRect {
  final int x, y, w, h;
  const GridRect(this.x, this.y, this.w, this.h);

  factory GridRect.of(ControlItem i) => GridRect(i.x, i.y, i.w, i.h);

  int get right => x + w;
  int get bottom => y + h;

  bool overlaps(GridRect o) => x < o.right && o.x < right && y < o.bottom && o.y < bottom;

  bool inside(int cols, int rows) => x >= 0 && y >= 0 && right <= cols && bottom <= rows;

  @override
  bool operator ==(Object other) =>
      other is GridRect && other.x == x && other.y == y && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'GridRect($x,$y ${w}x$h)';
}

abstract final class LayoutGrid {
  /// Toạ độ pixel → ô gần nhất
  static int snap(double px, double cell) => cell <= 0 ? 0 : (px / cell).round();

  /// Vị trí `r` của phần tử `id` có hợp lệ không: trong lưới và không đè phần tử khác
  static bool fits(ControlLayout l, String id, GridRect r) {
    if (!r.inside(l.cols, l.rows)) return false;
    return !collides(l, id, r);
  }

  static bool collides(ControlLayout l, String id, GridRect r) =>
      l.items.any((o) => o.id != id && GridRect.of(o).overlaps(r));

  /// Kẹp kích thước vào giới hạn của loại và vào trong lưới
  static GridRect clampSize(GridRect r, SizeLimits lim, int cols, int rows) {
    final w = r.w.clamp(lim.minW, min(lim.maxW, cols)).toInt();
    final h = r.h.clamp(lim.minH, min(lim.maxH, rows)).toInt();
    final x = r.x.clamp(0, cols - w).toInt();
    final y = r.y.clamp(0, rows - h).toInt();
    return GridRect(x, y, w, h);
  }

  /// Tìm chỗ trống đầu tiên (quét từ trên xuống, trái sang phải)
  static GridRect? findFreeSpot(ControlLayout l, int w, int h, {String id = ''}) {
    for (var y = 0; y + h <= l.rows; y++) {
      for (var x = 0; x + w <= l.cols; x++) {
        final r = GridRect(x, y, w, h);
        if (!collides(l, id, r)) return r;
      }
    }
    return null;
  }

  /// Đường gióng: cột/hàng mà cạnh của `r` trùng với cạnh phần tử khác
  static ({Set<int> xs, Set<int> ys}) guides(ControlLayout l, String id, GridRect r) {
    final xs = <int>{}, ys = <int>{};
    for (final o in l.items) {
      if (o.id == id) continue;
      final g = GridRect.of(o);
      for (final a in [r.x, r.right]) {
        if (a == g.x || a == g.right) xs.add(a);
      }
      for (final a in [r.y, r.bottom]) {
        if (a == g.y || a == g.bottom) ys.add(a);
      }
    }
    return (xs: xs, ys: ys);
  }

  /// Kiểm tra trước khi lưu (H5, I3, V). `throttleInputs` / `steerInputs`: Input đang điều khiển
  /// kênh Ga / Lái qua luật mix; bố cục phải có phần tử cho ít nhất một Input mỗi loại.
  /// Trả về lỗi đầu tiên hoặc null.
  static String? validate(ControlLayout l,
      {Set<String> throttleInputs = const {}, Set<String> steerInputs = const {}}) {
    if (l.name.trim().isEmpty) return tr('Tên bố cục không được trống', 'Layout name cannot be empty');
    final seen = <String>{};
    for (final i in l.items) {
      final r = GridRect.of(i);
      if (!r.inside(l.cols, l.rows)) return tr('${i.kind.label} nằm ngoài lưới', '${i.kind.label} is outside the grid');
      final lim = SizeLimits.of(i.kind);
      if (i.w < lim.minW || i.h < lim.minH || i.w > lim.maxW || i.h > lim.maxH) {
        return tr('${i.kind.label} có kích thước ngoài giới hạn', '${i.kind.label} has an out-of-range size');
      }
      if (collides(l, i.id, r)) return tr('Có phần tử chồng lên nhau', 'Some controls overlap');
      for (final id in i.inputIds) {
        if (!seen.add(id)) return tr('Input "$id" có nhiều hơn một phần tử trên màn', 'Input "$id" has more than one control on screen');
      }
      final err = i.returnCfg?.validate() ?? i.returnCfgY?.validate();
      if (err != null) return err;
      if (i.style.deadzonePct < 0 || i.style.deadzonePct > 20) return tr('Vùng chết trong khoảng 0–20%', 'Deadzone must be 0–20%');
      if (i.style.opacityPct < 30 || i.style.opacityPct > 100) return tr('Độ trong suốt trong khoảng 30–100%', 'Opacity must be 30–100%');
    }
    if (throttleInputs.isNotEmpty && !throttleInputs.any(seen.contains)) {
      return tr('Bố cục phải có phần tử điều khiển kênh Ga', 'The layout needs a control for the throttle channel');
    }
    if (steerInputs.isNotEmpty && !steerInputs.any(seen.contains)) {
      return tr('Bố cục phải có phần tử điều khiển kênh Lái', 'The layout needs a control for the steering channel');
    }
    return null;
  }
}
