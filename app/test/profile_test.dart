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

  test('mẫu "Trống": không Input, không luật, không kênh Ga/Lái, bố cục không có cần gạt', () {
    final p = CarProfile(id: 'b', name: 'b', connType: ConnType.wifi, wifi: WifiConn());
    ProfileTemplate.blank.applyTo(p);
    expect(p.inputs, isEmpty);
    expect(p.mixer, isEmpty);
    expect(p.throttleCh, isNull);
    expect(p.steeringCh, isNull);
    expect(p.activeLayout.items.where((i) => i.kind.isControl), isEmpty);
    expect(p.channels.map((c) => c.name).take(2), ['Kênh 1', 'Kênh 2']);
    expect(p.channels.map((c) => c.enabled).take(3), [true, true, false]); // firmware v1 luôn xuất CH1/CH2
    expect(p.validateAll(), isEmpty);
    expect(p.validateMixerPart().warnings, isEmpty);
    final back = CarProfile.fromJson(ProfileMigration.migrate(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>));
    expect(back.throttleCh, isNull);
    expect(back.steeringCh, isNull);
  });

  test('hồ sơ lưu trước khi chọn được kênh Ga/Lái: Lái CH1, Ga CH2', () {
    final j = sample().toJson()
      ..remove('throttleCh')
      ..remove('steeringCh');
    final p = CarProfile.fromJson(ProfileMigration.migrate(j));
    expect(p.steeringCh, 1);
    expect(p.throttleCh, 2);
  });

  test('xe (firmware v1) nhận CH1/CH2, 1 số, giới hạn ga 100% (app không có hộp số)', () {
    final cfg = sample().toCarConfig();
    expect(cfg.gearCount, 1);
    expect(cfg.gearLimit, [100, 100, 100, 100, 100]);
    expect(cfg.validate(), isNull);
    expect(cfg.steering.minUs, 1100);
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
    expect(p.ch(2).centerUs, 1520);
    expect(p.ch(1).centerUs, 1480);
    expect(p.ch(1).trimUs, 12);
    expect(p.ch(1).offsetUs, -30);
    expect(p.ch(1).reverse, isTrue);
    expect(p.failsafeTimeoutMs, 500);
    expect(p.toJson().containsKey('gears'), isFalse); // hộp số đã bỏ
  });

  test('ARM: hồ sơ cũ không có khoá enabled thì vẫn dùng ARM; tắt ARM lưu lại được', () {
    final j = sample().toJson();
    (j['arm'] as Map).remove('enabled');
    expect(CarProfile.fromJson(j).arm.enabled, isTrue);
    final p = sample()..arm.enabled = false;
    expect(CarProfile.fromJson(p.toJson()).arm.enabled, isFalse);
    p.resetConfig();
    expect(p.arm.enabled, isTrue);
  });

  test('bố cục cũ có ô hộp số: bỏ khi đọc, không biến thành nút', () {
    final j = sample().activeLayout.toJson();
    (j['items'] as List).add({'id': 'g', 'kind': 'gearBox', 'x': 5, 'y': 9, 'w': 8, 'h': 3});
    final l = ControlLayout.fromJson(j);
    expect(l.items.length, sample().activeLayout.items.length);
    expect(l.items.any((i) => i.id == 'g'), isFalse);
  });

  test('từ chối schemaVersion mới hơn app', () {
    expect(() => ProfileMigration.migrate({'schemaVersion': 99, 'id': 'a'}), throwsA(isA<ProfileFormatException>()));
  });

  test('đổi qua lại CarConfig của firmware v1', () {
    final p = sample();
    p.ch(1).trimUs = 25;
    final cfg = CarConfig.parse(p.toCarConfig().toBytes())!;
    expect(cfg.steering.trimUs, 25);
    final q = CarProfile(id: 'q', name: 'q', connType: ConnType.wifi)..applyCarConfig(cfg);
    expect(q.ch(1).trimUs, 25);
    expect(q.ch(2).centerUs, p.ch(2).centerUs);
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

    test('kênh Ga/Lái đã chọn mà thiếu luật hoặc phần tử: chỉ cảnh báo, vẫn lưu được (V)', () {
      final p = sample();
      expect(p.validateMixerPart().warnings, isEmpty);
      p.activeLayout.unbindInput('throttle');
      expect(p.roleWarning(throttle: true), contains('Ga (CH2)'));
      expect(p.validateAll(), isEmpty);
      final q = sample()..mixer.removeWhere((r) => r.destCh == 1);
      expect(q.roleWarning(throttle: false), contains('Lái (CH1)'));
      expect(q.validateMixerPart().warnings.join(), contains('Lái (CH1)'));
      expect(q.validateAll(), isEmpty);
      q.steeringCh = null;
      expect(q.roleWarning(throttle: false), isNull);
    });

    test('kênh Ga và Lái không được trùng nhau', () {
      final p = sample()..steeringCh = 2;
      expect(p.validateAll().join(), contains('trùng'));
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

    test('ảnh xe: chép vào thư mục ảnh, bản nhân bản dùng chung, xoá hồ sơ cuối cùng mới xoá ảnh', () async {
      final repo = ProfileRepository(dir);
      await repo.load();
      await repo.save(sample());
      final src = File('${dir.parent.path}/rc_photo_src_${DateTime.now().microsecondsSinceEpoch}.PNG')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => src.existsSync() ? src.deleteSync() : null);

      await repo.setPhoto('p1', src);
      final first = repo.photoFile(repo.get('p1')!)!;
      expect(first.readAsBytesSync(), [1, 2, 3]);
      expect(first.path, endsWith('.png'));
      expect(first.parent.path, repo.photoDir.path);
      final again = ProfileRepository(dir);
      await again.load();
      expect(again.list().length, 1, reason: 'thư mục ảnh không bị đọc như hồ sơ');
      expect(again.get('p1')!.photo, repo.get('p1')!.photo);

      // Đổi ảnh: ảnh cũ bị xoá
      await repo.setPhoto('p1', src);
      final second = repo.photoFile(repo.get('p1')!)!;
      expect(second.path, isNot(first.path));
      expect(first.existsSync(), isFalse);

      final d = await repo.duplicate('p1');
      expect(d.photo, repo.get('p1')!.photo);
      await repo.delete('p1');
      expect(second.existsSync(), isTrue, reason: 'bản nhân bản còn dùng');
      await repo.setPhoto(d.id, null);
      expect(repo.get(d.id)!.photo, isNull);
      expect(second.existsSync(), isFalse);
    });

    test('ảnh xe: tên file lạ không được đọc / xoá; nhập hồ sơ thì bỏ ảnh không có trên máy', () async {
      final repo = ProfileRepository(dir);
      await repo.load();
      await repo.save(sample());
      final bad = sample()
        ..id = 'p2'
        ..name = 'Xe lạ'
        ..photo = '../p1.json';
      expect(repo.photoFile(bad), isNull);
      await repo.save(bad);
      await repo.delete('p2');
      expect(File('${dir.path}/p1.json').existsSync(), isTrue, reason: 'không xoá ra ngoài thư mục ảnh');

      final missing = sample()
        ..id = 'p3'
        ..name = 'Xe nhập'
        ..photo = 'khong-co.jpg';
      final imported = await repo.import(jsonEncode(missing.toJson()));
      expect(imported.photo, isNull);
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
    p.ch(1).trimUs = 30;
    p.ch(2).maxUs = 1900;
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
