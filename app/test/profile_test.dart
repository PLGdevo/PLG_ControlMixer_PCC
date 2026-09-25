import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/data/profile_migration.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/channel_config.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/input_def.dart';
import 'package:rc_controller/models/mixer_rule.dart';
import 'package:rc_controller/protocol/protocol.dart';

CarProfile sample() {
  final p = CarProfile(id: 'p1', name: 'Xe tải đỏ', connType: ConnType.wifi, wifi: WifiConn());
  ProfileTemplate.lightsHorn.applyTo(p);
  p.mixer.add(MixRule(
    id: 'm1',
    source: 'steer',
    destCh: 5,
    condition: const ExprCmp(input: 'light', op: CmpOp.eq, value: 1),
  ));
  p.ch(5).enabled = true;
  return p;
}

void main() {
  test('JSON: lưu → đọc lại giống hệt', () {
    final p = sample();
    final j = jsonEncode(p.toJson());
    final back = CarProfile.fromJson(ProfileMigration.migrate(jsonDecode(j) as Map<String, dynamic>));
    expect(jsonEncode(back.toJson()), j);
  });

  test('mặc định: Input Lái (cần ngang) → CH1, Ga (cần dọc) → CH2, kênh còn lại tắt', () {
    final p = CarProfile(id: 'x', name: 'x', connType: ConnType.wifi, wifi: WifiConn());
    expect(p.channels.length, 10);
    expect([for (final i in p.inputs) i.id], ['steer', 'throttle']);
    expect(p.activeLayout.itemForInput('steer')?.kind, ItemKind.stickH);
    expect(p.activeLayout.itemForInput('throttle')?.kind, ItemKind.stickV);
    expect(p.quickRoute('steer'), 1);
    expect(p.quickRoute('throttle'), 2);
    expect(p.isThrottleInput('throttle'), isTrue);
    expect(p.channels.skip(2).every((c) => !c.enabled && p.rulesTo(c.index).isEmpty), isTrue);
    expect(p.validateAll(), isEmpty);
  });

  test('hồ sơ định dạng cũ chuyển sang hệ kênh, CH1/CH2 giữ giá trị cũ (B5)', () {
    final old = {
      'name': 'Xe cũ',
      'ip': '192.168.4.1',
      'port': 4210,
      'config': {
        'throttle': [1000, 1520, 2000, 0, 0, 0, 1500],
        'steering': [1100, 1480, 1900, 12, -30, 1, 1480],
        'failsafe_timeout_ms': 500,
        'gear_count': 2,
        'gear_limit': [40, 80, 100, 100, 100],
      },
    };
    final p = CarProfile.fromJson(ProfileMigration.migrate(old));
    expect(p.inputs, isEmpty); // định dạng cũ không có bố cục: phải gắn Input lại
    expect(p.throttle.centerUs, 1520);
    expect(p.steering.centerUs, 1480);
    expect(p.steering.trimUs, 12);
    expect(p.steering.offsetUs, -30);
    expect(p.steering.reverse, isTrue);
    expect(p.failsafeTimeoutMs, 500);
    expect(p.gears.gearCount, 2);
    expect(p.gears.maxThrottle.take(2), [40, 80]);
  });

  test('từ chối schemaVersion mới hơn app', () {
    expect(() => ProfileMigration.migrate({'schemaVersion': 99, 'id': 'a'}), throwsA(isA<ProfileFormatException>()));
  });

  test('đổi qua lại CarConfig của firmware v1', () {
    final p = sample();
    p.steering.trimUs = 25;
    final cfg = CarConfig.parse(p.toCarConfig().toBytes())!;
    expect(cfg.steering.trimUs, 25);
    final q = CarProfile(id: 'q', name: 'q', connType: ConnType.wifi)..applyCarConfig(cfg);
    expect(q.steering.trimUs, 25);
    expect(q.throttle.centerUs, p.throttle.centerUs);
  });

  group('Kiểm tra dữ liệu (E7)', () {
    test('IPv4, port, tên', () {
      expect(CarProfile.isValidIpv4('192.168.4.1'), isTrue);
      expect(CarProfile.isValidIpv4('256.1.1.1'), isFalse);
      expect(CarProfile.isValidIpv4('1.2.3'), isFalse);
      expect(CarProfile.isValidIpv4('01.2.3.4'), isFalse);
      final p = sample()..wifi!.port = 0;
      expect(p.validateGeneral()['port'], isNotNull);
      p.name = '';
      expect(p.validateGeneral()['name'], isNotNull);
      p.name = 'Xe A';
      expect(p.validateGeneral(otherNames: ['xe a'])['name'], isNotNull);
    });

    test('servo: 500 ≤ Min < Center < Max ≤ 2500, failsafe trong [Min, Max]', () {
      final c = ChannelConfig.defaults(3);
      expect(c.validate(), isEmpty);
      c.minUs = 400;
      expect(c.validate()['min'], isNotNull);
      c
        ..minUs = 1000
        ..centerUs = 2100;
      expect(c.validate()['center'], isNotNull);
      c
        ..centerUs = 1500
        ..failsafeUs = 2200;
      expect(c.validate()['failsafe'], isNotNull);
    });

    test('thiếu luật hoặc phần tử cho Ga/Lái thì không cho lưu (V)', () {
      final p = sample();
      expect(p.validateAll(), isEmpty);
      p.activeLayout.unbindInput('throttle');
      expect(p.validateAll().join(), contains('Ga'));
      final q = sample()..mixer.removeWhere((r) => r.destCh == 1);
      expect(q.validateAll().join(), contains('Lái (CH1)'));
    });

    test('phần tử gắn Input sai kiểu hoặc Input không tồn tại', () {
      final p = sample();
      p.activeLayout.itemForInput('light')!.inputId = 'steer'; // nút bật/tắt gắn Input trục
      expect(p.validateAll().join(), contains('không gắn được'));
      final q = sample();
      q.activeLayout.itemForInput('horn')!.inputId = 'ghost';
      expect(q.validateAll().join(), contains('không tồn tại'));
    });
  });

  test('quy ước phần trăm (B1)', () {
    final c = ChannelConfig(index: 3, name: 'x', minUs: 1000, centerUs: 1400, maxUs: 2000);
    expect(c.pctToUs(100), 2000);
    expect(c.pctToUs(-100), 1000);
    expect(c.pctToUs(50), 1700);
    expect(c.pctToUs(-50), 1200);
    expect(c.usToPct(1700), 50);
    expect(c.usToPct(1200), -50);
  });

  group('Gắn nhanh Input → kênh (U5)', () {
    test('tạo Input từ phần tử, gắn nhanh tới kênh thì tạo luật mặc định và bật kênh', () {
      final p = sample();
      final knob = LayoutTemplates.addControl(p.activeLayout, ItemKind.knob)!;
      final d = p.createInput(ItemKind.knob);
      p.activeLayout.bindInput(knob, d.id);
      expect(d.type, InputType.axis);
      expect(p.quickRoute(d.id), isNull);
      p.setQuickRoute(d.id, 6);
      expect(p.ch(6).enabled, isTrue);
      expect(p.quickRoute(d.id), 6);
      p.setQuickRoute(d.id, 7);
      expect(p.rulesUsing(d.id).single.destCh, 7);
      p.setQuickRoute(d.id, null);
      expect(p.rulesUsing(d.id), isEmpty);
    });

    test('Input có luật có điều kiện / nhiều luật thì không gắn nhanh được', () {
      final p = sample();
      expect(p.canQuickRoute('steer'), isFalse); // CH1 + luật m1 có điều kiện
      expect(p.canQuickRoute('light'), isFalse); // dùng trong điều kiện của m1
      expect(p.quickRoute('horn'), 4);
    });

    test('xoá Input: gỡ khỏi bố cục, tắt các luật dùng nó; đổi mã thì đổi ở mọi nơi', () {
      final p = sample();
      p.renameInput('light', 'lamp');
      expect(p.activeLayout.itemForInput('lamp')?.kind, ItemKind.toggle);
      expect(p.mixer.firstWhere((r) => r.id == 'm1').condition.inputs, ['lamp']);
      p.deleteInput('lamp');
      expect(p.input('lamp'), isNull);
      expect(p.activeLayout.itemForInput('lamp'), isNull);
      expect(p.mixer.where((r) => !r.enabled).map((r) => r.id), containsAll(['m1']));
    });

    test('khôi phục mặc định giữ Input điều khiển Lái/Ga', () {
      final p = sample()..resetConfig();
      expect(p.mixer.map((r) => (r.source, r.destCh)), [('steer', 1), ('throttle', 2)]);
      expect(p.inputs.length, 4);
    });
  });

  group('ProfileRepository', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rc_profiles_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lưu, đọc lại từ đĩa, nhân bản, xoá', () async {
      final repo = ProfileRepository(dir);
      await repo.load();
      await repo.save(sample());
      final repo2 = ProfileRepository(dir);
      await repo2.load();
      expect(repo2.list().single.name, 'Xe tải đỏ');
      final d = await repo2.duplicate('p1');
      expect(d.name, 'Xe tải đỏ (bản sao)');
      expect(repo2.list().length, 2);
      await repo2.delete('p1');
      expect(repo2.exists('p1'), isFalse);
    });

    test('mở app: hồ sơ Sprint 3 tự chuyển sang v2, giữ bản gốc, có báo cáo', () async {
      final v1 = File('test/fixtures/sprint3_profile.json').readAsStringSync();
      File('${dir.path}/fixture-s3.json').writeAsStringSync(v1);
      final repo = ProfileRepository(dir);
      await repo.load();
      expect(repo.loadErrors, isEmpty);
      final p = repo.get('fixture-s3')!;
      expect(p.inputs.map((i) => i.id), containsAll(['ch1', 'ch2', 'ch3']));
      expect(repo.migrationReports.keys, ['fixture-s3']);
      expect(File('${dir.path}/fixture-s3.v1.bak').existsSync(), isTrue);
      final saved = jsonDecode(File('${dir.path}/fixture-s3.json').readAsStringSync()) as Map;
      expect(saved['schemaVersion'], CarProfile.schemaVersion);
      final again = ProfileRepository(dir);
      await again.load();
      expect(again.migrationReports, isEmpty); // chỉ báo một lần
      expect(again.list().length, 1); // file .bak không bị đọc
    });

    test('xuất rồi nhập lại cho ra hồ sơ giống hệt; trùng id thì hỏi', () async {
      final repo = ProfileRepository(dir);
      await repo.load();
      await repo.save(sample());
      final json = repo.export('p1');
      await expectLater(repo.import(json), throwsA(isA<ImportConflictException>()));
      final copy = await repo.import(json, onConflict: ImportConflict.createNew);
      expect(copy.id, isNot('p1'));
      expect(copy.name, isNot('Xe tải đỏ'));

      final other = Directory.systemTemp.createTempSync('rc_profiles_b_');
      try {
        final repoB = ProfileRepository(other);
        await repoB.load();
        final p = await repoB.import(json);
        final a = repo.get('p1')!.toJson()..remove('updatedAt');
        final b = p.toJson()..remove('updatedAt');
        expect(jsonEncode(b), jsonEncode(a));
      } finally {
        other.deleteSync(recursive: true);
      }
    });
  });

  test('hash failsafe (E5) chỉ đổi khi failsafe đổi', () {
    final p = CarProfile(id: 'h', name: 'h', connType: ConnType.wifi);
    final h0 = p.failsafeHash();
    expect(p.failsafeBytes().length, 22);
    p.steering.trimUs = 30;
    p.throttle.maxUs = 1900;
    p.gears.gearCount = 2;
    p.mixer.add(MixRule(id: 'm', source: 'steer', destCh: 5));
    expect(p.failsafeHash(), h0);
    p.channels[4].failsafeUs = 1000;
    expect(p.failsafeHash(), isNot(h0));
    p.channels[4].failsafeUs = 1500;
    expect(p.failsafeHash(), h0);
    p.failsafeTimeoutMs = 500;
    expect(p.failsafeHash(), isNot(h0));
  });
}
