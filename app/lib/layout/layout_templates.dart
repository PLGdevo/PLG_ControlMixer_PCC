// Bố cục khởi đầu. (Các mẫu Thuận tay trái / Tay cầm / Tối giản và nút Lật ngang thuộc H4, Sprint 4.)
import '../models/control_layout.dart';
import 'layout_grid.dart';

abstract final class LayoutTemplates {
  static ControlItem _it(ItemKind k, int x, int y, int w, int h, {String? input, String? gauge, ReturnConfig? ret}) =>
      ControlItem(
        id: ControlItem.newId(),
        kind: k,
        inputId: input,
        gaugeKey: gauge,
        x: x,
        y: y,
        w: w,
        h: h,
        returnCfg: ret,
      );

  /// Bố cục trống (mẫu "Trống"): chỉ trạng thái và đồng hồ; cần gạt, hộp số, trim người dùng tự thêm.
  static ControlLayout blank() => ControlLayout(id: ControlLayout.newId(), name: 'Mặc định', items: [
        _it(ItemKind.statusBadge, 5, 0, 6, 2),
        _it(ItemKind.gauge, 5, 2, 4, 2, gauge: GaugeKey.battery.name),
        _it(ItemKind.gauge, 9, 2, 4, 2, gauge: GaugeKey.current.name),
        _it(ItemKind.gauge, 5, 4, 4, 2, gauge: GaugeKey.speed.name),
        _it(ItemKind.gauge, 9, 4, 4, 2, gauge: GaugeKey.ping.name),
      ]);

  /// "Mặc định": ga dọc trái, lái ngang phải, đồng hồ ở giữa.
  static ControlLayout standard({String steerInput = 'steer', String throttleInput = 'throttle'}) {
    // Input Ga vào cần gạt dọc, Lái vào cần gạt ngang; phần tử khác người dùng tự thêm rồi gắn Input
    return blank()
      ..items.addAll([
        _it(ItemKind.gearBox, 5, 9, 8, 3),
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
        ItemKind.gearBox || ItemKind.trim => (6, 2),
      };

  /// Thêm một phần tử điều khiển (cần gạt, nút, ...) vào chỗ trống, gắn sẵn Input nếu có.
  /// Input đang ở phần tử khác trên bố cục thì được chuyển sang phần tử mới (I3).
  static ControlItem? addControl(ControlLayout l, ItemKind kind, {String? inputId}) {
    final item = _place(l, kind);
    if (item != null && inputId != null) l.bindInput(item, inputId);
    return item;
  }

  /// Thêm một ô đồng hồ / hộp số / trim / trạng thái
  static ControlItem? addWidget(ControlLayout l, ItemKind kind, {String? gaugeKey}) =>
      _place(l, kind, gaugeKey: gaugeKey);

  static ControlItem? _place(ControlLayout l, ItemKind kind, {String? gaugeKey}) {
    final (w, h) = defaultSize(kind);
    final spot = LayoutGrid.findFreeSpot(l, w, h) ?? LayoutGrid.findFreeSpot(l, SizeLimits.of(kind).minW, SizeLimits.of(kind).minH);
    if (spot == null) return null;
    final item = ControlItem(
      id: ControlItem.newId(),
      kind: kind,
      gaugeKey: gaugeKey,
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
