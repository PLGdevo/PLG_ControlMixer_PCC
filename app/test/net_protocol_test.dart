// Cấu hình mạng của xe (NET_*) và dò xe (DISCOVER/HERE): khớp byte với firmware, kiểm tra dữ liệu,
// CarController đọc/ghi qua xe giả, CarDiscovery qua UDP loopback.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/protocol/net_protocol.dart';
import 'package:rc_controller/protocol/protocol.dart';
import 'package:rc_controller/services/car_discovery.dart';

import 'support/fake_car.dart';

NetConfig parsed() => NetConfig.parse(FirmwareVectors.general, FirmwareVectors.ap, FirmwareVectors.sta)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockWakelock);

  group('Khớp byte với firmware', () {
    test('Đọc trạng thái', () {
      final s = NetStatus.parse(FirmwareVectors.status)!;
      expect(s.mode, NetMode.sta);
      expect(s.fellBack, isFalse);
      expect(s.staResult, StaResult.none);
      expect(s.rssi, -55);
      expect(s.ip, '192.168.1.37');
      expect(s.id, '24:0A:C4:12:A1:B2');
      expect(s.setupLeftS, 300);
      expect(s.clients, 1);
      expect(s.setupSsid, 'RC-SETUP-A1B2');
      expect(NetStatus.parse(FirmwareVectors.status.sublist(0, 17)), isNull, reason: 'thiếu byte');
    });

    test('Đọc cấu hình: mật khẩu không bao giờ ra khỏi xe', () {
      final c = parsed();
      expect(c.bootMode, NetMode.sta);
      expect(c.udpPort, 4210);
      expect(c.name, 'RC-CAR');
      expect(c.apSsid, 'RC-CAR');
      expect(c.apChannel, 1);
      expect(c.apIp, '192.168.4.1');
      expect(c.apPass, isNull);
      expect(c.staSsid, 'Nha Minh');
      expect(c.staHasPass, isTrue);
      expect(c.staPass, isNull);
      expect(c.staDhcp, isFalse);
      expect(c.staIp, '192.168.1.50');
      expect(c.staGateway, '192.168.1.1');
      expect(c.staSubnet, '255.255.255.0');
      expect(c.staDns, '');
      expect(c.validate(), isEmpty);
    });

    test('Ghi lại không sửa gì ra đúng byte firmware (0xFF = giữ mật khẩu cũ)', () {
      final c = parsed();
      expect(c.sectionBytes(NetSection.general), FirmwareVectors.general);
      expect(c.sectionBytes(NetSection.ap), FirmwareVectors.ap);
      expect(c.sectionBytes(NetSection.sta), FirmwareVectors.sta);
    });

    test('Mật khẩu mới / mạng mở / tên WiFi có dấu', () {
      final c = parsed()
        ..staPass = ''
        ..apPass = 'matkhau123'
        ..staSsid = 'Nhà Minh';
      final sta = c.sectionBytes(NetSection.sta);
      expect(sta.last, 0, reason: 'mạng mở: độ dài 0');
      // SSID tính theo byte UTF-8: "à" là 2 byte
      expect(sta[18], 9);
      final ap = c.sectionBytes(NetSection.ap);
      expect(ap.sublist(ap.length - 11), [10, ...'matkhau123'.codeUnits]);
    });

    test('HERE', () {
      final h = HereInfo.parse(FirmwareVectors.here)!;
      expect(h.nonce, 0x1234);
      expect(h.id, '24:0A:C4:12:A1:B2');
      expect(h.ip, '192.168.1.37');
      expect(h.port, 4210);
      expect(h.mode, NetMode.sta);
      expect(h.name, 'RC-CAR');
      expect(encodeDiscover(0x1234), encodeFrame(PacketType.discover, [0x34, 0x12]));
    });

    test('Gói STA lớn nhất vừa khung (firmware MAX_PAYLOAD = 128)', () {
      final c = NetConfig(
        bootMode: NetMode.sta,
        staSsid: 'S' * 32,
        staPass: 'p' * 63,
        staDhcp: false,
        staIp: '192.168.100.200',
        staGateway: '192.168.100.1',
        staDns: '8.8.8.8',
      );
      expect(c.validate(), isEmpty);
      expect(c.sectionBytes(NetSection.sta).length, 115);
    });
  });

  group('Kiểm tra dữ liệu (giống net::validConfig)', () {
    test('Router cần SSID; mật khẩu 8–63 ký tự ASCII', () {
      final c = NetConfig(bootMode: NetMode.sta);
      expect(c.validate().keys, contains('staSsid'));
      c.staSsid = 'Nha';
      expect(c.validate(), isEmpty);
      c.staPass = 'short';
      expect(c.validate().keys, contains('staPass'));
      c.staPass = 'mậtkhẩu123';
      expect(c.validate().keys, contains('staPass'));
      c.staPass = '';
      expect(c.validate(), isEmpty, reason: 'mạng mở');
      c.apPass = '';
      expect(c.validate().keys, contains('apPass'), reason: 'WiFi riêng luôn phải có mật khẩu');
      c.bootMode = NetMode.ap;
      c.staSsid = '';
      c.apPass = null;
      expect(c.validate(), isEmpty, reason: 'chế độ AP không cần router');
    });

    test('IP tĩnh', () {
      final c = parsed();
      expect(c.validate(), isEmpty);
      c.staGateway = '192.168.2.1';
      expect(c.validate()['staGateway'], contains('cùng mạng'));
      c.staGateway = '192.168.1.1';
      c.staIp = '192.168.1.255';
      expect(c.validate().keys, contains('staIp'));
      c.staIp = '192.168.1.1';
      expect(c.validate().keys, contains('staIp'), reason: 'trùng gateway');
      c.staIp = '192.168.1.050';
      expect(c.validate().keys, contains('staIp'), reason: 'số 0 đứng đầu');
      c.staIp = '192.168.1.50';
      c.staSubnet = '255.0.255.0';
      expect(c.validate().keys, contains('staSubnet'));
      c.staSubnet = '255.255.255.0';
      c.staDns = '239.1.1.1';
      expect(c.validate().keys, contains('staDns'));
      c.staDns = '8.8.8.8';
      expect(c.validate(), isEmpty);
      c.staDhcp = true;
      c.staIp = 'rác';
      expect(c.validate(), isEmpty, reason: 'IP động bỏ qua ô IP tĩnh');
    });

    test('Tên, port, kênh, IP của AP', () {
      final c = NetConfig();
      expect(c.validate(), isEmpty);
      for (final bad in ['', '-xe', 'xe-', 'Xe_1', 'xe đỏ', 'a' * 21]) {
        c.name = bad;
        expect(c.validate().keys, contains('name'), reason: bad);
      }
      c.name = 'RC-CAR-2';
      c.udpPort = discoveryPort;
      expect(c.validate().keys, contains('udpPort'));
      c.udpPort = 0;
      expect(c.validate().keys, contains('udpPort'));
      c.udpPort = 5000;
      c.apChannel = 14;
      expect(c.validate().keys, contains('apChannel'));
      c.apChannel = 11;
      c.apIp = '10.0.0.255';
      expect(c.validate().keys, contains('apIp'));
      c.apIp = '10.0.0.1';
      expect(c.validate(), isEmpty);
    });

    test('maskPrefix', () {
      expect(maskPrefix([255, 255, 255, 0]), 24);
      expect(maskPrefix([255, 255, 252, 0]), 22);
      expect(maskPrefix([255, 0, 255, 0]), -1);
      expect(maskPrefix([0, 0, 0, 0]), 0);
    });
  });

  group('CarController với xe giả', () {
    test('Đọc trạng thái + cấu hình, ghi lại, xe khởi động lại thì app ngắt', () async {
      final c = CarController();
      final car = FakeCarTransport();
      await c.connect(car, key: 'wifi:x');
      expect(c.error, isNull);
      final st = await c.readNetStatus();
      expect(st.ip, '192.168.1.37');
      final cfg = await c.readNetConfig();
      expect(cfg.staSsid, 'Nha Minh');

      await c.applyNetConfig(cfg);
      expect(car.netSets, [FirmwareVectors.general, FirmwareVectors.ap, FirmwareVectors.sta]);
      expect(car.applied, 1);
      expect(c.state, LinkState.disconnected);
      c.dispose();
    });

    test('Xe đang chạy thì từ chối, báo lý do', () async {
      final c = CarController();
      final car = FakeCarTransport()..ackStatus = NetAck.busy;
      await c.connect(car, key: 'wifi:x');
      await expectLater(c.enterNetSetup(), throwsA(predicate((e) => '$e'.contains('Xe đang chạy'))));
      expect(c.isConnected, isTrue, reason: 'không ngắt khi xe từ chối');
      car.ackStatus = NetAck.ok;
      await c.resetNetConfig();
      expect(car.resets, 1);
      expect(c.state, LinkState.disconnected);
      c.dispose();
    });

    test('Cấu hình sai thì không gửi gì xuống xe', () async {
      final c = CarController();
      final car = FakeCarTransport();
      await c.connect(car, key: 'wifi:x');
      final cfg = await c.readNetConfig()
        ..apIp = '1.2.3';
      await expectLater(c.applyNetConfig(cfg), throwsException);
      expect(car.netSets, isEmpty);
      await c.disconnect();
      c.dispose();
    });
  });

  group('CarDiscovery', () {
    test('Lọc theo nonce, dùng địa chỉ gửi trả lời, dừng sớm khi thấy đúng xe', () async {
      final car = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      car.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = car.receive();
        final f = d == null ? null : decodeFrame(d.data);
        if (d == null || f == null || f.type != PacketType.discover) return;
        final rest = FirmwareVectors.here.sublist(2);
        // Gói nhiễu: nonce khác (trả lời cho lần tìm khác)
        final other = [f.payload[0] ^ 0xFF, f.payload[1], ...rest];
        car.send(encodeFrame(PacketType.here, other), d.address, d.port);
        car.send(encodeFrame(PacketType.here, Uint8List.fromList([...f.payload, ...rest])), d.address, d.port);
      });
      final sw = Stopwatch()..start();
      final found = await CarDiscovery.scan(
        id: '24:0a:c4:12:a1:b2',
        timeout: const Duration(seconds: 3),
        targets: [InternetAddress.loopbackIPv4],
        port: car.port,
      );
      sw.stop();
      car.close();
      expect(found, hasLength(1));
      expect(found.single.id, '24:0A:C4:12:A1:B2');
      expect(found.single.ip, '127.0.0.1');
      expect(found.single.port, 4210);
      expect(found.single.name, 'RC-CAR');
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('Không có xe thì hết giờ, trả danh sách rỗng', () async {
      final found = await CarDiscovery.scan(
        timeout: const Duration(milliseconds: 400),
        targets: [InternetAddress.loopbackIPv4],
        port: 9, // không ai nghe
      );
      expect(found, isEmpty);
    });
  });
}
