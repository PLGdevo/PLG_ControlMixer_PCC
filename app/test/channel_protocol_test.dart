// Giao thức n kênh (CONTROL_US / INFO / FS_WRITE / FS_ACK) và CarController với xe giả
// n kênh lẫn firmware cũ 2 kênh.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/controller/car_controller.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/models/condition.dart';
import 'package:rc_controller/protocol/protocol.dart';
import 'package:rc_controller/services/arm_controller.dart';

import 'support/fake_car.dart';

String hexOf(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

CarProfile profile() => CarProfile(id: 'p', name: 'Xe', connType: ConnType.wifi);

Future<void> wait([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(mockWakelock);

  group('Gói n kênh', () {
    test('FS_WRITE của hồ sơ mặc định khớp vector firmware (test host protocol.h)', () {
      final p = profile();
      expect(hexOf(p.failsafeBytes()), '9001${'dc05' * 10}');
      expect(p.failsafeHash(), 0xce5e49da);
      expect(FakeCarTransport.fnv1a(p.failsafeBytes()), p.failsafeHash());
    });

    test('CONTROL_US: seq u16, µs little-endian, kẹp 500..2500', () {
      final f = decodeFrame(encodeControlUs(0x11234, [1000, 3000, 400]))!;
      expect(f.type, PacketType.controlUs);
      expect(hexOf(f.payload), '3412' 'e803' 'c409' 'f401');
      expect(decodeFrame(encodeControlUs(7, const []))!.payload, [7, 0]);
    });

    test('INFO / FS_ACK', () {
      final i = CarInfo.parse(Uint8List.fromList([2, 8]))!;
      expect((i.proto, i.channels), (2, 8));
      expect(CarInfo.parse(Uint8List.fromList([2])), isNull);
      expect(i.id, isNull, reason: 'firmware cũ không gửi mã xe');
      expect(CarInfo.parse(Uint8List.fromList([2, 8, 0x24, 0x0a, 0xc4, 0x12, 0xa1, 0xb2]))!.id, '24:0A:C4:12:A1:B2');
      final a = FsAck.parse(Uint8List.fromList([1, 0xda, 0x49, 0x5e, 0xce, 8]))!;
      expect((a.ok, a.hash, a.channels), (true, 0xce5e49da, 8));
      expect(FsAck.parse(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('CarController — firmware n kênh', () {
    late CarController c;
    late FakeCarTransport car;

    setUp(() async {
      c = CarController();
      car = FakeCarTransport(channels: 8);
      await c.connect(car);
    });

    tearDown(() async {
      await c.disconnect();
      c.dispose();
    });

    test('nhận ra xe 8 kênh', () {
      expect(c.multiChannel, isTrue);
      expect(c.carChannels, 8);
    });

    test('đồng bộ failsafe bằng FS_WRITE, không gửi lại khi failsafe không đổi', () async {
      final p = profile()..channels[2].failsafeUs = 1200;
      expect(await c.syncProfile(p), isTrue);
      expect(car.fsWrites.single, p.failsafeBytes());
      expect(car.configSets, isEmpty, reason: 'n kênh không ghi cấu hình servo xuống xe');
      expect(c.arm.state, ArmState.ready);

      p.channels[0].trimUs = 50; // sửa trim không làm failsafe đổi
      expect(await c.syncProfile(p), isFalse);
      expect(car.fsWrites, hasLength(1));

      p.failsafeTimeoutMs = 600;
      expect(await c.syncProfile(p), isTrue);
      expect(car.fsWrites, hasLength(2));
    });

    test('hash FS_ACK không khớp: báo lỗi, không cho ARM', () async {
      car.fsAckHash = 1;
      await expectLater(c.syncProfile(profile()), throwsException);
      expect(c.arm.syncFailed, isTrue);
      expect(c.arm.state, ArmState.connected);
    });

    test('chưa vào màn Lái gửi 0 kênh; READY gửi failsafe; ARMED gửi µs sau mix, cắt còn 8 kênh', () async {
      await wait();
      expect(car.controls.last.type, PacketType.controlUs);
      expect(car.controls.last.payload, hasLength(2), reason: '0 kênh');

      final p = profile()..channels[7].failsafeUs = 1111;
      await c.syncProfile(p);
      c.loadProfile(p);
      await wait();
      expect(c.lastSentUs, [for (final ch in p.channels.take(8)) ch.failsafeUs]);

      expect(c.arm.arm(const ArmCheck()), isNull);
      await wait();
      final pl = c.pipeline!;
      final want = pl.toUsList(pl.mixed()).sublist(0, 8);
      expect(c.lastSentUs, want);
      final f = car.controls.last;
      expect(f.type, PacketType.controlUs);
      expect(f.payload, hasLength(2 + 8 * 2));
      final b = ByteData.sublistView(f.payload);
      expect([for (var i = 0; i < 8; i++) b.getUint16(2 + i * 2, Endian.little)], want);
    });
  });

  group('CarController — tắt cơ chế ARM', () {
    late CarController c;
    late FakeCarTransport car;

    setUp(() async {
      c = CarController();
      car = FakeCarTransport(channels: 8);
      await c.connect(car);
    });

    tearDown(() async {
      await c.disconnect();
      c.dispose();
    });

    test('vào màn Lái là tự ARM khi thả ga, bỏ qua điều kiện ARM riêng; màn Lái ẩn thì gửi failsafe', () async {
      final p = profile()
        ..arm.enabled = false
        ..arm.armCondition = const ExprNot(ExprTrue()); // luôn sai: bị bỏ qua khi tắt ARM
      p.channels[0].failsafeUs = 1234;
      await c.syncProfile(p);
      c.loadProfile(p);
      var chk = const ArmCheck(throttleAtRest: false);
      c.armCheck = () => chk;
      await wait();
      expect(c.arm.state, ArmState.ready);
      expect(c.lastSentUs[0], 1234);

      chk = const ArmCheck();
      c.setPosition('steer', 100);
      await wait();
      expect(c.arm.armed, isTrue);
      expect(c.lastSentUs[0], 1900);

      chk = const ArmCheck(paused: true); // mở Cấu hình / app xuống nền
      await wait();
      expect(c.arm.state, ArmState.ready);
      expect(c.lastSentUs[0], 1234);

      chk = const ArmCheck();
      await wait();
      expect(c.arm.armed, isTrue);
    });

    test('bật lại cơ chế ARM: không tự ARM, điều kiện ARM riêng có tác dụng', () async {
      final p = profile()..arm.armCondition = const ExprNot(ExprTrue());
      await c.syncProfile(p);
      c.loadProfile(p);
      c.armCheck = () => const ArmCheck();
      await wait();
      expect(c.arm.state, ArmState.ready);
      expect(c.arm.arm(c.currentArmCheck()!), contains('Điều kiện'));
    });
  });

  group('CarController — cấu hình trực tiếp (Thử trên xe)', () {
    late CarController c;
    late FakeCarTransport car;

    setUp(() async {
      c = CarController();
      car = FakeCarTransport(channels: 8);
      await c.connect(car);
    });

    tearDown(() async {
      await c.disconnect();
      c.dispose();
    });

    test('chưa bật Thử thì gửi failsafe; bật Thử thì kênh theo cấu hình đang sửa, trim có tác dụng ngay', () async {
      final p = profile();
      p.channels[0].failsafeUs = 1234;
      await c.syncProfile(p);
      c.updateLive(p.copy()); // màn Cấu hình mở từ màn chính: tự nạp hồ sơ
      expect(c.live, isTrue);
      await wait();
      expect(c.lastSentUs[0], 1234);

      c.setTesting(true);
      expect(c.testing, isTrue);
      await wait();
      expect(c.lastSentUs[0], 1500); // Lái ở vị trí nghỉ = Center

      final edited = p.copy()..channels[0].trimUs = 40;
      c.updateLive(edited);
      await wait();
      expect(c.lastSentUs[0], 1540);

      c.setTest(1, 100); // kéo thanh Xem trước của CH1
      await wait();
      expect(c.lastSentUs[0], 1900);
      c.setTest(1, null); // thả tay
      await wait();
      expect(c.lastSentUs[0], 1540);

      c.endLive(p);
      expect(c.testing, isFalse);
      expect(c.pipeline, isNull, reason: 'Cấu hình tự nạp thì trả vòng gửi khi rời màn');
      await wait();
      expect(c.lastSentUs, isEmpty);
    });

    test('không bật được Thử khi chưa đồng bộ failsafe; ngắt kết nối thì tự tắt', () async {
      final p = profile();
      c.updateLive(p.copy());
      c.setTesting(true);
      expect(c.testing, isFalse);
      expect(c.testBlock, isNotNull);
      await c.syncProfile(p);
      c.setTesting(true);
      expect(c.testing, isTrue);
      await c.disconnect();
      expect(c.testing, isFalse);
    });

    test('mở từ màn Lái: rời Cấu hình thì nạp lại hồ sơ đã lưu, giữ vòng gửi của màn Lái', () async {
      final p = profile();
      await c.syncProfile(p);
      c.loadProfile(p); // màn Lái
      c.updateLive(p.copy()..channels[0].trimUs = 50);
      c.endLive(p);
      expect(c.pipeline, isNotNull);
      expect(c.pipeline!.profile.channels[0].trimUs, 0);
    });
  });

  test('firmware cũ: không trả INFO → lái 2 kênh, đồng bộ bằng cấu hình servo', () async {
    final c = CarController();
    final car = FakeCarTransport(channels: null);
    await c.connect(car);
    expect(c.multiChannel, isFalse);
    expect(c.carChannels, 2);

    final p = profile()..channels[0].trimUs = 30;
    expect(await c.syncProfile(p), isTrue);
    expect(car.fsWrites, isEmpty);
    expect(car.configSets.single, p.toCarConfig().toBytes());
    expect(c.arm.state, ArmState.ready);

    await wait();
    expect(car.controls.last.type, PacketType.control);
    await c.disconnect();
    c.dispose();
  });

  group('Nhận đúng xe theo mã (INFO mang MAC)', () {
    const mine = '24:0A:C4:12:A1:B2', other = '24:0A:C4:99:88:77';

    test('xe trả đúng mã: kết nối, đọc được mã xe', () async {
      final c = CarController();
      await c.connect(FakeCarTransport(id: mine), expectId: mine.toLowerCase());
      expect(c.error, isNull);
      expect(c.isConnected, isTrue);
      expect(c.carInfo!.id, mine);
      await c.disconnect();
      c.dispose();
    });

    test('IP đã thuộc về xe khác: từ chối, không gửi lệnh lái', () async {
      final c = CarController();
      final car = FakeCarTransport(id: other);
      await c.connect(car, expectId: mine);
      expect(c.isConnected, isFalse);
      expect(c.error, contains('sai xe'));
      expect(c.error, contains(other));
      await wait();
      expect(car.controls, isEmpty);
      c.dispose();
    });

    test('firmware chưa gửi mã: vẫn kết nối (không kiểm tra được)', () async {
      final c = CarController();
      await c.connect(FakeCarTransport(), expectId: mine);
      expect(c.isConnected, isTrue);
      expect(c.carInfo!.id, isNull);
      await c.disconnect();
      c.dispose();
    });
  });

  group('Chất lượng liên kết khi đang nối (ping ngầm 1 lần/giây, LQ)', () {
    test('nối xong là ping ngay, có ping trung bình; ngắt thì hết số', () async {
      final c = CarController();
      final car = FakeCarTransport();
      expect(c.pingMs, isNull);
      await c.connect(car);
      await wait(100);
      expect(car.pings, 1, reason: 'gói đầu gửi ngay khi nối, sau đó 1 gói mỗi giây');
      expect(c.pingMs, isNotNull);
      await c.disconnect();
      expect(c.pingMs, isNull);
      expect(c.linkQuality, isNull);
      c.dispose();
    });

    test('xuống nền thì ngừng ping, lên lại thì ping tiếp', () async {
      final c = CarController();
      final car = FakeCarTransport();
      c.background = true;
      await c.connect(car);
      await wait(100);
      expect(car.pings, 0);
      c.background = false;
      await wait(100);
      expect(car.pings, 1);
      await c.disconnect();
      c.dispose();
    });

    test('LQ theo tỉ lệ telemetry về tới; mất nhiều gói thì báo tín hiệu yếu', () async {
      final c = CarController();
      final car = FakeCarTransport();
      await c.connect(car);
      expect(c.linkQuality, isNull, reason: 'mới nối chưa đủ dữ liệu');
      // Đủ gói 10 Hz trong 1 giây
      for (var i = 0; i < 10; i++) {
        car.telemetry();
        await wait(100);
      }
      expect(c.linkQuality, greaterThanOrEqualTo(90));
      expect(c.weakLink, isFalse);
      // Chỉ về 1/3 số gói
      for (var i = 0; i < 15; i++) {
        if (i % 3 == 0) car.telemetry();
        await wait(100);
      }
      expect(c.linkQuality, lessThan(CarController.weakLq));
      expect(c.weakLink, isTrue);
      await c.disconnect();
      c.dispose();
    });
  });
}
