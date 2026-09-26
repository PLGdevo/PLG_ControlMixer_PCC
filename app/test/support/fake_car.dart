// Xe giả trong bộ nhớ cho test CarController / màn Mạng của xe: trả lời CONFIG_GET và NET_*.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/models/car_profile.dart';
import 'package:rc_controller/protocol/net_protocol.dart';
import 'package:rc_controller/protocol/protocol.dart';
import 'package:rc_controller/transport/transport.dart';

Uint8List hex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

/// Payload do firmware thật dựng (net::encodeSection / encodeHere, in ra từ test C++ của net_config.h)
abstract final class FirmwareVectors {
  /// Router, UDP 4210, tên "RC-CAR"
  static final general = hex('010172100652432d434152');

  /// Kênh 1, 192.168.4.1, "RC-CAR", có mật khẩu (không gửi ra)
  static final ap = hex('0201c0a804010652432d434152ff');

  /// IP tĩnh 192.168.1.50 / gateway .1 / 255.255.255.0 / DNS trống, "Nha Minh", có mật khẩu
  static final sta = hex('0300c0a80132c0a80101ffffff0000000000084e6861204d696e68ff');

  /// Đang chạy Router, −55 dBm, 192.168.1.37, mã 24:0A:C4:12:A1:B2, còn 300 s, 1 máy
  static final status = hex('00010000c9c0a80125240ac412a1b22c0101');

  /// HERE nonce 0x1234 của xe trên
  static final here = hex('3412240ac412a1b2c0a801257210010652432d434152');
}

/// WakelockPlus gọi kênh pigeon khi kết nối; test không có plugin thật
void mockWakelock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
  );
}

class FakeCarTransport implements CarTransport {
  FakeCarTransport({Map<int, Uint8List>? sections})
      : sections = sections ??
            {
              NetSection.status: FirmwareVectors.status,
              NetSection.general: FirmwareVectors.general,
              NetSection.ap: FirmwareVectors.ap,
              NetSection.sta: FirmwareVectors.sta,
            };

  final Map<int, Uint8List> sections;
  final netSets = <Uint8List>[];
  int applied = 0, setups = 0, resets = 0;
  int ackStatus = NetAck.ok;

  final _in = StreamController<Uint8List>.broadcast();
  final _lost = StreamController<void>.broadcast();

  static final _config = CarProfile(id: 'x', name: 'x', connType: ConnType.wifi).toCarConfig().toBytes();

  @override
  String get name => 'Xe giả';

  @override
  Stream<Uint8List> get incoming => _in.stream;

  @override
  Stream<void> get onLinkLost => _lost.stream;

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> send(Uint8List data) async {
    final f = decodeFrame(data);
    if (f == null) return;
    switch (f.type) {
      case PacketType.configGet:
        _reply(PacketType.configData, _config);
      case PacketType.netGet:
        final s = sections[f.payload[0]];
        if (s != null) _reply(PacketType.netData, s);
      case PacketType.netSet:
        netSets.add(f.payload);
        _ack(f.type);
      case PacketType.netApply:
        applied++;
        _ack(f.type);
      case PacketType.netSetup:
        setups++;
        _ack(f.type);
      case PacketType.netReset:
        resets++;
        _ack(f.type);
    }
  }

  void _ack(int type) => _reply(PacketType.ack, [type, ackStatus]);

  void _reply(int type, List<int> payload) => scheduleMicrotask(() => _in.add(encodeFrame(type, payload)));
}
