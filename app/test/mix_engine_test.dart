import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/models/mix_rule.dart';
import 'package:rc_controller/services/mix_engine.dart';

List<double> input({double ch1 = 0, double ch2 = 0, double ch3 = 0, double ch4 = 0}) {
  final v = List<double>.filled(10, 0);
  v[0] = ch1;
  v[1] = ch2;
  v[2] = ch3;
  v[3] = ch4;
  return v;
}

void main() {
  group('Ngưỡng có hysteresis (G2a)', () {
    MixRule rule() => MixRule(
          id: 'r',
          type: MixType.threshold,
          sourceCh: 1,
          targetCh: 3,
          onAtPct: 80,
          offBelowPct: 70,
          onValuePct: 100,
          offValuePct: 0,
        );

    test('bảng ví dụ trong đặc tả', () {
      final e = MixEngine([rule()]);
      double ch3(double ch1) => e.run(input(ch1: ch1))[2];
      expect(ch3(0), 0);
      expect(ch3(75), 0); // chưa chạm 80
      expect(ch3(82), 100);
      expect(ch3(72), 100); // vẫn ≥ 70, giữ
      expect(ch3(69), 0);
      expect(ch3(78), 0); // chưa chạm 80, giữ
    });

    test('dao động trong vùng giữ không đổi trạng thái', () {
      final e = MixEngine([rule()]);
      e.run(input(ch1: 85));
      for (final v in [79.0, 71.0, 75.0, 70.0, 79.9]) {
        expect(e.run(input(ch1: v))[2], 100, reason: 'CH1 = $v');
      }
    });

    test('failsafe giữa chừng reset trạng thái', () {
      final e = MixEngine([rule()]);
      e.run(input(ch1: 90));
      expect(e.isOn('r'), isTrue);
      final fs = List<double>.filled(10, -100);
      expect(e.run(input(ch1: 90), failsafe: true, failsafePct: fs), fs);
      expect(e.isOn('r'), isFalse);
      expect(e.run(input(ch1: 75))[2], 0);
    });

    test('gate tắt thì luật không chạy và reset về TẮT', () {
      final r = rule()..gateCh = 4;
      final e = MixEngine([r]);
      expect(e.run(input(ch1: 90, ch4: 100))[2], 100);
      expect(e.run(input(ch1: 90, ch4: -100))[2], 0); // không có luật → giữ giá trị gốc CH3 = 0
      expect(e.isOn('r'), isFalse);
      expect(e.run(input(ch1: 75, ch4: 100))[2], 0); // bật gate lại: 75 < 80 → TẮT
    });
  });

  group('Chế độ ghi', () {
    MixRule lin(MixMode m) =>
        MixRule(id: 'l', type: MixType.linear, sourceCh: 1, targetCh: 2, gainPct: 50, offsetPct: 0, mode: m);

    test('override / add / max', () {
      expect(MixEngine([lin(MixMode.override)]).run(input(ch1: 80, ch2: 30))[1], 40);
      expect(MixEngine([lin(MixMode.add)]).run(input(ch1: 80, ch2: 30))[1], 70);
      expect(MixEngine([lin(MixMode.add)]).run(input(ch1: 100, ch2: 90))[1], 100); // kẹp
      expect(MixEngine([lin(MixMode.max)]).run(input(ch1: 80, ch2: 30))[1], 40);
      expect(MixEngine([lin(MixMode.max)]).run(input(ch1: 20, ch2: 30))[1], 30);
    });

    test('luật sau nhận kết quả luật trước', () {
      final a = MixRule(id: 'a', type: MixType.linear, sourceCh: 1, targetCh: 2, gainPct: 100);
      final b = MixRule(id: 'b', type: MixType.linear, sourceCh: 2, targetCh: 3, gainPct: 50);
      expect(MixEngine([a, b]).run(input(ch1: 60))[2], 30);
    });

    test('đường cong nội suy 5 điểm', () {
      final pts = [-100.0, -20.0, 0.0, 20.0, 100.0];
      expect(MixEngine.curve(pts, 25), 10);
      expect(MixEngine.curve(pts, 75), 60);
      expect(MixEngine.curve(pts, -100), -100);
    });
  });

  group('Chuyển kênh (select) có khoá an toàn', () {
    MixRule sel() => MixRule(
          id: 's',
          type: MixType.select,
          sourceCh: 2,
          selectCh: 3,
          targetOnCh: 1,
          targetOffCh: 4,
        );

    test('nút tắt → vào đích TẮT, đích còn lại 0%', () {
      final out = MixEngine([sel()]).run(input(ch2: 50, ch3: -100));
      expect(out[3], 50);
      expect(out[0], 0);
    });

    test('đổi nút khi nguồn lệch tâm thì giữ đích cũ tới khi về giữa', () {
      final e = MixEngine([sel()]);
      e.run(input(ch2: 0, ch3: -100));
      var out = e.run(input(ch2: 60, ch3: -100));
      expect(out[3], 60);
      out = e.run(input(ch2: 60, ch3: 100)); // bấm nút A khi ga 60%
      expect(out[3], 60);
      expect(out[0], 0);
      expect(e.selectState('s')!.pending, isTrue);
      out = e.run(input(ch2: 30, ch3: 100));
      expect(out[3], 30);
      out = e.run(input(ch2: 4, ch3: 100)); // về vùng chết 5% → chuyển
      expect(out[0], 4);
      expect(out[3], 0);
      expect(e.selectState('s')!.pending, isFalse);
    });

    test('đổi nút khi nguồn ở vùng chết thì chuyển ngay', () {
      final e = MixEngine([sel()]);
      e.run(input(ch2: 0, ch3: -100));
      final out = e.run(input(ch2: 3, ch3: 100));
      expect(out[0], 3);
      expect(out[3], 0);
    });

    test('failsafe huỷ trạng thái chờ chuyển', () {
      final e = MixEngine([sel()]);
      e.run(input(ch2: 60, ch3: -100));
      e.run(input(ch2: 60, ch3: 100));
      expect(e.selectState('s')!.pending, isTrue);
      e.run(input(), failsafe: true);
      expect(e.selectState('s'), isNull);
      final out = e.run(input(ch2: 60, ch3: 100)); // sau failsafe theo nút ngay
      expect(out[0], 60);
    });
  });

  group('Kiểm tra luật (G4)', () {
    test('phát hiện vòng lặp', () {
      final a = MixRule(id: 'a', type: MixType.linear, sourceCh: 1, targetCh: 3);
      final b = MixRule(id: 'b', type: MixType.linear, sourceCh: 3, targetCh: 1);
      expect(MixRule.findCycle([a, b]), isNotNull);
      expect(MixRule.validateAll([a, b]), contains('vòng lặp'));
      final c = MixRule(id: 'c', type: MixType.linear, sourceCh: 3, targetCh: 5);
      final d = MixRule(id: 'd', type: MixType.linear, sourceCh: 5, targetCh: 1);
      expect(MixRule.findCycle([a, c, d]), isNotNull);
      expect(MixRule.findCycle([a, c]), isNull);
    });

    test('select góp hai cạnh vào đồ thị', () {
      final s = MixRule(id: 's', type: MixType.select, sourceCh: 2, selectCh: 3, targetOnCh: 1, targetOffCh: 4);
      final back = MixRule(id: 'x', type: MixType.linear, sourceCh: 4, targetCh: 2);
      expect(MixRule.findCycle([s, back]), isNotNull);
    });

    test('nguồn trùng đích, ngưỡng ngược, select trùng kênh', () {
      expect(MixRule(id: 'a', sourceCh: 2, targetCh: 2).validate(), isNotNull);
      expect(MixRule(id: 'a', onAtPct: 60, offBelowPct: 70).validate(), isNotNull);
      expect(
        MixRule(id: 'a', type: MixType.select, sourceCh: 2, selectCh: 3, targetOnCh: 3, targetOffCh: 4).validate(),
        isNotNull,
      );
    });
  });

  group('Nhiều luật chạy đồng thời (G1)', () {
    // 10 luật, đủ 4 loại; CH1 và CH2 là nguồn chung, CH3/CH4/CH8 là đích chung
    List<MixRule> tenRules() => [
          MixRule(id: 'r1', type: MixType.threshold, sourceCh: 1, targetCh: 3),
          MixRule(id: 'r2', type: MixType.linear, sourceCh: 1, targetCh: 4, gainPct: 50),
          MixRule(id: 'r3', type: MixType.curve, sourceCh: 2, targetCh: 7, curvePts: [-100, -50, 0, 20, 100]),
          MixRule(id: 'r4', type: MixType.linear, sourceCh: 2, targetCh: 4, gainPct: 10, mode: MixMode.add),
          MixRule(id: 'r5', sourceCh: 2, targetCh: 8, gateCh: 5, onAtPct: 50, offBelowPct: 40,
              onValuePct: 80, offValuePct: -80),
          MixRule(id: 'r6', sourceCh: 2, targetCh: 9, gateCh: 6, onAtPct: 0, offBelowPct: 0),
          MixRule(id: 'r7', type: MixType.select, sourceCh: 2, selectCh: 5, targetOnCh: 10, targetOffCh: 9),
          MixRule(id: 'r8', type: MixType.linear, sourceCh: 1, targetCh: 3, gainPct: 50, mode: MixMode.max),
          MixRule(id: 'r9', type: MixType.linear, sourceCh: 7, targetCh: 8, gainPct: 50, mode: MixMode.add),
          MixRule(id: 'r10', sourceCh: 4, targetCh: 3, onAtPct: 50, offBelowPct: 40,
              onValuePct: -50, offValuePct: 0, mode: MixMode.add),
        ];

    List<double> ins() {
      final v = List<double>.filled(10, 0);
      v[0] = 90; // CH1
      v[1] = 60; // CH2
      v[4] = 100; // CH5: nút bật (gate r5, chọn r7)
      v[5] = -100; // CH6: nút tắt (gate r6)
      return v;
    }

    test('10 luật cùng bật cho kết quả đúng trong một chu kỳ', () {
      final rules = tenRules();
      expect(MixRule.validateAll(rules), isNull);
      final out = MixEngine(rules).run(ins());
      expect(out[2], 50); // CH3: r1 = 100 → r8 max(100, 45) → r10 +(−50)
      expect(out[3], 51); // CH4: r2 = 45 → r4 +6
      expect(out[6], closeTo(36, 1e-9)); // CH7: đường cong tại 60
      expect(out[7], closeTo(98, 1e-9)); // CH8: r5 = 80 (gate bật) → r9 +18
      expect(out[8], 0); // CH9: r6 bị gate tắt; r7 đưa đích không active về 0
      expect(out[9], 60); // CH10: r7 định tuyến ga vào đích ON
    });

    test('20 luật chạy trong ≤ 2 ms mỗi chu kỳ', () {
      final rules = [
        ...tenRules(),
        for (var i = 0; i < 10; i++)
          MixRule(id: 'x$i', type: MixType.linear, sourceCh: 1, targetCh: 4, gainPct: 1, mode: MixMode.add),
      ];
      expect(rules.length, MixRule.maxRules);
      expect(MixRule.validateAll(rules), isNull);
      final e = MixEngine(rules);
      final input = ins();
      for (var i = 0; i < 200; i++) {
        e.run(input); // làm nóng JIT
      }
      const cycles = 2000;
      final sw = Stopwatch()..start();
      for (var i = 0; i < cycles; i++) {
        input[0] = (i % 200) - 100.0;
        e.run(input);
      }
      sw.stop();
      expect(sw.elapsedMicroseconds / cycles, lessThan(2000));
    });

    test('tối đa 20 luật', () {
      final r = List.generate(
          21, (i) => MixRule(id: 'l$i', type: MixType.linear, sourceCh: 1, targetCh: 2, mode: MixMode.add));
      expect(MixRule.validateAll(r.take(20).toList()), isNull);
      expect(MixRule.validateAll(r), 'Tối đa 20 luật mix');
    });
  });
}
