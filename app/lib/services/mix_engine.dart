// Thuật toán mix (G2). Mix chạy trong app (G3): cùng một engine dùng cho vòng gửi CONTROL
// (qua OutputPipeline), xem trước (G6) và hiển thị khi lái (G7). Xe không chạy mix (0.5).
import 'dart:collection';
import 'dart:math';

import '../models/mix_rule.dart';

/// Trạng thái của luật chuyển kênh (select) để hiển thị
class SelectState {
  final int activeCh; // kênh đích đang nhận giá trị nguồn
  final bool pending; // nút chọn đã đổi nhưng đang chờ nguồn về giữa
  const SelectState(this.activeCh, this.pending);
}

class MixEngine {
  MixEngine(this.rules);

  List<MixRule> rules;
  final Map<String, bool> _thresholdOn = {};
  final Map<String, bool> _selectOn = {}; // true = đang định tuyến vào targetOnCh
  final Map<String, bool> _selectPending = {};

  bool isOn(String ruleId) => _thresholdOn[ruleId] ?? false;

  SelectState? selectState(String ruleId) {
    final r = rules.where((r) => r.id == ruleId).firstOrNull;
    final on = _selectOn[ruleId];
    if (r == null || on == null) return null;
    return SelectState(on ? r.targetOnCh : r.targetOffCh, _selectPending[ruleId] ?? false);
  }

  void reset() {
    _thresholdOn.clear();
    _selectOn.clear();
    _selectPending.clear();
  }

  static double _clamp(double v) => v.clamp(-100.0, 100.0).toDouble();

  /// Nội suy tuyến tính giữa 5 điểm tại −100, −50, 0, 50, 100
  static double curve(List<double> pts, double x) {
    final v = _clamp(x);
    const xs = MixRule.curveXs;
    for (var i = 0; i < xs.length - 1; i++) {
      if (v <= xs[i + 1]) {
        final t = (v - xs[i]) / (xs[i + 1] - xs[i]);
        return pts[i] + (pts[i + 1] - pts[i]) * t;
      }
    }
    return pts.last;
  }

  /// `input`: 10 kênh theo % (−100…+100), CH1 ở vị trí 0.
  /// Failsafe: bỏ qua mix, reset trạng thái; trả về `failsafePct` nếu có.
  List<double> run(List<double> input, {bool failsafe = false, List<double>? failsafePct}) {
    if (failsafe) {
      reset();
      return List<double>.from(failsafePct ?? input);
    }
    final out = List<double>.from(input);
    double get(int ch) => out[ch - 1];
    void put(int ch, double v, MixMode m) {
      final cur = out[ch - 1];
      out[ch - 1] = _clamp(switch (m) {
        MixMode.override => v,
        MixMode.add => cur + v,
        MixMode.max => max(cur, v),
      });
    }

    for (final r in rules) {
      if (!r.enabled) continue;
      if (r.type != MixType.select && r.gateCh != null && get(r.gateCh!) <= 0) {
        _thresholdOn[r.id] = false; // gate tắt → luật coi như không tồn tại
        continue;
      }
      final s = get(r.sourceCh);
      switch (r.type) {
        case MixType.threshold:
          var on = _thresholdOn[r.id] ?? false;
          if (s >= r.onAtPct) {
            on = true;
          } else if (s < r.offBelowPct) {
            on = false;
          }
          _thresholdOn[r.id] = on;
          put(r.targetCh, on ? r.onValuePct : r.offValuePct, r.mode);
        case MixType.linear:
          put(r.targetCh, _clamp(s * r.gainPct / 100 + r.offsetPct), r.mode);
        case MixType.curve:
          put(r.targetCh, curve(r.curvePts, s), r.mode);
        case MixType.select:
          final want = get(r.selectCh) > 0;
          var on = _selectOn[r.id] ?? want;
          if (want != on && (!r.requireNeutralToSwitch || s.abs() <= r.neutralDeadzonePct)) on = want;
          _selectOn[r.id] = on;
          _selectPending[r.id] = want != on;
          final active = on ? r.targetOnCh : r.targetOffCh;
          final idle = on ? r.targetOffCh : r.targetOnCh;
          put(active, s, r.mode);
          out[idle - 1] = 0;
      }
    }
    return out;
  }
}
