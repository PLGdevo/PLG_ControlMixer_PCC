// Mô hình bố cục màn Lái (H1), thuộc tính phần tử (H3) và cài đặt tự về (H3b).
import 'dart:collection';
import 'dart:math';


enum ItemKind {
  stickH('Cần gạt ngang'),
  stickV('Cần gạt dọc'),
  stick2D('Cần 2 trục'),
  button('Nút nhấn giữ'),
  toggle('Nút bật/tắt'),
  switch3('Công tắc 3 nấc'),
  knob('Núm xoay'),
  gauge('Ô đồng hồ'),
  gearBox('Hộp số'),
  trim('Trim lái'),
  statusBadge('Trạng thái');

  const ItemKind(this.label);
  final String label;

  bool get isControl => index <= ItemKind.knob.index;
  bool get isStick => this == stickH || this == stickV || this == stick2D;
  bool get isSwitchLike => this == button || this == toggle || this == switch3;

  /// Các loại phần tử điều khiển có thể thêm tự do lên màn Lái (không giới hạn số lượng)
  static List<ItemKind> get controls => values.where((k) => k.isControl).toList();
}

/// Các ô đồng hồ có thể đặt lên màn Lái
enum GaugeKey {
  battery('Pin'),
  current('Dòng'),
  speed('Tốc độ'),
  ping('Ping'),
  rssi('RSSI');

  const GaugeKey(this.label);
  final String label;
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
  pct('%'),
  us('µs'),
  hidden('Ẩn');

  const ValueDisplay(this.label);
  final String label;
}

enum KnobSize {
  small('Nhỏ', 0.28),
  medium('Vừa', 0.38),
  large('Lớn', 0.5);

  const KnobSize(this.label, this.factor);
  final String label;
  final double factor;
}

class ItemStyle {
  String? labelText; // null = dùng tên kênh
  bool showLabel;
  String? iconName; // khoá trong AppIcons.pickable
  ValueDisplay valueDisplay;
  KnobSize knobSize;
  double deadzonePct; // 0–20
  bool haptic;
  double opacityPct; // 30–100

  ItemStyle({
    this.labelText,
    this.showLabel = true,
    this.iconName,
    this.valueDisplay = ValueDisplay.pct,
    this.knobSize = KnobSize.medium,
    this.deadzonePct = 0,
    this.haptic = true,
    this.opacityPct = 100,
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
    );
  }
}

enum ReturnMode {
  spring('Tự về'),
  hold('Giữ vị trí'),
  halfSpring('Về một nửa');

  const ReturnMode(this.label);
  final String label;
}

enum ReturnCurve {
  linear('Tuyến tính'),
  easeOut('Chậm dần cuối');

  const ReturnCurve(this.label);
  final String label;
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
    if (targetPct < -100 || targetPct > 100) return 'Vị trí về phải trong −100…+100%';
    if (positiveOnly && negativeOnly) return 'Không thể bật cả "chỉ nửa dương" và "chỉ nửa âm"';
    if (delayMs < 0 || delayMs > 1000) return 'Trễ trước khi về trong 0–1000 ms';
    if (durationMs < 0 || durationMs > 2000) return 'Thời gian về trong 0–2000 ms';
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
  int? channel; // 1..10; với stick2D là trục X
  int? channelY; // chỉ stick2D
  String? gaugeKey; // với kind = gauge
  int x, y, w, h; // theo ô lưới
  ItemStyle style;
  ReturnConfig? returnCfg; // cần gạt (trục X với stick2D)
  ReturnConfig? returnCfgY; // trục Y của stick2D
  double? savedPct, savedPctY; // vị trí nhớ khi thoát (Giữ vị trí + Nhớ vị trí)

  ControlItem({
    required this.id,
    required this.kind,
    this.channel,
    this.channelY,
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

  /// Các kênh mà phần tử này điều khiển
  List<int> get channels => [if (channel != null) channel!, if (channelY != null) channelY!];

  bool get touchable => kind.isControl || kind == ItemKind.gearBox || kind == ItemKind.trim;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'channel': channel,
        'channelY': channelY,
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
        channel: j['channel'] as int?,
        channelY: j['channelY'] as int?,
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

  ControlItem? itemForChannel(int ch) => items.where((i) => i.channels.contains(ch)).firstOrNull;

  /// Gán kênh `ch` cho phần tử `item` (trục Y nếu `y`). Mỗi kênh chỉ có một phần tử trên
  /// một bố cục (H7) nên kênh được gỡ khỏi phần tử đang giữ nó. `ch` = null để bỏ gán.
  /// Trả về phần tử bị gỡ kênh (nếu có) để báo cho người dùng.
  ControlItem? assignChannel(ControlItem item, int? ch, {bool y = false}) {
    ControlItem? moved;
    if (ch != null) {
      for (final o in items) {
        if (o.channel == ch && !(o.id == item.id && !y)) {
          o.channel = null;
          moved = o;
        }
        if (o.channelY == ch && !(o.id == item.id && y)) {
          o.channelY = null;
          moved = o;
        }
      }
    }
    if (y) {
      item.channelY = ch;
    } else {
      item.channel = ch;
    }
    return moved;
  }

  /// Gỡ kênh `ch` khỏi mọi phần tử (khi tắt kênh)
  void unassignChannel(int ch) {
    for (final o in items) {
      if (o.channel == ch) o.channel = null;
      if (o.channelY == ch) o.channelY = null;
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
