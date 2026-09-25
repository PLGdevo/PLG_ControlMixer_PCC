// N4: chuyển hồ sơ Sprint 3 (v1) → Sprint 4 (v2). So kết quả của engine Sprint 3 và Sprint 4
// trên cùng chuỗi thao tác: phải trùng khớp, trừ các ca có cảnh báo.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/data/profile_migration.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mix_rule.dart' as s3;
import 'package:rc_controller/models/mixer_rule.dart' as s4;
import 'package:rc_controller/services/input_manager.dart';
import 'package:rc_controller/services/mixer_engine.dart';
import 'package:rc_controller/services/output_pipeline.dart';

/// Hồ sơ Sprint 3: lái/ga + đèn (bật/tắt), còi (nhấn giữ, tắt = 0%), công tắc 3 nấc, núm
CarProfile sprint3Profile() {
  final p = CarProfile(id: 'p1', name: 'Xe', connType: ConnType.wifi)
    ..gears.maxThrottle = [100, 100, 100, 100, 100]; // hộp số ngoài phạm vi so sánh (áp sau mix ở Sprint 4)
  final l = p.activeLayout;
  p.ch(3)
    ..name = 'Đèn'
    ..enabled = true;
  p.ch(4)
    ..name = 'Còi'
    ..enabled = true
    ..offValuePct = 0;
  p.ch(5).enabled = true;
  p.ch(6).enabled = true;
  LayoutTemplates.addControl(l, ItemKind.toggle, channel: 3);
  LayoutTemplates.addControl(l, ItemKind.button, channel: 4);
  LayoutTemplates.addControl(l, ItemKind.switch3, channel: 5);
  LayoutTemplates.addControl(l, ItemKind.knob, channel: 6);
  return p;
}

/// Bộ điều khiển giả: vị trí cần theo kênh và vị trí nút/công tắc
class Controls {
  final pos = <int, double>{1: 0, 2: 0, 6: 0};
  final sw = <int, int>{3: 0, 4: 0, 5: 1};

  /// Đầu vào Sprint 3 (% theo kênh, như control_screen._switchPct)
  List<double?> s3Input(CarProfile p) {
    final v = List<double?>.filled(10, null);
    pos.forEach((ch, x) => v[ch - 1] = x);
    sw.forEach((ch, k) {
      final off = p.ch(ch).offValuePct;
      v[ch - 1] = ch == 5 ? [off, 0.0, 100.0][k] : (k == 1 ? 100 : off);
    });
    return v;
  }

  void applyTo(InputManager im) {
    pos.forEach((ch, x) => im.setPosition('ch$ch', x));
    sw.forEach((ch, k) => im.setSwitch('ch$ch', k));
  }

  void randomStep(Random r) {
    for (final ch in pos.keys.toList()) {
      final roll = r.nextDouble();
      pos[ch] = roll < 0.15 ? 0 : (roll < 0.25 ? r.nextDouble() * 6 - 3 : r.nextDouble() * 200 - 100);
    }
    if (r.nextDouble() < 0.2) sw[3] = 1 - sw[3]!;
    if (r.nextDouble() < 0.3) sw[4] = r.nextInt(2);
    if (r.nextDouble() < 0.2) sw[5] = r.nextInt(3);
  }
}

({InputManager im, MixerEngine mixer, List<String> warnings, Map<String, dynamic> json}) migrate(CarProfile p) {
  final r = ProfileMigration.v1ToV2(p.toJson());
  final j = r.json;
  final inputs = [for (final e in j['inputs'] as List) InputDef.fromJson(e as Map<String, dynamic>)];
  final conds = [for (final e in j['conditions'] as List) ConditionDef.fromJson(e as Map<String, dynamic>)];
  final rules = [for (final e in j['mixer'] as List) s4.MixRule.fromJson(e as Map<String, dynamic>)];
  final im = InputManager(inputs);
  return (im: im, mixer: MixerEngine(im, conditions: conds, rules: rules), warnings: r.warnings, json: j);
}

void expectSameOutput(CarProfile p, {int steps = 3000, int seed = 7}) {
  final m = migrate(p);
  final pipe = OutputPipeline(p);
  final c = Controls();
  final rnd = Random(seed);
  for (var i = 0; i < steps; i++) {
    c.randomStep(rnd);
    final want = pipe.mixedPct(c.s3Input(p), gear: 1);
    c.applyTo(m.im);
    final got = m.mixer.run();
    for (var ch = 0; ch < 10; ch++) {
      expect(got[ch], closeTo(want[ch], 1e-9), reason: 'bước $i, CH${ch + 1}');
    }
  }
}

void main() {
  test('hồ sơ không có mix: Input ch1…ch6, mỗi Input một luật gốc, cùng kết quả', () {
    final p = sprint3Profile();
    final m = migrate(p);
    expect(m.warnings, isEmpty);
    expect([for (final i in m.json['inputs'] as List) i['id']], ['ch1', 'ch2', 'ch3', 'ch4', 'ch5', 'ch6']);
    expect((m.json['inputs'] as List)[3]['levels']['offPct'], 0); // offValuePct của còi
    expect((m.json['mixer'] as List).length, 6);
    expectSameOutput(p);
  });

  test('đủ 4 loại luật Sprint 3 (threshold/max, linear+gate, curve/add, select) cho cùng µs', () {
    final p = sprint3Profile()
      ..mixes = [
        s3.MixRule(id: 'a', type: s3.MixType.threshold, sourceCh: 1, targetCh: 7, mode: s3.MixMode.max,
            onAtPct: 80, offBelowPct: 70, onValuePct: 100, offValuePct: -40),
        s3.MixRule(id: 'b', type: s3.MixType.linear, sourceCh: 6, targetCh: 8, gateCh: 3, gainPct: 50, offsetPct: 10),
        s3.MixRule(id: 'c', type: s3.MixType.curve, sourceCh: 6, targetCh: 8, mode: s3.MixMode.add,
            curvePts: [-100, -20, 0, 30, 100]),
        s3.MixRule(id: 'd', type: s3.MixType.select, sourceCh: 6, selectCh: 4, targetOnCh: 10, targetOffCh: 9),
        s3.MixRule(id: 'e', type: s3.MixType.linear, sourceCh: 5, targetCh: 7, enabled: false),
      ];
    final m = migrate(p);
    expect(m.warnings, isEmpty);
    final v = s4.validateMixer(
      inputs: [for (final e in m.json['inputs'] as List) InputDef.fromJson(e as Map<String, dynamic>)],
      conditions: const [],
      rules: [for (final e in m.json['mixer'] as List) s4.MixRule.fromJson(e as Map<String, dynamic>)],
    );
    expect(v.errors, isEmpty);
    expectSameOutput(p, seed: 11);
    expectSameOutput(p, seed: 12);
  });

  test('JSON v2: không còn channel/mixes/offValuePct, kênh đích của mix được bật', () {
    final p = sprint3Profile()
      ..mixes = [s3.MixRule(id: 'a', type: s3.MixType.linear, sourceCh: 1, targetCh: 9)];
    final j = migrate(p).json;
    expect(j['schemaVersion'], 2);
    expect(j.containsKey('mixes'), isFalse);
    for (final c in j['channels'] as List) {
      expect((c as Map).containsKey('offValuePct'), isFalse);
    }
    expect((j['channels'] as List)[8]['enabled'], isTrue);
    final items = [for (final l in j['layouts'] as List) ...(l['items'] as List)];
    expect(items.any((i) => (i as Map).containsKey('channel')), isFalse);
    expect(items.where((i) => i['inputId'] != null).length, 6);
    expect(j['arm'], {'autoArm': false});
  });

  test('cảnh báo: đọc kênh đã bị luật trước ghi, đọc/ghi CH2 (hộp số), đích chuyển kênh đang có phần tử', () {
    final p = sprint3Profile()
      ..mixes = [
        s3.MixRule(id: 'a', type: s3.MixType.linear, sourceCh: 1, targetCh: 7),
        s3.MixRule(id: 'b', type: s3.MixType.linear, sourceCh: 7, targetCh: 8),
        s3.MixRule(id: 'c', type: s3.MixType.linear, sourceCh: 2, targetCh: 9),
        s3.MixRule(id: 'd', type: s3.MixType.select, sourceCh: 6, selectCh: 3, targetOnCh: 2, targetOffCh: 10),
      ];
    final w = migrate(p).warnings.join('\n');
    expect(w, contains('Luật mix 2 đọc CH7'));
    expect(w, contains('Luật mix 3 đọc CH2 (Ga)'));
    expect(w, contains('Luật mix 4 (chuyển kênh)'));
    expect(w, contains('Luật mix 4 ghi vào CH2 (Ga)'));
  });

  test('một kênh gán vào hai kiểu phần tử ở hai bố cục → Input thứ hai, không có luật, có cảnh báo', () {
    final p = sprint3Profile();
    final l2 = LayoutTemplates.standard()..name = 'Bố cục 2';
    LayoutTemplates.addControl(l2, ItemKind.knob, channel: 3); // CH3 là nút bật/tắt ở bố cục 1
    p.layouts.add(l2);
    final m = migrate(p);
    final ids = [for (final i in m.json['inputs'] as List) i['id']];
    expect(ids, contains('ch3_2'));
    expect(m.warnings.single, contains('CH3'));
    expect((m.json['mixer'] as List).where((r) => r['source'] == 'ch3_2'), isEmpty);
    final l2json = (m.json['layouts'] as List)[1] as Map;
    expect((l2json['items'] as List).any((i) => i['inputId'] == 'ch3_2'), isTrue);
  });
}
