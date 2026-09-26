// Mô hình bố cục màn Lái (H1), thuộc tính phần tử (H3) và cài đặt tự về (H3b).
// Phần tử gắn vào Input (Sprint 4 — I3), không gắn thẳng vào kênh.
import 'dart:collection';
import 'dart:math';

import '../l10n/lang.dart';
import '../theme/tokens.dart';


enum ItemKind {
  stickH('Cần gạt ngang', 'Horizontal stick'),
  stickV('Cần gạt dọc', 'Vertical stick'),
  stick2D('Cần 2 trục', '2-axis stick'),
  button('Nút nhấn giữ', 'Push button'),
  toggle('Nút bật/tắt', 'Toggle button'),
  switch3('Công tắc 3 nấc', '3-position switch'),
  knob('Núm xoay', 'Knob'),
  gauge('Ô đồng hồ', 'Gauge'),
  gearBox('Hộp số', 'Gearbox'),
  trim('Trim lái', 'Steering trim'),
  statusBadge('Trạng thái', 'Status');

  const ItemKind(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);

  bool get isControl => index <= ItemKind.knob.index;
  bool get isStick => this == stickH || this == stickV || this == stick2D;
  bool get isSwitchLike => this == button || this == toggle || this == switch3;

  /// Các loại phần tử điều khiển có thể thêm tự do lên màn Lái (không giới hạn số lượng)
  static List<ItemKind> get controls => values.where((k) => k.isControl).toList();
}

/// Các ô đồng hồ có thể đặt lên màn Lái
enum GaugeKey {
  battery('Pin', 'Battery'),
  current('Dòng', 'Current'),
  speed('Tốc độ', 'Speed'),
  ping('Ping', 'Ping'),
  rssi('RSSI', 'RSSI'),
  channels('Kênh đầu ra', 'Output channels');

  const GaugeKey(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

/// Giới hạn kích thước theo ô lưới (H2)
class SizeLimits {
  final int minW, minH, maxW, maxH;
  const SizeLimits(this.minW, this.minH, this.maxW, this.maxH);

  static SizeLimits of(ItemKind k) => switch (k) {
        ItemKind.stickH => const SizeLimits(6, 2, 24, 4),
        ItemKind.stickV => const SizeLimits(2, 6, 4, 12),
        ItemKind.stick2D => const SizeLimits(5, 5, 12, 12),
        ItemKind.button || ItemKind.toggle => const SizeLimits(2, 2, 6, 4),
        ItemKind.switch3 => const SizeLimits(3, 2, 8, 4),
        ItemKind.knob => const SizeLimits(3, 3, 6, 6),
        ItemKind.gauge || ItemKind.statusBadge => const SizeLimits(3, 2, 8, 4),
        ItemKind.gearBox || ItemKind.trim => const SizeLimits(4, 2, 12, 4),
      };

  /// Nâng kích thước nhỏ nhất để vùng chạm ≥ 48 dp trên màn thật
  SizeLimits forCell(double cellW, double cellH, {bool touchable = true}) {
    if (!touchable || cellW <= 0 || cellH <= 0) return this;
    final mw = max(minW, (48 / cellW).ceil());
    final mh = max(minH, (48 / cellH).ceil());
    return SizeLimits(mw, mh, max(maxW, mw), max(maxH, mh));
  }
}

enum ValueDisplay {
  pct('%', '%'),
  us('µs', 'µs'),
  hidden('Ẩn', 'Hidden');

  const ValueDisplay(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

enum KnobSize {
  small('Nhỏ', 'Small', 0.28),
  medium('Vừa', 'Medium', 0.38),
  large('Lớn', 'Large', 0.5);

  const KnobSize(this._vi, this._en, this.factor);
  final String _vi, _en;
  final double factor;
  String get label => tr(_vi, _en);
}

class ItemStyle {
  String? labelText; // null = dùng tên Input
  bool showLabel;
  String? iconName; // khoá trong AppIcons.pickable
  ValueDisplay valueDisplay;
  KnobSize knobSize;
  double deadzonePct; // 0–20
  bool haptic;
  double opacityPct; // 30–100
  AccentColor? color; // màu riêng của phần tử; null = theo màu chủ đạo của app

  ItemStyle({
    this.labelText,
    this.showLabel = true,
    this.iconName,
    this.valueDisplay = ValueDisplay.pct,
    this.knobSize = KnobSize.medium,
    this.deadzonePct = 0,
    this.haptic = true,
    this.opacityPct = 100,
    this.color,
  });

  Map<String, dynamic> toJson() => {
        'labelText': labelText,
        'showLabel': showLabel,
        'iconName': iconName,
        'valueDisplay': valueDisplay.name,
        'knobSize': knobSize.name,
        'deadzonePct': deadzonePct,
        'haptic': haptic,
        'opacityPct': opacityPct,
        if (color != null) 'color': color!.name,
      };

  factory ItemStyle.fromJson(Map<String, dynamic>? j) {
    if (j == null) return ItemStyle();
    return ItemStyle(
      labelText: j['labelText'] as String?,
      showLabel: j['showLabel'] as bool? ?? true,
      iconName: j['iconName'] as String?,
      valueDisplay: ValueDisplay.values.asNameMap()[j['valueDisplay']] ?? ValueDisplay.pct,
      knobSize: KnobSize.values.asNameMap()[j['knobSize']] ?? KnobSize.medium,
      deadzonePct: (j['deadzonePct'] as num?)?.toDouble() ?? 0,
      haptic: j['haptic'] as bool? ?? true,
      opacityPct: (j['opacityPct'] as num?)?.toDouble() ?? 100,
      color: AccentColor.values.asNameMap()[j['color']],
    );
  }
}

enum ReturnMode {
  spring('Tự về', 'Spring back'),
  hold('Giữ vị trí', 'Hold position'),
  halfSpring('Về một nửa', 'Half return');

  const ReturnMode(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

enum ReturnCurve {
  linear('Tuyến tính', 'Linear'),
  easeOut('Chậm dần cuối', 'Ease out');

  const ReturnCurve(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

/// Cài đặt tự về của một trục cần gạt (H3b)
class ReturnConfig {
  ReturnMode mode;
  double targetPct; // −100…+100
  int delayMs; // 0–1000
  int durationMs; // 0–2000, 0 = về ngay
  ReturnCurve curve;
  bool positiveOnly, negativeOnly;
  bool rememberOnExit; // chỉ cho chế độ Giữ vị trí

  ReturnConfig({
    this.mode = ReturnMode.spring,
    this.targetPct = 0,
    this.delayMs = 0,
    this.durationMs = 0,
    this.curve = ReturnCurve.linear,
    this.positiveOnly = false,
    this.negativeOnly = false,
    this.rememberOnExit = false,
  });

  /// Cài đặt nhanh
  factory ReturnConfig.instant() => ReturnConfig();
  factory ReturnConfig.smooth() => ReturnConfig(durationMs: 300, curve: ReturnCurve.easeOut);
  factory ReturnConfig.holdPosition() => ReturnConfig(mode: ReturnMode.hold);

  /// Thả tay ở vị trí `value` thì có tự về không
  bool returnsFrom(double value) => switch (mode) {
        ReturnMode.spring => true,
        ReturnMode.hold => false,
        ReturnMode.halfSpring => positiveOnly ? value > 0 : (negativeOnly ? value < 0 : true),
      };

  /// Có thể làm xe tiếp tục chạy sau khi thả tay (cảnh báo khi gán cho kênh ga)
  bool get risky => mode == ReturnMode.hold || durationMs > 500;

  String? validate() {
    if (targetPct < -100 || targetPct > 100) return tr('Vị trí về phải trong −100…+100%', 'Return position must be within −100…+100%');
    if (positiveOnly && negativeOnly) return tr('Không thể bật cả "chỉ nửa dương" và "chỉ nửa âm"', 'Cannot enable both "positive half only" and "negative half only"');
    if (delayMs < 0 || delayMs > 1000) return tr('Trễ trước khi về trong 0–1000 ms', 'Return delay must be 0–1000 ms');
    if (durationMs < 0 || durationMs > 2000) return tr('Thời gian về trong 0–2000 ms', 'Return time must be 0–2000 ms');
    return null;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'targetPct': targetPct,
        'delayMs': delayMs,
        'durationMs': durationMs,
        'curve': curve.name,
        'positiveOnly': positiveOnly,
        'negativeOnly': negativeOnly,
        'rememberOnExit': rememberOnExit,
      };

  factory ReturnConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return ReturnConfig();
    return ReturnConfig(
      mode: ReturnMode.values.asNameMap()[j['mode']] ?? ReturnMode.spring,
      targetPct: (j['targetPct'] as num?)?.toDouble() ?? 0,
      delayMs: j['delayMs'] as int? ?? 0,
      durationMs: j['durationMs'] as int? ?? 0,
      curve: ReturnCurve.values.asNameMap()[j['curve']] ?? ReturnCurve.linear,
      positiveOnly: j['positiveOnly'] as bool? ?? false,
      negativeOnly: j['negativeOnly'] as bool? ?? false,
      rememberOnExit: j['rememberOnExit'] as bool? ?? false,
    );
  }

  ReturnConfig copy() => ReturnConfig.fromJson(toJson());
}

class ControlItem {
  String id;
  ItemKind kind;
  String? inputId; // Input gắn vào; với stick2D là trục X
  String? inputIdY; // chỉ stick2D
  String? gaugeKey; // với kind = gauge
  int x, y, w, h; // theo ô lưới
  ItemStyle style;
  ReturnConfig? returnCfg; // cần gạt (trục X với stick2D)
  ReturnConfig? returnCfgY; // trục Y của stick2D
  double? savedPct, savedPctY; // vị trí nhớ khi thoát (Giữ vị trí + Nhớ vị trí)

  ControlItem({
    required this.id,
    required this.kind,
    this.inputId,
    this.inputIdY,
    this.gaugeKey,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    ItemStyle? style,
    this.returnCfg,
    this.returnCfgY,
    this.savedPct,
    this.savedPctY,
  }) : style = style ?? ItemStyle();

  static String newId() =>
      'it-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 20).toRadixString(36)}';

  /// Các Input mà phần tử này điều khiển
  List<String> get inputIds => [if (inputId != null) inputId!, if (inputIdY != null) inputIdY!];

  /// Cài đặt tự về của trục gắn Input `id` (null nếu không phải cần gạt hoặc không gắn Input đó)
  ReturnConfig? returnFor(String id) {
    if (!kind.isStick) return null;
    if (kind == ItemKind.stick2D && inputIdY == id) return returnCfgY ?? ReturnConfig();
    return inputId == id ? returnCfg ?? ReturnConfig() : null;
  }

  bool get touchable => kind.isControl || kind == ItemKind.gearBox || kind == ItemKind.trim;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'inputId': inputId,
        'inputIdY': inputIdY,
        'gaugeKey': gaugeKey,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'style': style.toJson(),
        'returnCfg': returnCfg?.toJson(),
        'returnCfgY': returnCfgY?.toJson(),
        'savedPct': savedPct,
        'savedPctY': savedPctY,
      };

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
        id: j['id'] as String? ?? newId(),
        kind: ItemKind.values.asNameMap()[j['kind']] ?? ItemKind.button,
        inputId: j['inputId'] as String?,
        inputIdY: j['inputIdY'] as String?,
        gaugeKey: j['gaugeKey'] as String?,
        x: j['x'] as int,
        y: j['y'] as int,
        w: j['w'] as int,
        h: j['h'] as int,
        style: ItemStyle.fromJson(j['style'] as Map<String, dynamic>?),
        returnCfg: j['returnCfg'] == null ? null : ReturnConfig.fromJson(j['returnCfg'] as Map<String, dynamic>),
        returnCfgY:
            j['returnCfgY'] == null ? null : ReturnConfig.fromJson(j['returnCfgY'] as Map<String, dynamic>),
        savedPct: (j['savedPct'] as num?)?.toDouble(),
        savedPctY: (j['savedPctY'] as num?)?.toDouble(),
      );

  ControlItem copy() => ControlItem.fromJson(toJson());
}

class ControlLayout {
  static const defaultCols = 24, defaultRows = 12;

  String id;
  String name;
  int cols, rows;
  List<ControlItem> items;
  bool locked; // Khoá bố cục (H5), mặc định bật

  ControlLayout({
    required this.id,
    required this.name,
    this.cols = defaultCols,
    this.rows = defaultRows,
    List<ControlItem>? items,
    this.locked = true,
  }) : items = items ?? [];

  static String newId() => 'lay-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  ControlItem? itemForInput(String id) => items.where((i) => i.inputIds.contains(id)).firstOrNull;

  /// Gắn Input `id` vào phần tử `item` (trục Y nếu `y`). Một Input chỉ có một phần tử trên
  /// một bố cục (I3) nên Input được gỡ khỏi phần tử đang giữ nó. `id` = null để bỏ gắn.
  /// Trả về phần tử bị gỡ Input (nếu có) để báo cho người dùng.
  ControlItem? bindInput(ControlItem item, String? id, {bool y = false}) {
    ControlItem? moved;
    if (id != null) {
      for (final o in items) {
        if (o.inputId == id && !(o.id == item.id && !y)) {
          o.inputId = null;
          moved = o;
        }
        if (o.inputIdY == id && !(o.id == item.id && y)) {
          o.inputIdY = null;
          moved = o;
        }
      }
    }
    if (y) {
      item.inputIdY = id;
    } else {
      item.inputId = id;
    }
    return moved;
  }

  /// Gỡ Input `id` khỏi mọi phần tử (khi xoá Input)
  void unbindInput(String id) {
    for (final o in items) {
      if (o.inputId == id) o.inputId = null;
      if (o.inputIdY == id) o.inputIdY = null;
    }
  }

  /// Đổi mã Input trên mọi phần tử
  void renameInput(String from, String to) {
    for (final o in items) {
      if (o.inputId == from) o.inputId = to;
      if (o.inputIdY == from) o.inputIdY = to;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cols': cols,
        'rows': rows,
        'locked': locked,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ControlLayout.fromJson(Map<String, dynamic> j) => ControlLayout(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? 'Bố cục',
        cols: j['cols'] as int? ?? defaultCols,
        rows: j['rows'] as int? ?? defaultRows,
        locked: j['locked'] as bool? ?? true,
        items: (j['items'] as List? ?? const [])
            .map((e) => ControlItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  ControlLayout copy() => ControlLayout.fromJson(toJson());
}
