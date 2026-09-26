// Đường tính giá trị gửi đi (Sprint 4 — 0.2, O2), chạy trong app mỗi chu kỳ gửi:
// Input → Condition → Mixer (%) → hộp số (kênh Ga) → reverse → µs quanh Center + trim + offset
// → kẹp [Min, Max]. Kênh tắt ra failsafeUs. Xe chỉ nhận kết quả cuối (0.5).
import 'dart:typed_data';

import '../layout/return_motion.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/control_layout.dart';
import '../models/input_def.dart';
import 'input_manager.dart';
import 'mixer_engine.dart';

class OutputPipeline {
  OutputPipeline(CarProfile p)
      : profile = p,
        inputs = InputManager(p.inputs),
        _restInputs = InputManager(p.inputs) {
    mixer = MixerEngine(inputs, conditions: p.conditions, rules: p.mixer);
    _restMixer = MixerEngine(_restInputs, conditions: p.conditions, rules: p.mixer);
  }

  CarProfile profile;
  final InputManager inputs;
  late final MixerEngine mixer;
  final InputManager _restInputs;
  late final MixerEngine _restMixer;

  /// Kết quả mixer của chu kỳ gần nhất (10 kênh %, CH1 ở vị trí 0)
  Float64List get lastPct => mixer.out;

  /// Nạp lại hồ sơ sau khi sửa cấu hình (có tác dụng ngay ở chu kỳ tiếp theo). Giữ trạng thái Input.
  void update(CarProfile p) {
    profile = p;
    inputs.load(p.inputs);
    mixer.load(conditions: p.conditions, rules: p.mixer);
    _restInputs.load(p.inputs);
    _restMixer.load(conditions: p.conditions, rules: p.mixer);
  }

  /// Mất kết nối, DISARM, thoát màn Lái, xe báo failsafe: reset hysteresis / khoá an toàn (M4, K2)
  void reset() => mixer.reset();

  /// Chạy mixer một chu kỳ: 10 kênh % (−100…+100)
  Float64List mixed() => mixer.run();

  /// Chạy một chu kỳ và đổi sang 10 kênh µs gửi xuống xe
  List<int> run({required int gear}) => toUsList(mixed(), gear: gear);

  /// % sau mixer → µs (O2): hộp số áp lên kênh Ga sau mixer; kênh tắt ra failsafeUs
  List<int> toUsList(List<double> pct, {required int gear}) => List<int>.generate(10, (i) {
        final ch = profile.channels[i];
        if (!ch.enabled) return ch.failsafeUs;
        return toUs(ch, gearedPct(pct, i + 1, gear: gear));
      });

  /// % của kênh `ch` sau hộp số: chỉ kênh Ga đã chọn bị giới hạn, hồ sơ không có kênh Ga thì giữ nguyên
  double gearedPct(List<double> pct, int ch, {required int gear}) {
    final p = pct[ch - 1];
    return ch == profile.throttleCh ? p * gearLimitPct(gear) / 100 : p;
  }

  /// Failsafe của 10 kênh (READY gửi giá trị này — R1)
  List<int> failsafeUs() => [for (final c in profile.channels) c.failsafeUs];

  double gearLimitPct(int gear) {
    final g = profile.gears;
    final n = gear.clamp(1, g.gearCount).toInt();
    return g.maxThrottle[n - 1].toDouble();
  }

  /// % (−100…+100) → µs: reverse, nội suy quanh tâm thực tế (Center + trim + offset), kẹp [Min, Max]
  static int toUs(ChannelConfig ch, double pct) {
    var p = pct.clamp(-100.0, 100.0).toDouble();
    if (ch.reverse) p = -p;
    final center = ch.effectiveCenter;
    final us = p >= 0 ? center + p / 100 * (ch.maxUs - center) : center + p / 100 * (center - ch.minUs);
    return us.round().clamp(ch.minUs, ch.maxUs).toInt();
  }

  /// Giá trị % của kênh `ch` khi mọi cần gạt trên bố cục ở vị trí nghỉ (R2, H5).
  /// Nút / công tắc giữ trạng thái hiện tại, riêng nút nhấn giữ coi như đã thả.
  double restPct(int ch, ControlLayout layout) {
    for (final d in _restInputs.defs) {
      if (d.isAxis) {
        _restInputs.setPosition(d.id, ReturnMotion.restPct(layout, d.id, isThrottle: profile.isThrottleInput(d.id)));
      } else if (d.type != InputType.constant) {
        final momentary = layout.itemForInput(d.id)?.kind == ItemKind.button;
        _restInputs.setState(d.id, momentary ? d.restState : inputs.stateOf(d.id));
      }
    }
    _restMixer.reset();
    return _restMixer.run()[ch - 1];
  }

  /// Kênh Ga đang ở vị trí nghỉ (sai số ±5%); hồ sơ không có kênh Ga thì luôn đúng. Tính lại mixer
  /// với Input hiện tại (tính lặp với cùng đầu vào không đổi trạng thái trễ / khoá an toàn).
  bool throttleAtRest(ControlLayout layout) {
    final ch = profile.throttleCh;
    if (ch == null) return true;
    return (mixed()[ch - 1] - restPct(ch, layout)).abs() <= 5;
  }
}
