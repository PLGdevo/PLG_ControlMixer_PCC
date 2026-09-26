import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/services/output_pipeline.dart';

// Đường tính giá trị gửi đi (Sprint 4 — 0.2, O2)
void main() {
  CarProfile profile() => CarProfile(id: 'p', name: 'p', connType: ConnType.wifi);

  List<int> run(OutputPipeline pipe, {double steer = 0, double thr = 0}) {
    pipe.inputs
      ..setPosition('steer', steer)
      ..setPosition('throttle', thr);
    return pipe.run();
  }

  test('kênh không có luật ra Center, kênh tắt ra failsafe', () {
    final p = profile();
    p.ch(3).enabled = true;
    p.ch(4).failsafeUs = 1000;
    final out = run(OutputPipeline(p));
    expect(out.take(3), [1500, 1500, 1500]);
    expect(out[3], 1000); // CH4 tắt
    expect(OutputPipeline(p).failsafeUs()[3], 1000);
  });

  test('đổi % sang µs quanh Center, reverse đảo chiều', () {
    final p = profile();
    final pipe = OutputPipeline(p);
    expect(run(pipe, steer: 100)[0], 1900); // CH1 Lái: 1100/1500/1900
    expect(run(pipe, steer: -50)[0], 1300);
    p.ch(1).reverse = true;
    expect(run(pipe, steer: 100)[0], 1100);
  });

  test('trim + offset dời tâm, kết quả luôn kẹp trong [Min, Max]', () {
    final p = profile();
    p.ch(1).trimUs = 20;
    final pipe = OutputPipeline(p);
    expect(run(pipe)[0], 1520);
    expect(run(pipe, steer: 100)[0], 1900);
    p.ch(2).offsetUs = 300;
    p.ch(2).trimUs = 200; // tâm 2000 > Max → kẹp
    expect(run(pipe)[1], 2000);
    expect(run(pipe, thr: -100)[1], 1000);
  });

  test('không có hộp số: kênh Ga ra đủ hành trình', () {
    final pipe = OutputPipeline(profile());
    final out = run(pipe, steer: 100, thr: 100);
    expect(out[1], 2000);
    expect(out[0], 1900);
    expect(run(pipe, thr: -100)[1], 1000);
  });

  test('hồ sơ không có kênh Ga: cần ga luôn coi là ở vị trí nghỉ', () {
    final p = profile()..throttleCh = null;
    final pipe = OutputPipeline(p);
    pipe.inputs.setPosition('throttle', 80);
    expect(pipe.throttleAtRest(p.activeLayout), isTrue); // không có kênh Ga để kiểm tra
  });

  test('luật mix: ga vào CH4; điều kiện có trễ vào CH3; reset trạng thái', () {
    final p = profile()
      ..inputs.add(InputDef(id: 'k100', name: '100', type: InputType.constant, constPct: 100))
      ..mixer.addAll([
        MixRule(id: 'a', source: 'k100', destCh: 3,
            condition: const ExprCmp(input: 'steer', op: CmpOp.ge, value: 80, hyst: 10)),
        MixRule(id: 'b', source: 'throttle', destCh: 4),
      ]);
    p.ch(3).enabled = true;
    p.ch(4).enabled = true;
    final pipe = OutputPipeline(p);
    final out = run(pipe, steer: 90, thr: 100);
    expect(out[2], 2000); // steer ≥ 80 → CH3 = 100%
    expect(out[3], 2000); // CH4 lấy ga
    expect(out[1], 2000); // CH2 (Ga)
    expect(run(pipe, steer: 75)[2], 2000); // vùng giữ
    pipe.reset();
    expect(run(pipe, steer: 75)[2], 1500); // reset hysteresis → không tác động → Center
  });

  test('sửa hồ sơ có tác dụng ngay ở chu kỳ tiếp theo, giữ vị trí Input', () {
    final p = profile()..ch(3).enabled = true;
    final pipe = OutputPipeline(p);
    expect(run(pipe, steer: 40)[2], 1500);
    final q = profile()
      ..ch(3).enabled = true
      ..mixer.add(MixRule(id: 'c', source: 'steer', destCh: 3, offsetPct: 10));
    pipe.update(q);
    expect(pipe.run()[2], 1750); // steer 40 giữ nguyên + 10 = 50%
  });

  test('vị trí nghỉ của Ga theo vị trí về đã cài (R2, H5-1)', () {
    final p = profile();
    final stick = p.activeLayout.itemForInput('throttle')!;
    stick.returnCfg!.targetPct = -28;
    final pipe = OutputPipeline(p);
    expect(pipe.restPct(p.throttleCh!, p.activeLayout), -28);
    pipe.inputs.setPosition('throttle', -28);
    expect(pipe.throttleAtRest(p.activeLayout), isTrue);
    pipe.inputs.setPosition('throttle', 40);
    expect(pipe.throttleAtRest(p.activeLayout), isFalse);
  });
}
