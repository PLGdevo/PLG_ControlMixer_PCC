// N4: chuyển hồ sơ Sprint 3 (v1) → Sprint 4 (v2). So kết quả của thuật toán Sprint 3 (bản đóng băng
// trong support/) và mixer Sprint 4 trên cùng chuỗi thao tác: phải trùng khớp, trừ các ca có cảnh báo.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/data/profile_migration.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/services/input_manager.dart';
import 'package:rc_controller/services/mixer_engine.dart';

import 'support/sprint3_reference.dart';

/// Hồ sơ Sprint 3 thật: lái, ga, đèn (bật/tắt), còi (nhấn giữ, tắt = 0%), tời (3 nấc), ben (núm),
/// 5 luật mix đủ 4 loại. Hộp số 100% mọi số (hộp số áp sau mix ở Sprint 4, so riêng).
Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/sprint3_profile.json').readAsStringSync()) as Map<String, dynamic>;

/// Phần tử trên bố cục đang dùng: kênh → loại phần tử
Map<int, String> controlsOf(Map<String, dynamic> j) {
  final l = (j['layouts'] as List).firstWhere((l) => l['id'] == j['activeLayoutId']) as Map;
  return {
    for (final it in l['items'] as List)
      if (it['channel'] != null) it['channel'] as int: it['kind'] as String,
  };
}

/// Bộ điều khiển giả: cần gạt/núm theo vị trí %, nút/công tắc theo nấc
class Controls {
  Controls(this.j) : kinds = controlsOf(j);
  final Map<String, dynamic> j;
  final Map<int, String> kinds;
  final pos = <int, double>{}, sw = <int, int>{};

  bool isSwitch(String k) => k == 'button' || k == 'toggle' || k == 'switch3';

  double offPct(int ch) =>
      ((j['channels'] as List).firstWhere((c) => c['index'] == ch)['offValuePct'] as num?)?.toDouble() ?? -100;

  void randomStep(Random r) {
    kinds.forEach((ch, k) {
      if (k == 'switch3') {
        if (r.nextDouble() < 0.2) sw[ch] = r.nextInt(3);
      } else if (isSwitch(k)) {
        if (r.nextDouble() < 0.25) sw[ch] = r.nextInt(2);
      } else {
        final roll = r.nextDouble();
        pos[ch] = roll < 0.15 ? 0 : (roll < 0.25 ? r.nextDouble() * 6 - 3 : r.nextDouble() * 200 - 100);
      }
    });
  }

  /// Đầu vào Sprint 3 (% theo kênh, như control_screen._switchPct của Sprint 3)
  List<double?> s3Input() {
    final v = List<double?>.filled(10, null);
    kinds.forEach((ch, k) {
      if (k == 'switch3') {
        v[ch - 1] = [offPct(ch), 0.0, 100.0][sw[ch] ?? 0];
      } else if (isSwitch(k)) {
        v[ch - 1] = (sw[ch] ?? 0) == 1 ? 100 : offPct(ch);
      } else {
        v[ch - 1] = pos[ch] ?? 0;
      }
    });
    return v;
  }

  void applyTo(InputManager im) {
    kinds.forEach((ch, k) {
      if (isSwitch(k)) {
        im.setSwitch('ch$ch', sw[ch] ?? 0);
      } else {
        im.setPosition('ch$ch', pos[ch] ?? 0);
      }
    });
  }
}

({InputManager im, MixerEngine mixer, List<String> warnings, Map<String, dynamic> json}) migrate(
    Map<String, dynamic> v1) {
  final r = ProfileMigration.v1ToV2(v1);
  final j = r.json;
  final inputs = [for (final e in j['inputs'] as List) InputDef.fromJson(e as Map<String, dynamic>)];
  final conds = [for (final e in j['conditions'] as List) ConditionDef.fromJson(e as Map<String, dynamic>)];
  final rules = [for (final e in j['mixer'] as List) MixRule.fromJson(e as Map<String, dynamic>)];
  final im = InputManager(inputs);
  return (im: im, mixer: MixerEngine(im, conditions: conds, rules: rules), warnings: r.warnings, json: j);
}

void expectSameOutput(Map<String, dynamic> v1, {int steps = 3000, int seed = 7}) {
  final m = migrate(v1);
  final ref = Sprint3Mixer(v1);
  final c = Controls(v1);
  final rnd = Random(seed);
  for (var i = 0; i < steps; i++) {
    c.randomStep(rnd);
    final want = ref.mixedPct(c.s3Input(), gear: 1);
    c.applyTo(m.im);
    final got = m.mixer.run();
    for (var ch = 0; ch < 10; ch++) {
      expect(got[ch], closeTo(want[ch], 1e-9), reason: 'bước $i, CH${ch + 1}');
    }
  }
}

void main() {
  test('hồ sơ Sprint 3 thật (đủ 4 loại luật) chuyển xong cho cùng kết quả, không cảnh báo, hợp lệ', () {
    final v1 = fixture();
    final m = migrate(v1);
    expect(m.warnings, isEmpty);
    expect([for (final i in m.json['inputs'] as List) i['id']].take(6), ['ch1', 'ch2', 'ch3', 'ch4', 'ch5', 'ch6']);
    expect((m.json['inputs'] as List)[3]['levels']['offPct'], 0); // offValuePct của còi
    final v = validateMixer(
      inputs: [for (final e in m.json['inputs'] as List) InputDef.fromJson(e as Map<String, dynamic>)],
      conditions: const [],
      rules: [for (final e in m.json['mixer'] as List) MixRule.fromJson(e as Map<String, dynamic>)],
    );
    expect(v.errors, isEmpty);
    for (final seed in [7, 11, 12]) {
      expectSameOutput(v1, seed: seed);
    }
  });

  test('hồ sơ không có mix: mỗi Input một luật gốc, cùng kết quả', () {
    final v1 = fixture()..['mixes'] = <Object>[];
    final m = migrate(v1);
    expect(m.warnings, isEmpty);
    expect((m.json['mixer'] as List).length, 6);
    expectSameOutput(v1);
  });

  test('JSON v2: không còn channel/mixes/offValuePct, kênh đích của mix được bật', () {
    final j = migrate(fixture()).json;
    expect(j['schemaVersion'], 2);
    expect(j.containsKey('mixes'), isFalse);
    for (final c in j['channels'] as List) {
      expect((c as Map).containsKey('offValuePct'), isFalse);
    }
    expect([for (final n in [7, 8, 9, 10]) (j['channels'] as List)[n - 1]['enabled']], everyElement(isTrue));
    final items = [for (final l in j['layouts'] as List) ...(l['items'] as List)];
    expect(items.any((i) => (i as Map).containsKey('channel')), isFalse);
    expect(items.where((i) => i['inputId'] != null).length, 6);
    expect(j['arm'], {'autoArm': false});
  });

  test('cảnh báo: đọc kênh đã bị luật trước ghi, đọc/ghi CH2 (hộp số), đích chuyển kênh đang có phần tử', () {
    final v1 = fixture()
      ..['mixes'] = [
        {'id': 'a', 'type': 'linear', 'sourceCh': 1, 'targetCh': 7},
        {'id': 'b', 'type': 'linear', 'sourceCh': 7, 'targetCh': 8},
        {'id': 'c', 'type': 'linear', 'sourceCh': 2, 'targetCh': 9},
        {'id': 'd', 'type': 'select', 'sourceCh': 6, 'selectCh': 3, 'targetOnCh': 2, 'targetOffCh': 10},
      ];
    final w = migrate(v1).warnings.join('\n');
    expect(w, contains('Luật mix 2 đọc CH7'));
    expect(w, contains('Luật mix 3 đọc CH2 (Ga)'));
    expect(w, contains('Luật mix 4 (chuyển kênh)'));
    expect(w, contains('Luật mix 4 ghi vào CH2 (Ga)'));
  });

  test('một kênh gán vào hai kiểu phần tử ở hai bố cục → Input thứ hai, không có luật, có cảnh báo', () {
    final v1 = fixture();
    final l2 = jsonDecode(jsonEncode((v1['layouts'] as List).first)) as Map<String, dynamic>;
    l2['id'] = 'lay-2';
    l2['name'] = 'Bố cục 2';
    final light = (l2['items'] as List).firstWhere((i) => i['channel'] == 3) as Map;
    light['kind'] = 'knob'; // CH3 là nút bật/tắt ở bố cục 1
    (v1['layouts'] as List).add(l2);
    final m = migrate(v1);
    expect([for (final i in m.json['inputs'] as List) i['id']], contains('ch3_2'));
    expect(m.warnings.single, contains('CH3'));
    expect((m.json['mixer'] as List).where((r) => r['source'] == 'ch3_2'), isEmpty);
    final l2json = (m.json['layouts'] as List)[1] as Map;
    expect((l2json['items'] as List).any((i) => i['inputId'] == 'ch3_2'), isTrue);
  });
}
