// Luật mix (Sprint 4 — M1): Nguồn (Input) → Condition → Weight / Offset / Curve / Min–Max → kênh đích.
import 'dart:math';

import 'condition.dart';
import 'input_def.dart';

enum Combine {
  replace('Thay thế'),
  add('Cộng'),
  multiply('Nhân'),
  max('Lấy lớn hơn'),
  min('Lấy nhỏ hơn');

  const Combine(this.label);
  final String label;
}

enum CurveType {
  linear('Tuyến tính'),
  expo('Expo'),
  points('5 điểm');

  const CurveType(this.label);
  final String label;
}

class Curve {
  static const xs = [-100.0, -50.0, 0.0, 50.0, 100.0];

  CurveType type;
  double expoPct; // −100…+100
  List<double> points; // 5 điểm tại −100, −50, 0, 50, 100

  Curve({this.type = CurveType.linear, this.expoPct = 0, List<double>? points})
      : points = points ?? [-100, -50, 0, 50, 100];

  /// Áp đường cong; đầu vào được kẹp về −100…+100 trước
  double apply(double x) {
    final v = x.clamp(-100.0, 100.0).toDouble();
    switch (type) {
      case CurveType.linear:
        return v;
      case CurveType.expo:
        final k = expoPct.clamp(-100.0, 100.0) / 100;
        final a = v.abs() / 100, b = 1 - a;
        // k > 0: mềm quanh tâm (y = (1−k)x + kx³); k < 0: hình phản chiếu, gắt quanh tâm
        final f = k >= 0 ? (1 - k) * a + k * a * a * a : 1 - ((1 + k) * b - k * b * b * b);
        return v.sign * f * 100;
      case CurveType.points:
        for (var i = 0; i < xs.length - 1; i++) {
          if (v <= xs[i + 1]) {
            final t = (v - xs[i]) / (xs[i + 1] - xs[i]);
            return points[i] + (points[i + 1] - points[i]) * t;
          }
        }
        return points.last;
    }
  }

  bool get isLinear => type == CurveType.linear;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (type == CurveType.expo) 'expoPct': expoPct,
        if (type == CurveType.points) 'points': points,
      };

  factory Curve.fromJson(Map<String, dynamic>? j) => Curve(
        type: CurveType.values.asNameMap()[j?['type']] ?? CurveType.linear,
        expoPct: (j?['expoPct'] as num?)?.toDouble() ?? 0,
        points: (j?['points'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

/// Khoá an toàn khi đổi đích (M4)
class SwitchSafety {
  /// null = tự chọn: bật nếu nguồn là Input axis và priority < [MixRule.emergencyPriority]
  bool? requireNeutral;
  double deadzonePct;

  SwitchSafety({this.requireNeutral, this.deadzonePct = 5});

  Map<String, dynamic> toJson() => {
        if (requireNeutral != null) 'requireNeutral': requireNeutral,
        'deadzonePct': deadzonePct,
      };

  factory SwitchSafety.fromJson(Map<String, dynamic>? j) => SwitchSafety(
        requireNeutral: j?['requireNeutral'] as bool?,
        deadzonePct: (j?['deadzonePct'] as num?)?.toDouble() ?? 5,
      );
}

class MixRule {
  static const maxRules = 64;
  static const emergencyPriority = 8; // priority ≥ 8: không được bật khoá an toàn (M4)

  String id;
  String name;
  bool enabled;
  String source; // inputId (kể cả constant)
  Expr condition;
  double weightPct; // −200…+200
  double offsetPct; // −100…+100
  Curve curve;
  double minPct, maxPct; // −100…+100
  int destCh; // 1..10
  Combine combine;
  int priority; // 0..9
  SwitchSafety safety;

  MixRule({
    required this.id,
    this.name = '',
    this.enabled = true,
    required this.source,
    this.condition = const ExprTrue(),
    this.weightPct = 100,
    this.offsetPct = 0,
    Curve? curve,
    this.minPct = -100,
    this.maxPct = 100,
    required this.destCh,
    this.combine = Combine.replace,
    this.priority = 0,
    SwitchSafety? safety,
  })  : curve = curve ?? Curve(),
        safety = safety ?? SwitchSafety();

  static String newId() {
    final r = Random();
    return 'r_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 16).toRadixString(36)}';
  }

  /// Khoá an toàn có hiệu lực không, theo kiểu nguồn (M1: mặc định bật nếu nguồn là axis)
  bool requiresNeutral(InputDef? src) =>
      safety.requireNeutral ?? (src != null && src.isAxis && priority < emergencyPriority);

  /// Kiểm tra riêng một luật (V). Trả về lỗi đầu tiên hoặc null.
  String? validate(Map<String, InputDef> inputs, Set<String> conditionIds) {
    if (!inputs.containsKey(source)) return 'Nguồn "$source" không tồn tại';
    if (destCh < 1 || destCh > 10) return 'Kênh đích phải trong CH1–CH10';
    if (weightPct < -200 || weightPct > 200) return 'Weight trong khoảng −200…+200%';
    if (offsetPct < -100 || offsetPct > 100) return 'Offset trong khoảng −100…+100%';
    if (minPct < -100 || maxPct > 100 || minPct >= maxPct) return 'Cần −100 ≤ Min < Max ≤ 100';
    if (priority < 0 || priority > 9) return 'Priority trong khoảng 0–9';
    if (curve.type == CurveType.expo && (curve.expoPct < -100 || curve.expoPct > 100)) {
      return 'Expo trong khoảng −100…+100%';
    }
    if (curve.type == CurveType.points &&
        (curve.points.length != 5 || curve.points.any((p) => p < -100 || p > 100))) {
      return 'Đường cong cần 5 điểm trong −100…+100%';
    }
    if (safety.deadzonePct < 0 || safety.deadzonePct > 50) return 'Vùng chết trong khoảng 0–50%';
    if (priority >= emergencyPriority && safety.requireNeutral == true) {
      return 'Luật priority ≥ $emergencyPriority không được bật khoá an toàn';
    }
    return condition.validate(inputs, conditionIds);
  }

  /// Mô tả tự sinh (M6)
  String describe(Map<String, InputDef> inputs, {String Function(int ch)? chName, String Function(String id)? condName}) {
    String nm(String id) => inputs[id]?.name ?? condName?.call(id) ?? id;
    String pct(double v) => '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}%';
    final dest = chName?.call(destCh) ?? 'CH$destCh';
    final src = inputs[source];
    final buf = StringBuffer();
    if (src?.type == InputType.constant) {
      final v = src!.constPct * weightPct / 100 + offsetPct;
      buf.write('$dest = ${pct(v)}');
    } else {
      buf.write(nm(source));
      if (weightPct != 100) buf.write(' × ${pct(weightPct)}');
      if (offsetPct != 0) buf.write(offsetPct > 0 ? ' + ${pct(offsetPct)}' : ' − ${pct(-offsetPct)}');
      if (!curve.isLinear) buf.write(' (${curve.type.label})');
      buf.write(' → $dest');
    }
    if (!condition.isTrue) buf.write(' · khi ${condition.describe(nm)}');
    if (combine != Combine.replace) buf.write(' · ${combine.label.toLowerCase()}');
    if (requiresNeutral(src)) buf.write(' · chờ về giữa');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name.isNotEmpty) 'name': name,
        'enabled': enabled,
        'source': source,
        'condition': condition.toJson(),
        'weightPct': weightPct,
        'offsetPct': offsetPct,
        'curve': curve.toJson(),
        'minPct': minPct,
        'maxPct': maxPct,
        'destCh': destCh,
        'combine': combine.name,
        'priority': priority,
        'safety': safety.toJson(),
      };

  factory MixRule.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return MixRule(
      id: j['id'] as String? ?? newId(),
      name: j['name'] as String? ?? '',
      enabled: j['enabled'] as bool? ?? true,
      source: j['source'] as String? ?? '',
      condition: Expr.fromJson(j['condition']),
      weightPct: d('weightPct', 100),
      offsetPct: d('offsetPct', 0),
      curve: Curve.fromJson(j['curve'] as Map<String, dynamic>?),
      minPct: d('minPct', -100),
      maxPct: d('maxPct', 100),
      destCh: j['destCh'] as int? ?? 1,
      combine: Combine.values.asNameMap()[j['combine']] ?? Combine.replace,
      priority: j['priority'] as int? ?? 0,
      safety: SwitchSafety.fromJson(j['safety'] as Map<String, dynamic>?),
    );
  }

  MixRule copy() => MixRule.fromJson(toJson());
}

/// Kiểm tra cả bộ Input / Condition / luật (V). Trả về (lỗi, cảnh báo).
({List<String> errors, List<String> warnings}) validateMixer({
  required List<InputDef> inputs,
  required List<ConditionDef> conditions,
  required List<MixRule> rules,
  Set<int> disabledChannels = const {},
}) {
  final errors = <String>[], warnings = <String>[];
  final byId = <String, InputDef>{};
  if (inputs.length > InputDef.maxInputs) errors.add('Tối đa ${InputDef.maxInputs} Input');
  for (final i in inputs) {
    final e = i.validate();
    if (e != null) errors.add('Input "${i.name}": $e');
    if (byId.containsKey(i.id)) errors.add('Trùng mã Input "${i.id}"');
    byId[i.id] = i;
  }
  final condIds = <String>{};
  if (conditions.length > ConditionDef.maxConditions) errors.add('Tối đa ${ConditionDef.maxConditions} điều kiện đặt tên');
  for (final c in conditions) {
    if (!condIds.add(c.id)) errors.add('Trùng mã điều kiện "${c.id}"');
  }
  for (final c in conditions) {
    final e = c.expr.validate(byId, condIds);
    if (e != null) errors.add('Điều kiện "${c.name}": $e');
  }
  final cycle = ConditionDef.findRefCycle(conditions);
  if (cycle != null) errors.add('Điều kiện tham chiếu vòng: ${cycle.join(' → ')}');
  if (rules.length > MixRule.maxRules) errors.add('Tối đa ${MixRule.maxRules} luật mix');
  for (var i = 0; i < rules.length; i++) {
    final r = rules[i];
    final e = r.validate(byId, condIds);
    if (e != null) errors.add('Luật ${i + 1}: $e');
    if (r.enabled && disabledChannels.contains(r.destCh)) warnings.add('Luật ${i + 1} ghi vào CH${r.destCh} đang tắt');
  }
  return (errors: errors, warnings: warnings);
}
