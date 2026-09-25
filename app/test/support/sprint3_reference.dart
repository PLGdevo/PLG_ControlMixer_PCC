// Bản đóng băng thuật toán mix của Sprint 3 (models/mix_rule.dart + services/mix_engine.dart +
// OutputPipeline.mixedPct, trước khi đổi sang Input → Condition → Mixer). Chỉ dùng làm chuẩn so sánh
// trong test chuyển hồ sơ (N4); đọc trực tiếp JSON hồ sơ schemaVersion 1.
import 'dart:math';

class Sprint3Rule {
  Sprint3Rule(Map<String, dynamic> j)
      : id = j['id'] as String,
        enabled = j['enabled'] as bool? ?? true,
        type = j['type'] as String? ?? 'threshold',
        sourceCh = j['sourceCh'] as int? ?? 1,
        targetCh = j['targetCh'] as int? ?? 3,
        gateCh = j['gateCh'] as int?,
        mode = j['mode'] as String? ?? 'override',
        onAtPct = _d(j, 'onAtPct', 80),
        offBelowPct = _d(j, 'offBelowPct', 70),
        onValuePct = _d(j, 'onValuePct', 100),
        offValuePct = _d(j, 'offValuePct', 0),
        gainPct = _d(j, 'gainPct', 100),
        offsetPct = _d(j, 'offsetPct', 0),
        curvePts = (j['curvePts'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [-100, -50, 0, 50, 100],
        selectCh = j['selectCh'] as int? ?? 3,
        targetOnCh = j['targetOnCh'] as int? ?? 1,
        targetOffCh = j['targetOffCh'] as int? ?? 4,
        requireNeutral = j['requireNeutralToSwitch'] as bool? ?? true,
        neutralDeadzonePct = _d(j, 'neutralDeadzonePct', 5);

  static double _d(Map<String, dynamic> j, String k, double def) => (j[k] as num?)?.toDouble() ?? def;

  final String id, type, mode;
  final bool enabled, requireNeutral;
  final int sourceCh, targetCh, selectCh, targetOnCh, targetOffCh;
  final int? gateCh;
  final double onAtPct, offBelowPct, onValuePct, offValuePct, gainPct, offsetPct, neutralDeadzonePct;
  final List<double> curvePts;
}

class Sprint3Mixer {
  Sprint3Mixer(Map<String, dynamic> profile)
      : rules = [for (final m in profile['mixes'] as List? ?? const []) Sprint3Rule(m as Map<String, dynamic>)],
        maxThrottle = [for (final g in (profile['gears']['maxThrottle'] as List)) (g as num).toDouble()],
        gearCount = profile['gears']['gearCount'] as int;

  final List<Sprint3Rule> rules;
  final List<double> maxThrottle;
  final int gearCount;
  final Map<String, bool> _thr = {}, _sel = {};

  static double _clamp(double v) => v.clamp(-100.0, 100.0).toDouble();

  static double _curve(List<double> pts, double x) {
    const xs = [-100.0, -50.0, 0.0, 50.0, 100.0];
    final v = _clamp(x);
    for (var i = 0; i < xs.length - 1; i++) {
      if (v <= xs[i + 1]) return pts[i] + (pts[i + 1] - pts[i]) * (v - xs[i]) / (xs[i + 1] - xs[i]);
    }
    return pts.last;
  }

  /// OutputPipeline.mixedPct của Sprint 3: hộp số (CH2) trước, rồi mix. `input`: 10 kênh, null = chưa gán.
  List<double> mixedPct(List<double?> input, {required int gear}) {
    final out = List<double>.generate(10, (i) => i < input.length ? (input[i] ?? 0) : 0);
    out[1] = out[1] * maxThrottle[gear.clamp(1, gearCount) - 1] / 100;
    double get(int ch) => out[ch - 1];
    void put(int ch, double v, String m) {
      final cur = out[ch - 1];
      out[ch - 1] = _clamp(switch (m) { 'add' => cur + v, 'max' => max(cur, v), _ => v });
    }

    for (final r in rules) {
      if (!r.enabled) continue;
      if (r.type != 'select' && r.gateCh != null && get(r.gateCh!) <= 0) {
        _thr[r.id] = false;
        continue;
      }
      final s = get(r.sourceCh);
      switch (r.type) {
        case 'threshold':
          var on = _thr[r.id] ?? false;
          if (s >= r.onAtPct) {
            on = true;
          } else if (s < r.offBelowPct) {
            on = false;
          }
          _thr[r.id] = on;
          put(r.targetCh, on ? r.onValuePct : r.offValuePct, r.mode);
        case 'linear':
          put(r.targetCh, _clamp(s * r.gainPct / 100 + r.offsetPct), r.mode);
        case 'curve':
          put(r.targetCh, _curve(r.curvePts, s), r.mode);
        case 'select':
          final want = get(r.selectCh) > 0;
          var on = _sel[r.id] ?? want;
          if (want != on && (!r.requireNeutral || s.abs() <= r.neutralDeadzonePct)) on = want;
          _sel[r.id] = on;
          final active = on ? r.targetOnCh : r.targetOffCh;
          final idle = on ? r.targetOffCh : r.targetOnCh;
          put(active, s, r.mode);
          out[idle - 1] = 0;
      }
    }
    return out;
  }
}
