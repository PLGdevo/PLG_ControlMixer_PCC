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
  trim('Trim lái', 'Steering trim'),
  statusBadge('Trạng thái', 'Status'),
  led('Đèn LED', 'LED'),
  bar('Thanh giá trị', 'Value bar'),
  vector('Vector 2D', '2D vector'),
  channels('Bảng kênh', 'Channel monitor'),
  trimBar('Thanh trim', 'Trim bar');

  const ItemKind(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);

  bool get isControl => index <= ItemKind.knob.index;
  bool get isStick => this == stickH || this == stickV || this == stick2D;
  bool get isSwitchLike => this == button || this == toggle || this == switch3;

  /// Phần tử chỉ hiện một nguồn giá trị (DataSource), không điều khiển
  bool get isDisplay => this == gauge || this == led || this == bar || this == vector;

  /// Các loại phần tử điều khiển có thể thêm tự do lên màn Lái (không giới hạn số lượng)
  static List<ItemKind> get controls => values.where((k) => k.isControl).toList();
}

/// Giới hạn kích thước theo ô lưới (H2). Không giới hạn trên: phần tử to tuỳ ý miễn nằm trong
/// lưới và không đè phần tử khác; chỉ có cỡ nhỏ nhất để phần tử còn vẽ được.
class SizeLimits {
  final int minW, minH, maxW, maxH;
  const SizeLimits(this.minW, this.minH, [this.maxW = 1 << 16, this.maxH = 1 << 16]);

  static SizeLimits of(ItemKind k) => switch (k) {
        ItemKind.stickH || ItemKind.stickV || ItemKind.stick2D || ItemKind.knob => const SizeLimits(2, 2),
        ItemKind.switch3 || ItemKind.trim => const SizeLimits(3, 2),
        ItemKind.trimBar => const SizeLimits(2, 2),
        _ => const SizeLimits(1, 1),
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

/// Trục dùng của cần 2 trục: như tay RC, một cần có thể chỉ điều khiển 1 kênh (khoá trục kia, có rãnh dẫn)
enum StickAxes {
  both('Cả 2 trục', 'Both axes'),
  x('Chỉ ngang ↔', 'Horizontal ↔'),
  y('Chỉ dọc ↕', 'Vertical ↕');

  const StickAxes(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);

  bool get hasX => this != y;
  bool get hasY => this != x;
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
  bool gimbal; // cần 2 trục vẽ kiểu tay RC (đế, giếng, núm có khía); false = kiểu phẳng cũ

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
    this.gimbal = true,
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
        'gimbal': gimbal,
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
      gimbal: j['gimbal'] as bool? ?? true,
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

enum LedBlink {
  off('Sáng liền', 'Steady', 0),
  slow('Nháy chậm', 'Slow blink', 1000),
  fast('Nháy nhanh', 'Fast blink', 300);

  const LedBlink(this._vi, this._en, this.periodMs);
  final String _vi, _en;
  final int periodMs;
  String get label => tr(_vi, _en);
}

/// Cấu hình phần tử hiển thị. Để trống (null) = theo mặc định của nguồn giá trị.
class DisplayConfig {
  double? min, max; // khoảng của thanh giá trị
  double? threshold; // ngưỡng bật đèn LED (nguồn dạng số)
  bool? below; // LED sáng khi giá trị dưới ngưỡng (true) hay trên ngưỡng (false)
  LedBlink blink; // LED nháy khi sáng
  bool trail; // vector: vệt chuyển động

  DisplayConfig({this.min, this.max, this.threshold, this.below, this.blink = LedBlink.off, this.trail = true});

  Map<String, dynamic> toJson() => {
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (threshold != null) 'threshold': threshold,
        if (below != null) 'below': below,
        'blink': blink.name,
        'trail': trail,
      };

  factory DisplayConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return DisplayConfig();
    return DisplayConfig(
      min: (j['min'] as num?)?.toDouble(),
      max: (j['max'] as num?)?.toDouble(),
      threshold: (j['threshold'] as num?)?.toDouble(),
      below: j['below'] as bool?,
      blink: LedBlink.values.asNameMap()[j['blink']] ?? LedBlink.off,
      trail: j['trail'] as bool? ?? true,
    );
  }
}

class ControlItem {
  String id;
  ItemKind kind;
  String? inputId; // Input gắn vào; với stick2D là trục X
  String? inputIdY; // chỉ stick2D
  String? source; // phần tử hiển thị: khoá nguồn giá trị (DataSource); với vector là trục X
  String? sourceY; // chỉ vector
  int x, y, w, h; // theo ô lưới
  ItemStyle style;
  DisplayConfig display;
  ReturnConfig? returnCfg; // cần gạt (trục X với stick2D)
  ReturnConfig? returnCfgY; // trục Y của stick2D
  double? savedPct, savedPctY; // vị trí nhớ khi thoát (Giữ vị trí + Nhớ vị trí)
  StickAxes axes; // cần 2 trục: dùng 1 hay 2 trục
  int? trimCh; // thanh trim: kênh được trim; null = kênh Lái
  List<int>? chList; // bảng kênh: các kênh hiện; null = mọi kênh đang bật

  ControlItem({
    required this.id,
    required this.kind,
    this.inputId,
    this.inputIdY,
    this.source,
    this.sourceY,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    ItemStyle? style,
    DisplayConfig? display,
    this.returnCfg,
    this.returnCfgY,
    this.savedPct,
    this.savedPctY,
    this.axes = StickAxes.both,
    this.trimCh,
    this.chList,
  })  : style = style ?? ItemStyle(),
        display = display ?? DisplayConfig();

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

  bool get touchable => kind.isControl || kind == ItemKind.trim || kind == ItemKind.trimBar;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'inputId': inputId,
        'inputIdY': inputIdY,
        if (source != null) 'source': source,
        if (sourceY != null) 'sourceY': sourceY,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'style': style.toJson(),
        if (kind.isDisplay) 'display': display.toJson(),
        'returnCfg': returnCfg?.toJson(),
        'returnCfgY': returnCfgY?.toJson(),
        'savedPct': savedPct,
        'savedPctY': savedPctY,
        if (kind == ItemKind.stick2D) 'axes': axes.name,
        if (trimCh != null) 'trimCh': trimCh,
        if (chList != null) 'chList': chList,
      };

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
        id: j['id'] as String? ?? newId(),
        kind: ItemKind.values.asNameMap()[j['kind']] ?? ItemKind.button,
        inputId: j['inputId'] as String?,
        inputIdY: j['inputIdY'] as String?,
        // Bố cục cũ: ô đồng hồ lưu khoá ở 'gaugeKey' (cùng tên khoá nguồn: battery, speed…)
        source: j['source'] as String? ?? j['gaugeKey'] as String?,
        sourceY: j['sourceY'] as String?,
        x: j['x'] as int,
        y: j['y'] as int,
        w: j['w'] as int,
        h: j['h'] as int,
        style: ItemStyle.fromJson(j['style'] as Map<String, dynamic>?),
        display: DisplayConfig.fromJson(j['display'] as Map<String, dynamic>?),
        returnCfg: j['returnCfg'] == null ? null : ReturnConfig.fromJson(j['returnCfg'] as Map<String, dynamic>),
        returnCfgY:
            j['returnCfgY'] == null ? null : ReturnConfig.fromJson(j['returnCfgY'] as Map<String, dynamic>),
        savedPct: (j['savedPct'] as num?)?.toDouble(),
        savedPctY: (j['savedPctY'] as num?)?.toDouble(),
        axes: StickAxes.values.asNameMap()[j['axes']] ?? StickAxes.both,
        trimCh: j['trimCh'] as int?,
        chList: (j['chList'] as List?)?.cast<int>(),
      );

  ControlItem copy() => ControlItem.fromJson(toJson());
}

class ControlLayout {
  /// Lưới dày (mỗi ô cũ 24×12 chia 4): đặt phần tử mịn hơn
  static const defaultCols = 48, defaultRows = 24;

  /// Loại phần tử đã bỏ khỏi app (vd hộp số): bố cục cũ còn thì bỏ qua khi đọc
  static const removedKinds = {'gearBox'};

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

  factory ControlLayout.fromJson(Map<String, dynamic> j) {
    final l = ControlLayout(
      id: j['id'] as String? ?? newId(),
      name: j['name'] as String? ?? 'Bố cục',
      cols: j['cols'] as int? ?? 24, // bố cục lưu trước khi có khoá cols/rows dùng lưới 24×12
      rows: j['rows'] as int? ?? 12,
      locked: j['locked'] as bool? ?? true,
      items: (j['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((e) => !removedKinds.contains(e['kind']))
          .map(ControlItem.fromJson)
          .toList(),
    );
    l._densify();
    return l;
  }

  /// Bố cục lưới thưa cũ (vd 24×12) → lưới dày hiện tại: nhân toạ độ, giữ nguyên hình trên màn
  void _densify() {
    if (cols >= defaultCols || defaultCols % cols != 0) return;
    final k = defaultCols ~/ cols;
    if (rows * k != defaultRows) return;
    cols = defaultCols;
    rows = defaultRows;
    for (final i in items) {
      i
        ..x *= k
        ..y *= k
        ..w *= k
        ..h *= k;
    }
  }

  ControlLayout copy() => ControlLayout.fromJson(toJson());
}
