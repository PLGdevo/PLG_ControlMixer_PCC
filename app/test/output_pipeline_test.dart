import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/mix_rule.dart';
import 'package:rc_controller/services/output_pipeline.dart';

// Đường tính giá trị gửi đi (B1)
void main() {
  CarProfile profile() => CarProfile(id: 'p', name: 'p', connType: ConnType.wifi);

  List<double?> input({double? steer, double? thr}) {
    final v = List<double?>.filled(10, null);
    v[CarProfile.steeringCh - 1] = steer;
    v[CarProfile.throttleCh - 1] = thr;
    return v;
  }

  test('kênh chưa gán và không bị mix ghi vào thì ra Center', () {
    final out = OutputPipeline(profile()).run(input(), gear: 3);
    expect(out, List.filled(10, 1500));
  });

  test('đổi % sang µs quanh Center, reverse đảo chiều', () {
    final p = profile();
    final pipe = OutputPipeline(p);
    expect(pipe.run(input(steer: 100), gear: 3)[0], 1900); // CH1 Lái: 1100/1500/1900
    expect(pipe.run(input(steer: -50), gear: 3)[0], 1300);
    p.steering.reverse = true;
    expect(pipe.run(input(steer: 100), gear: 3)[0], 1100);
  });

  test('trim + offset dời tâm, kết quả luôn kẹp trong [Min, Max]', () {
    final p = profile();
    p.steering.trimUs = 20;
    final pipe = OutputPipeline(p);
    expect(pipe.run(input(steer: 0), gear: 3)[0], 1520);
    expect(pipe.run(input(steer: 100), gear: 3)[0], 1900);
    p.throttle.offsetUs = 300;
    p.throttle.trimUs = 200; // tâm 2000 > Max → kẹp
    expect(pipe.run(input(thr: 0), gear: 3)[1], 2000);
    expect(pipe.run(input(thr: -100), gear: 3)[1], 1000);
  });

  test('hộp số giới hạn kênh Ga, không đụng kênh khác', () {
    final pipe = OutputPipeline(profile()); // số 1 = 30%
    final out = pipe.run(input(steer: 100, thr: 100), gear: 1);
    expect(out[1], 1650);
    expect(out[0], 1900);
    expect(pipe.run(input(thr: -100), gear: 1)[1], 1350);
    expect(pipe.run(input(thr: 100), gear: 9)[1], 2000); // số vượt gearCount → số cao nhất
  });

  test('mix chạy sau hộp số, ghi vào kênh chưa gán', () {
    final p = profile()
      ..mixes = [
        MixRule(id: 'a', type: MixType.threshold, sourceCh: 1, targetCh: 3),
        MixRule(id: 'b', type: MixType.linear, sourceCh: 2, targetCh: 4),
      ];
    final pipe = OutputPipeline(p);
    final out = pipe.run(input(steer: 90, thr: 100), gear: 1);
    expect(out[2], 2000); // CH1 ≥ 80% → CH3 = 100%
    expect(out[3], 1650); // CH4 = ga sau hộp số (30%)
    expect(pipe.run(input(steer: 75), gear: 1)[2], 2000); // vùng giữ
    pipe.reset();
    expect(pipe.run(input(steer: 75), gear: 1)[2], 1500); // reset hysteresis → TẮT
  });

  test('sửa hồ sơ có tác dụng ngay ở chu kỳ tiếp theo', () {
    final p = profile();
    final pipe = OutputPipeline(p);
    expect(pipe.run(input(), gear: 1)[2], 1500);
    final q = profile()..mixes = [MixRule(id: 'c', type: MixType.linear, sourceCh: 1, targetCh: 3, offsetPct: 50)];
    pipe.update(q);
    expect(pipe.run(input(), gear: 1)[2], 1750);
  });
}
