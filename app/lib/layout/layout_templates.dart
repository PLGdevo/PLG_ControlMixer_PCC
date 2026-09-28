// Bố cục khởi đầu. (Các mẫu Thuận tay trái / Tay cầm / Tối giản và nút Lật ngang thuộc H4, Sprint 4.)
import '../l10n/lang.dart';
import '../models/control_layout.dart';
import '../models/data_source.dart';
import 'layout_grid.dart';

abstract final class LayoutTemplates {
  static ControlItem _it(ItemKind k, int x, int y, int w, int h, {String? input, String? source, ReturnConfig? ret}) =>
      ControlItem(
        id: ControlItem.newId(),
        kind: k,
        inputId: input,
        source: source,
        x: x,
        y: y,
        w: w,
        h: h,
        returnCfg: ret,
      );

  /// Bố cục trống (mẫu "Trống"): chỉ trạng thái và đồng hồ; cần gạt, trim người dùng tự thêm.
  static ControlLayout blank() => ControlLayout(id: ControlLayout.newId(), name: tr('Mặc định', 'Default'), items: [
        _it(ItemKind.statusBadge, 5, 0, 6, 2),
        _it(ItemKind.gauge, 5, 2, 4, 2, source: DataSource.battery),
        _it(ItemKind.gauge, 9, 2, 4, 2, source: DataSource.current),
        _it(ItemKind.gauge, 5, 4, 4, 2, source: DataSource.speed),
        _it(ItemKind.gauge, 9, 4, 4, 2, source: DataSource.ping),
      ]);

  /// "Mặc định": ga dọc trái, lái ngang phải, đồng hồ ở giữa.
  static ControlLayout standard({String steerInput = 'steer', String throttleInput = 'throttle'}) {
    // Input Ga vào cần gạt dọc, Lái vào cần gạt ngang; phần tử khác người dùng tự thêm rồi gắn Input
    return blank()
      ..items.addAll([
        _it(ItemKind.trim, 14, 6, 10, 2),
        _it(ItemKind.stickV, 0, 1, 4, 11, input: throttleInput, ret: ReturnConfig()),
        _it(ItemKind.stickH, 14, 9, 10, 3, input: steerInput, ret: ReturnConfig()),
      ]);
  }

  /// Kích thước mặc định khi thêm một loại phần tử
  static (int, int) defaultSize(ItemKind k) => switch (k) {
        ItemKind.stickH => (8, 3),
        ItemKind.stickV => (3, 8),
        ItemKind.stick2D => (6, 6),
        ItemKind.button || ItemKind.toggle => (3, 2),
        ItemKind.switch3 => (4, 2),
        ItemKind.knob => (3, 3),
        ItemKind.gauge || ItemKind.statusBadge => (4, 2),
        ItemKind.trim => (6, 2),
        ItemKind.led => (3, 1),
        ItemKind.bar => (6, 2),
        ItemKind.vector => (4, 4),
      };

  /// Thêm một phần tử điều khiển (cần gạt, nút, ...) vào chỗ trống, gắn sẵn Input nếu có.
  /// Input đang ở phần tử khác trên bố cục thì được chuyển sang phần tử mới (I3).
  static ControlItem? addControl(ControlLayout l, ItemKind kind, {String? inputId}) {
    final item = _place(l, kind);
    if (item != null && inputId != null) l.bindInput(item, inputId);
    return item;
  }

  /// Thêm một phần tử hiển thị (ô đồng hồ, LED, thanh, vector) / trim / trạng thái
  static ControlItem? addWidget(ControlLayout l, ItemKind kind, {String? source, String? sourceY}) =>
      _place(l, kind, source: source, sourceY: sourceY);

  static ControlItem? _place(ControlLayout l, ItemKind kind, {String? source, String? sourceY}) {
    final (w, h) = defaultSize(kind);
    final spot = LayoutGrid.findFreeSpot(l, w, h) ?? LayoutGrid.findFreeSpot(l, SizeLimits.of(kind).minW, SizeLimits.of(kind).minH);
    if (spot == null) return null;
    final item = ControlItem(
      id: ControlItem.newId(),
      kind: kind,
      source: source,
      sourceY: sourceY,
      x: spot.x,
      y: spot.y,
      w: spot.w,
      h: spot.h,
      returnCfg: kind.isStick ? ReturnConfig() : null,
      returnCfgY: kind == ItemKind.stick2D ? ReturnConfig() : null,
    );
    l.items.add(item);
    return item;
  }
}
