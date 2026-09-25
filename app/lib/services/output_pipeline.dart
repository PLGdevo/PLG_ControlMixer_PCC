// Đường tính giá trị gửi đi (B1), chạy trong app mỗi chu kỳ gửi:
// phần tử (%) → giới hạn hộp số (kênh Ga) → mix (G) → reverse → µs quanh Center + trim + offset
// → kẹp [Min, Max]. Xe chỉ nhận kết quả cuối (0.5).
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import 'mix_engine.dart';

class OutputPipeline {
  OutputPipeline(this.profile) : mix = MixEngine(profile.mixes);

  CarProfile profile;
  final MixEngine mix;

  /// Nạp lại hồ sơ sau khi sửa cấu hình (có tác dụng ngay ở chu kỳ tiếp theo)
  void update(CarProfile p) {
    profile = p;
    mix.rules = p.mixes;
  }

  /// Mất kết nối, thoát màn Lái, xe báo failsafe: reset trạng thái hysteresis / select (G3)
  void reset() => mix.reset();

  /// Giá trị % sau hộp số và mix, trước khi đổi sang µs. `input`: 10 kênh, null = chưa gán.
  List<double> mixedPct(List<double?> input, {required int gear}) {
    final pct = List<double>.generate(10, (i) => i < input.length ? (input[i] ?? 0) : 0);
    const thr = CarProfile.throttleCh - 1;
    pct[thr] = pct[thr] * gearLimitPct(gear) / 100;
    return mix.run(pct);
  }

  /// 10 kênh µs gửi xuống xe. Kênh chưa gán và không bị mix ghi vào thì ra Center.
  List<int> run(List<double?> input, {required int gear}) {
    final pct = mixedPct(input, gear: gear);
    return List<int>.generate(10, (i) => toUs(profile.channels[i], pct[i]));
  }

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
}
