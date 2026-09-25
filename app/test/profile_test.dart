import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/data/profile_migration.dart';
import 'package:rc_controller/data/profile_repository.dart';
import 'package:rc_controller/layout/layout_templates.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/channel_config.dart';
import 'package:rc_controller/models/control_layout.dart';
import 'package:rc_controller/models/mix_rule.dart';
import 'package:rc_controller/protocol/protocol.dart';

CarProfile sample() {
  final p = CarProfile(id: 'p1', name: 'Xe tải đỏ', connType: ConnType.wifi, wifi: WifiConn());
  ProfileTemplate.lightsHorn.applyTo(p);
  p.mixes.add(MixRule(id: 'm1', sourceCh: 1, targetCh: 3));
  return p;
}

void main() {
  test('JSON: lưu → đọc lại giống hệt', () {
    final p = sample();
    final j = jsonEncode(p.toJson());
    final back = CarProfile.fromJson(ProfileMigration.migrate(jsonDecode(j) as Map<String, dynamic>));
    expect(jsonEncode(back.toJson()), j);
  });

  test('mặc định: CH1 = Lái vào cần ngang, CH2 = Ga vào cần dọc, còn lại tắt', () {
    final p = CarProfile(id: 'x', name: 'x', connType: ConnType.wifi);
    expect(p.channels.length, 10);
    expect(p.controlOf(1)?.kind, ItemKind.stickH);
    expect(p.controlOf(2)?.kind, ItemKind.stickV);
    expect(p.channels.skip(2).every((c) => !c.enabled && p.controlOf(c.index) == null), isTrue);
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

    test('bố cục thiếu phần tử cho Ga/Lái thì không cho lưu (H5)', () {
      final p = sample();
      expect(p.validateAll(), isEmpty);
      p.activeLayout.unassignChannel(2);
      expect(p.validateAll().join(), contains('Ga'));
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

  test('gán kênh vào phần tử; tắt kênh thì gỡ khỏi phần tử, phần tử vẫn giữ', () {
    final p = sample();
    final light = p.controlOf(3)!;
    expect(light.kind, ItemKind.toggle);
    p.ch(3).enabled = false;
    p.syncLayouts();
    expect(p.controlOf(3), isNull);
    expect(p.activeLayout.items.any((i) => i.id == light.id), isTrue);
    final knob = LayoutTemplates.addControl(p.activeLayout, ItemKind.knob)!;
    p.assignChannel(knob, 6);
    expect(p.ch(6).enabled, isTrue);
    expect(p.controlOf(6)?.id, knob.id);
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
    p.mixes.add(MixRule(id: 'm'));
    expect(p.failsafeHash(), h0);
    p.channels[4].failsafeUs = 1000;
    expect(p.failsafeHash(), isNot(h0));
    p.channels[4].failsafeUs = 1500;
    expect(p.failsafeHash(), h0);
    p.failsafeTimeoutMs = 500;
    expect(p.failsafeHash(), isNot(h0));
  });
}
