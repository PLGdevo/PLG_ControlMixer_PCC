// Input (Sprint 4 — I1, I2): nguồn dữ liệu điều khiển. UI chỉ tạo Input; luật mix quyết định
// Input tác động lên kênh nào. Input thuộc hồ sơ, nhiều bố cục dùng chung.
import '../l10n/lang.dart';
import 'control_layout.dart';

enum InputType {
  axis('Trục', 'Axis'),
  binary('Bật/tắt', 'On/off'),
  ternary('3 nấc', '3-position'),
  constant('Hằng số', 'Constant');

  const InputType(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

enum AxisRange {
  bipolar('−100…+100%'),
  unipolar('0…100%');

  const AxisRange(this.label);
  final String label;
}

/// % đưa vào mixer ở từng trạng thái của Input binary / ternary
class InputLevels {
  double offPct; // binary: tắt; ternary: nấc trái
  double midPct; // ternary: nấc giữa
  double onPct; // binary: bật; ternary: nấc phải

  InputLevels({this.offPct = -100, this.midPct = 0, this.onPct = 100});

  Map<String, dynamic> toJson() => {'offPct': offPct, 'midPct': midPct, 'onPct': onPct};

  factory InputLevels.fromJson(Map<String, dynamic>? j) {
    double d(String k, double def) => (j?[k] as num?)?.toDouble() ?? def;
    return InputLevels(offPct: d('offPct', -100), midPct: d('midPct', 0), onPct: d('onPct', 100));
  }
}

class InputDef {
  static const maxInputs = 48;
  static final idPattern = RegExp(r'^[a-z0-9_]{1,24}$');

  String id;
  String name;
  InputType type;
  AxisRange range; // chỉ axis
  InputLevels levels; // chỉ binary / ternary
  double constPct; // chỉ constant

  InputDef({
    required this.id,
    required this.name,
    this.type = InputType.axis,
    this.range = AxisRange.bipolar,
    InputLevels? levels,
    this.constPct = 0,
  }) : levels = levels ?? InputLevels();

  bool get isAxis => type == InputType.axis;
  bool get isUnipolar => type == InputType.axis && range == AxisRange.unipolar;

  /// Trạng thái nghỉ (I3): axis = 0 (unipolar: 0 = cần ở thấp nhất), binary = tắt, ternary = giữa
  double get restState => type == InputType.constant ? constPct : 0;

  /// Trạng thái → giá trị % đưa vào mixer (I2)
  double valueOf(double state) => switch (type) {
        InputType.axis => state,
        InputType.binary => state >= 0.5 ? levels.onPct : levels.offPct,
        InputType.ternary => state <= -0.5 ? levels.offPct : (state >= 0.5 ? levels.onPct : levels.midPct),
        InputType.constant => constPct,
      };

  /// Vị trí cần (−100…+100) → trạng thái. Unipolar đổi thành 0…100 (I2).
  double stateFromPosition(double pos) {
    final p = pos.clamp(-100.0, 100.0).toDouble();
    return isUnipolar ? (p + 100) / 2 : p;
  }

  /// Phần tử loại `k` có gắn được vào Input này không (I2)
  bool accepts(ItemKind k) => switch (type) {
        InputType.axis => k.isStick || k == ItemKind.knob,
        InputType.binary => k == ItemKind.button || k == ItemKind.toggle,
        InputType.ternary => k == ItemKind.switch3,
        InputType.constant => false,
      };

  /// Kiểu Input phù hợp với loại phần tử (dùng khi tạo Input từ phần tử)
  static InputType typeFor(ItemKind k) => switch (k) {
        ItemKind.button || ItemKind.toggle => InputType.binary,
        ItemKind.switch3 => InputType.ternary,
        _ => InputType.axis,
      };

  /// Kiểm tra (V). Trả về lỗi đầu tiên hoặc null.
  String? validate() {
    if (!idPattern.hasMatch(id)) return tr('Mã Input chỉ gồm a–z, 0–9, "_" (1–24 ký tự)', 'Input ID may only use a–z, 0–9, "_" (1–24 characters)');
    final n = name.trim();
    if (n.isEmpty || n.length > 24) return tr('Tên Input dài 1–24 ký tự', 'Input name must be 1–24 characters');
    bool inRange(double v) => v >= -100 && v <= 100;
    if (!inRange(levels.offPct) || !inRange(levels.midPct) || !inRange(levels.onPct)) {
      return tr('Mức bật/tắt trong khoảng −100…+100%', 'On/off levels must be within −100…+100%');
    }
    if (!inRange(constPct)) return tr('Hằng số trong khoảng −100…+100%', 'Constant must be within −100…+100%');
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        if (type == InputType.axis) 'range': range.name,
        if (type == InputType.binary || type == InputType.ternary) 'levels': levels.toJson(),
        if (type == InputType.constant) 'constPct': constPct,
      };

  factory InputDef.fromJson(Map<String, dynamic> j) => InputDef(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        type: InputType.values.asNameMap()[j['type']] ?? InputType.axis,
        range: AxisRange.values.asNameMap()[j['range']] ?? AxisRange.bipolar,
        levels: InputLevels.fromJson(j['levels'] as Map<String, dynamic>?),
        constPct: (j['constPct'] as num?)?.toDouble() ?? 0,
      );

  InputDef copy() => InputDef.fromJson(toJson());

  /// Tạo mã Input chưa dùng từ `base` (vd "slider_x", "slider_x_2", ...)
  static String uniqueId(String base, Iterable<String> taken) {
    var b = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (b.isEmpty) b = 'input';
    if (b.length > 20) b = b.substring(0, 20);
    final set = taken.toSet();
    if (!set.contains(b)) return b;
    for (var i = 2;; i++) {
      final c = '${b}_$i';
      if (!set.contains(c)) return c;
    }
  }
}
