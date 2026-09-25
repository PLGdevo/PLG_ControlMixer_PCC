// N2, N6: MixerEngine — gộp theo priority, khoá an toàn khi đổi đích, curve, hiệu năng.
import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/services/input_manager.dart';
import 'package:rc_controller/services/mixer_engine.dart';

List<InputDef> defs() => [
      InputDef(id: 'steer', name: 'Lái'),
      InputDef(id: 'throttle', name: 'Ga'),
      InputDef(id: 'slider_x', name: 'Slider X'),
      InputDef(id: 'uni', name: 'Uni', range: AxisRange.unipolar),
      InputDef(id: 'btn_a', name: 'Nút A', type: InputType.binary),
      InputDef(id: 'btn_stop', name: 'Dừng', type: InputType.binary),
      InputDef(id: 'k100', name: '100', type: InputType.constant, constPct: 100),
      InputDef(id: 'k0', name: '0', type: InputType.constant, constPct: 0),
      InputDef(id: 'k30', name: '30', type: InputType.constant, constPct: 30),
    ];

Expr eq(String i, double v) => ExprCmp(input: i, op: CmpOp.eq, value: v);

void main() {
  late InputManager im;
  MixerEngine engine(List<MixRule> rules, {List<ConditionDef> conds = const []}) {
    im = InputManager(defs());
    return MixerEngine(im, conditions: conds, rules: rules);
  }

  test('kênh không có luật = 0%; luật không điều kiện chép nguồn', () {
    final e = engine([MixRule(id: 'r', source: 'steer', destCh: 1)]);
    im.setPosition('steer', 42);
    final out = e.run();
    expect(out[0], 42);
    expect(out.sublist(1), everyElement(0));
  });

  test('weight → offset → curve → min/max', () {
    final e = engine([
      MixRule(id: 'r', source: 'steer', destCh: 1, weightPct: 50, offsetPct: 10, minPct: -20, maxPct: 30),
      MixRule(id: 'c', source: 'steer', destCh: 2, curve: MixCurve(type: CurveType.points, points: [-100, -20, 0, 20, 100])),
    ]);
    im.setPosition('steer', 40);
    expect(e.run()[0], 30); // 40×50% + 10 = 30
    im.setPosition('steer', 80);
    expect(e.run()[0], 30); // 50 → kẹp Max 30
    im.setPosition('steer', -100);
    final out = e.run();
    expect(out[0], -20); // −40 → kẹp Min −20
    im.setPosition('steer', 25);
    expect(e.run()[1], closeTo(10, 1e-9)); // nội suy giữa (0,0) và (50,20)
  });

  test('expo: giữ đầu mút, mềm quanh tâm khi dương, gắt khi âm', () {
    final soft = MixCurve(type: CurveType.expo, expoPct: 50), hard = MixCurve(type: CurveType.expo, expoPct: -50);
    for (final c in [soft, hard]) {
      expect(c.apply(100), closeTo(100, 1e-9));
      expect(c.apply(-100), closeTo(-100, 1e-9));
      expect(c.apply(0), 0);
    }
    expect(soft.apply(50), lessThan(50));
    expect(hard.apply(50), greaterThan(50));
  });

  group('gộp nhiều luật vào một kênh (M3)', () {
    MixerEngine two(Combine c) => engine([
          MixRule(id: 'a', source: 'throttle', destCh: 1),
          MixRule(id: 'b', source: 'steer', destCh: 1, weightPct: 30, combine: c),
        ]);

    test('replace / add / multiply / max / min', () {
      final expected = {
        Combine.replace: 15.0,
        Combine.add: 75.0,
        Combine.multiply: 60 * 15 / 100,
        Combine.max: 60.0,
        Combine.min: 15.0,
      };
      expected.forEach((c, v) {
        final e = two(c);
        im.setPosition('throttle', 60);
        im.setPosition('steer', 50);
        expect(e.run()[0], closeTo(v, 1e-9), reason: c.name);
      });
    });

    test('multiply vào kênh chưa có giá trị giữ nguyên chưa có (0%)', () {
      final e = engine([MixRule(id: 'm', source: 'steer', destCh: 3, combine: Combine.multiply)]);
      im.setPosition('steer', 70);
      expect(e.run()[2], 0);
    });

    test('add vượt 100 bị kẹp ở cuối', () {
      final e = two(Combine.add);
      im.setPosition('throttle', 90);
      im.setPosition('steer', 100);
      expect(e.run()[0], 100);
    });

    test('priority cao chạy sau: luật khẩn cấp replace đè mọi thứ', () {
      final e = engine([
        MixRule(id: 'stop', source: 'k0', destCh: 2, condition: eq('btn_stop', 1), priority: 9),
        MixRule(id: 'thr', source: 'throttle', destCh: 2),
        MixRule(id: 'mix', source: 'steer', destCh: 2, weightPct: 30, combine: Combine.add),
      ]);
      im.setPosition('throttle', 100);
      im.setPosition('steer', 50);
      expect(e.run()[1], 100); // 100 + 15 → kẹp 100
      im.setSwitch('btn_stop', 1);
      expect(e.run()[1], 0);
      expect(e.isActive('stop'), isTrue);
    });
  });

  group('khoá an toàn khi đổi đích (M4) — A / Slider X', () {
    List<MixRule> rules({bool neutral = true}) => [
          MixRule(id: 'r_ch1', source: 'slider_x', destCh: 1, condition: eq('btn_a', 1),
              safety: SwitchSafety(requireNeutral: neutral)),
          MixRule(id: 'r_ch8', source: 'slider_x', destCh: 8, condition: eq('btn_a', 0),
              safety: SwitchSafety(requireNeutral: neutral)),
        ];

    test('bảng trong đặc tả, từng bước', () {
      final e = engine(rules());
      (double, double) step(int a, double x) {
        im.setSwitch('btn_a', a);
        im.setPosition('slider_x', x);
        final o = e.run();
        return (o[0], o[7]);
      }

      expect(step(1, 70), (70, 0));
      expect(step(0, 70), (70, 0)); // chờ về giữa
      expect(e.pendingRuleIds, {'r_ch1', 'r_ch8'});
      expect(step(0, 30), (30, 0)); // vẫn chờ
      expect(step(0, 3), (0, 3)); // về vùng chết → chuyển
      expect(e.pendingRuleIds, isEmpty);
      expect(step(0, 70), (0, 70));
    });

    test('không có chu kỳ nào kênh mới nhận giá trị lệch tâm đột ngột', () {
      final e = engine(rules());
      im.setSwitch('btn_a', 1);
      im.setPosition('slider_x', 60);
      e.run();
      im.setSwitch('btn_a', 0);
      for (var x = 60.0; x >= 0; x -= 1) {
        im.setPosition('slider_x', x);
        final o = e.run();
        expect(o[7].abs(), lessThanOrEqualTo(5), reason: 'x=$x');
        expect(o[0] == 0 || o[7] == 0, isTrue); // không bao giờ cả hai cùng nhận
      }
    });

    test('tắt khoá an toàn thì chuyển ngay', () {
      final e = engine(rules(neutral: false));
      im.setSwitch('btn_a', 1);
      im.setPosition('slider_x', 70);
      e.run();
      im.setSwitch('btn_a', 0);
      final o = e.run();
      expect((o[0], o[7]), (0, 70));
    });

    test('mặc định: nguồn axis bật khoá, nguồn nút / priority ≥ 8 thì không', () {
      final ins = {for (final d in defs()) d.id: d};
      expect(MixRule(id: 'x', source: 'slider_x', destCh: 1).requiresNeutral(ins['slider_x']), isTrue);
      expect(MixRule(id: 'x', source: 'btn_a', destCh: 1).requiresNeutral(ins['btn_a']), isFalse);
      expect(MixRule(id: 'x', source: 'slider_x', destCh: 1, priority: 9).requiresNeutral(ins['slider_x']), isFalse);
      expect(
        MixRule(id: 'x', source: 'slider_x', destCh: 1, priority: 9, safety: SwitchSafety(requireNeutral: true))
            .validate(ins, {}),
        contains('priority'),
      );
    });

    test('reset huỷ trạng thái chờ; lần sau tính lại từ điều kiện hiện tại', () {
      final e = engine(rules());
      im.setSwitch('btn_a', 1);
      im.setPosition('slider_x', 70);
      e.run();
      im.setSwitch('btn_a', 0);
      e.run();
      expect(e.pendingRuleIds, isNotEmpty);
      e.reset();
      final o = e.run();
      expect((o[0], o[7]), (0, 70));
    });
  });

  test('unipolar + Toàn dải (weight 200, offset −100) phủ Min…Max', () {
    final e = engine([MixRule(id: 'r', source: 'uni', destCh: 1, weightPct: 200, offsetPct: -100)]);
    im.setPosition('uni', -100); // cần ở thấp nhất → trạng thái 0
    expect(e.run()[0], -100);
    im.setPosition('uni', 100);
    expect(e.run()[0], 100);
    final plain = engine([MixRule(id: 'r', source: 'uni', destCh: 1)]);
    im.setPosition('uni', -100);
    expect(plain.run()[0], 0); // mặc định: 0…100 → Center…Max
  });

  test('ví dụ G2a viết lại bằng Condition có trễ (K2)', () {
    final e = engine([
      MixRule(id: 'lo', source: 'k0', destCh: 3),
      MixRule(id: 'hi', source: 'k100', destCh: 3, priority: 1,
          condition: const ExprCmp(input: 'steer', op: CmpOp.ge, value: 80, hyst: 10)),
    ]);
    final got = <double>[0, 75, 82, 72, 69, 78].map((v) {
      im.setPosition('steer', v);
      return e.run()[2];
    }).toList();
    expect(got, [0, 0, 100, 100, 0, 0]);
  });

  test('luật tắt hoặc nguồn không tồn tại bị bỏ qua', () {
    final e = engine([
      MixRule(id: 'off', source: 'steer', destCh: 1, enabled: false),
      MixRule(id: 'bad', source: 'nope', destCh: 2),
    ]);
    im.setPosition('steer', 50);
    expect(e.run().sublist(0, 2), [0, 0]);
  });

  test('validateMixer: lỗi và cảnh báo', () {
    final r = validateMixer(
      inputs: defs(),
      conditions: [ConditionDef(id: 'c', name: 'C', expr: const ExprRef('c'))],
      rules: [
        MixRule(id: 'a', source: 'steer', destCh: 4),
        MixRule(id: 'b', source: 'steer', destCh: 11),
      ],
      disabledChannels: {4},
    );
    expect(r.errors.join('\n'), allOf(contains('vòng'), contains('CH1–CH10')));
    expect(r.warnings.single, contains('CH4'));
  });

  test('N6: 64 luật + 32 điều kiện + 48 Input, p99 ≤ 2 ms mỗi chu kỳ', () {
    final ins = [
      for (var i = 0; i < 40; i++) InputDef(id: 'a$i', name: 'A$i'),
      for (var i = 0; i < 8; i++) InputDef(id: 'b$i', name: 'B$i', type: InputType.binary),
    ];
    final conds = [
      for (var i = 0; i < 32; i++)
        ConditionDef(id: 'c$i', name: 'C$i', expr: ExprAnd([
          ExprCmp(input: 'a${i % 40}', op: CmpOp.ge, value: 50, hyst: 10),
          ExprCmp(input: 'b${i % 8}', op: CmpOp.eq, value: 1),
        ])),
    ];
    final rules = [
      for (var i = 0; i < 64; i++)
        MixRule(
          id: 'r$i',
          source: 'a${i % 40}',
          destCh: i % 10 + 1,
          condition: i.isEven ? ExprRef('c${i % 32}') : const ExprTrue(),
          combine: Combine.values[i % Combine.values.length],
          curve: i % 3 == 0 ? MixCurve(type: CurveType.expo, expoPct: 30) : null,
          priority: i % 5,
        ),
    ];
    im = InputManager(ins);
    final e = MixerEngine(im, conditions: conds, rules: rules);
    final times = <int>[];
    final sw = Stopwatch();
    for (var k = 0; k < 10000; k++) {
      im.setPosition('a${k % 40}', (k % 200) - 100.0);
      im.setSwitch('b${k % 8}', k & 1);
      sw
        ..reset()
        ..start();
      e.run();
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    expect(times[(times.length * 0.99).floor()], lessThanOrEqualTo(2000));
  });
}
