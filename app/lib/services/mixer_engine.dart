// Mixer (Sprint 4 — M2–M5): Input → Condition → Weight/Offset/Curve/Min–Max → gộp theo priority
// → CH1…CH10 (%). Cùng một engine cho vòng gửi CONTROL, xem trước và hiển thị khi lái.
import 'dart:typed_data';

import '../models/condition.dart';
import '../models/input_def.dart';
import '../models/mixer_rule.dart';
import 'condition_engine.dart';
import 'input_manager.dart';

class _Compiled {
  _Compiled(this.rule, this.order, this.src, this.cond, this.needNeutral);
  final MixRule rule;
  final int order; // vị trí trong danh sách
  final int src; // chỉ số Input
  final CondNode cond;
  final bool needNeutral;
  int latched = -1; // −1 chưa có, 0 không active, 1 active
  bool active = false, pending = false;
}

class MixerEngine {
  static const channelCount = 10;

  MixerEngine(this.inputs, {List<ConditionDef> conditions = const [], List<MixRule> rules = const []}) {
    load(conditions: conditions, rules: rules);
  }

  final InputManager inputs;
  late ConditionEngine conditions;
  List<_Compiled> _rules = const []; // đã sắp theo (priority, thứ tự danh sách)
  final Map<String, _Compiled> _byId = {};
  final Float64List out = Float64List(channelCount);
  final List<bool> _set = List<bool>.filled(channelCount, false);

  /// Biên dịch lại sau khi sửa Input / Condition / luật. Gọi sau `inputs.load(...)`.
  void load({required List<ConditionDef> conditions, required List<MixRule> rules}) {
    this.conditions = ConditionEngine(inputs.index, conditions);
    _byId.clear();
    final list = <_Compiled>[];
    for (var i = 0; i < rules.length; i++) {
      final r = rules[i];
      final src = inputs.indexOf(r.source);
      if (!r.enabled || src < 0 || r.destCh < 1 || r.destCh > channelCount) continue;
      final c = _Compiled(r, i, src, this.conditions.compile(r.condition), r.requiresNeutral(inputs.defs[src]));
      list.add(c);
      _byId[r.id] = c;
    }
    list.sort((a, b) {
      final p = a.rule.priority.compareTo(b.rule.priority);
      return p != 0 ? p : a.order.compareTo(b.order);
    });
    _rules = list;
  }

  /// Tính một chu kỳ. Trả về 10 kênh % (−100…+100), CH1 ở vị trí 0. Không cấp phát.
  Float64List run() {
    conditions.beginCycle();
    final st = inputs.state, val = inputs.value;
    for (var i = 0; i < channelCount; i++) {
      out[i] = 0;
      _set[i] = false;
    }
    for (final c in _rules) {
      final want = conditions.eval(c.cond, st); // luôn tính để trạng thái trễ được cập nhật
      final w = want ? 1 : 0;
      if (c.latched < 0) {
        c.latched = w;
      } else if (w != c.latched) {
        // Khoá an toàn (M4): nguồn lệch tâm thì giữ trạng thái cũ tới khi về vùng chết
        if (!c.needNeutral || val[c.src].abs() <= c.rule.safety.deadzonePct) c.latched = w;
      }
      c.pending = w != c.latched;
      c.active = c.latched == 1;
      if (!c.active) continue;

      final r = c.rule;
      var v = val[c.src] * r.weightPct / 100 + r.offsetPct;
      if (!r.curve.isLinear) v = r.curve.apply(v);
      if (v < r.minPct) v = r.minPct;
      if (v > r.maxPct) v = r.maxPct;

      final k = r.destCh - 1;
      if (!_set[k]) {
        if (r.combine == Combine.multiply) continue; // nhân vào kênh chưa có giá trị: giữ chưa có
        out[k] = v;
        _set[k] = true;
        continue;
      }
      final cur = out[k];
      out[k] = switch (r.combine) {
        Combine.replace => v,
        Combine.add => cur + v,
        Combine.multiply => cur * v / 100,
        Combine.max => v > cur ? v : cur,
        Combine.min => v < cur ? v : cur,
      };
    }
    for (var i = 0; i < channelCount; i++) {
      final v = out[i];
      out[i] = v > 100 ? 100 : (v < -100 ? -100 : v); // kênh chưa có giá trị = 0% (Center)
    }
    return out;
  }

  bool isActive(String ruleId) => _byId[ruleId]?.active ?? false;
  bool isPending(String ruleId) => _byId[ruleId]?.pending ?? false;
  Set<String> get activeRuleIds => {for (final c in _rules) if (c.active) c.rule.id};
  Set<String> get pendingRuleIds => {for (final c in _rules) if (c.pending) c.rule.id};

  /// Các luật đang tác động lên kênh `ch` (cho chấm mix / nhấn giữ — U6)
  List<MixRule> activeRulesFor(int ch) => [for (final c in _rules) if (c.active && c.rule.destCh == ch) c.rule];

  /// Các luật đang dùng Input `inputId` làm nguồn hoặc trong điều kiện
  List<MixRule> rulesUsing(String inputId) => [
        for (final c in _rules)
          if (c.rule.source == inputId || c.rule.condition.inputs.contains(inputId)) c.rule,
      ];

  /// Hysteresis + khoá an toàn về ban đầu (M4, K2)
  void reset() {
    conditions.reset();
    for (final c in _rules) {
      c.latched = -1;
      c.active = false;
      c.pending = false;
    }
  }

  InputDef? sourceOf(MixRule r) => inputs.def(r.source);
}
