// Giao thức App <-> Xe — phải khớp với firmware/src/protocol.h
// Khung: [0xAA][type][len][payload][crc8], little-endian.
import 'dart:typed_data';

class PacketType {
  static const control = 0x01;
  static const telemetry = 0x02;
  static const configGet = 0x10;
  static const configData = 0x11;
  static const configSet = 0x12;
  static const configSave = 0x13;
  static const configReset = 0x14;
  static const ack = 0x20;
  // Ping (F1). Đặc tả C1 đặt PING ở 0x10, nhưng khung v1 đã dùng 0x10–0x14 cho cấu hình,
  // nên tới khi có giao thức v2 (Sprint 4) ping dùng 0x30–0x32.
  static const ping = 0x30;
  static const pong = 0x31;
  static const identify = 0x32;
  // Cấu hình mạng của xe và dò xe — payload ở net_protocol.dart
  static const netGet = 0x40;
  static const netData = 0x41;
  static const netSet = 0x42;
  static const netApply = 0x43;
  static const netSetup = 0x44;
  static const netReset = 0x45;
  static const discover = 0x46;
  static const here = 0x47;
}

const int frameHeader = 0xAA;
const _le = Endian.little;

int crc8(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

Uint8List encodeFrame(int type, [List<int> payload = const []]) {
  final out = Uint8List(4 + payload.length);
  out[0] = frameHeader;
  out[1] = type;
  out[2] = payload.length;
  out.setRange(3, 3 + payload.length, payload);
  out[3 + payload.length] = crc8(out.sublist(1, 3 + payload.length));
  return out;
}

class Frame {
  final int type;
  final Uint8List payload;
  const Frame(this.type, this.payload);
}

Frame? decodeFrame(List<int> buf) {
  if (buf.length < 4 || buf[0] != frameHeader) return null;
  final len = buf[2];
  if (buf.length != len + 4) return null;
  if (crc8(buf.sublist(1, 3 + len)) != buf[3 + len]) return null;
  return Frame(buf[1], Uint8List.fromList(buf.sublist(3, 3 + len)));
}

Uint8List encodeControl({
  required int throttle,
  required int steering,
  required int gear,
  required int seq,
}) {
  final b = ByteData(6)
    ..setInt16(0, throttle.clamp(-1000, 1000).toInt(), _le)
    ..setInt16(2, steering.clamp(-1000, 1000).toInt(), _le)
    ..setUint8(4, gear)
    ..setUint8(5, seq & 0xFF);
  return encodeFrame(PacketType.control, b.buffer.asUint8List());
}

class Telemetry {
  final int batteryMv, currentMa, speedCms, rssi, flags, gear, lastSeq;

  const Telemetry({
    required this.batteryMv,
    required this.currentMa,
    required this.speedCms,
    required this.rssi,
    required this.flags,
    required this.gear,
    required this.lastSeq,
  });

  bool get failsafe => (flags & 0x01) != 0;
  bool get armed => (flags & 0x02) != 0;
  bool get viaBle => (flags & 0x04) != 0;

  /// Xe đang ở chế độ cấu hình mạng (WiFi tạm), không nhận lệnh lái
  bool get netSetup => (flags & 0x08) != 0;
  double get batteryV => batteryMv / 1000;
  double get currentA => currentMa / 1000;
  double get speedKmh => speedCms * 0.036;

  static Telemetry? parse(Uint8List p) {
    if (p.length != 10) return null;
    final b = ByteData.sublistView(p);
    return Telemetry(
      batteryMv: b.getUint16(0, _le),
      currentMa: b.getInt16(2, _le),
      speedCms: b.getUint16(4, _le),
      rssi: b.getInt8(6),
      flags: b.getUint8(7),
      gear: b.getUint8(8),
      lastSeq: b.getUint8(9),
    );
  }
}

class ServoChannel {
  static const size = 13;
  int minUs, centerUs, maxUs, trimUs, offsetUs, failsafeUs;
  bool reverse;

  ServoChannel({
    required this.minUs,
    required this.centerUs,
    required this.maxUs,
    required this.trimUs,
    required this.offsetUs,
    required this.reverse,
    required this.failsafeUs,
  });

  factory ServoChannel.read(ByteData b, int o) => ServoChannel(
        minUs: b.getUint16(o, _le),
        centerUs: b.getUint16(o + 2, _le),
        maxUs: b.getUint16(o + 4, _le),
        trimUs: b.getInt16(o + 6, _le),
        offsetUs: b.getInt16(o + 8, _le),
        reverse: b.getUint8(o + 10) != 0,
        failsafeUs: b.getUint16(o + 11, _le),
      );

  void write(ByteData b, int o) {
    b
      ..setUint16(o, minUs, _le)
      ..setUint16(o + 2, centerUs, _le)
      ..setUint16(o + 4, maxUs, _le)
      ..setInt16(o + 6, trimUs, _le)
      ..setInt16(o + 8, offsetUs, _le)
      ..setUint8(o + 10, reverse ? 1 : 0)
      ..setUint16(o + 11, failsafeUs, _le);
  }

  /// Tâm thực tế mà xe sẽ xuất ra khi cần ở giữa
  int get effectiveCenter => (centerUs + trimUs + offsetUs).clamp(minUs, maxUs).toInt();

  ServoChannel copy() => ServoChannel(
        minUs: minUs,
        centerUs: centerUs,
        maxUs: maxUs,
        trimUs: trimUs,
        offsetUs: offsetUs,
        reverse: reverse,
        failsafeUs: failsafeUs,
      );

  /// Kiểm tra giống firmware; trả về thông báo lỗi hoặc null
  String? validate(String name) {
    if (minUs < 800 || maxUs > 2200) return '$name: Min/Max phải trong khoảng 800–2200 µs';
    if (!(minUs < centerUs && centerUs < maxUs)) return '$name: cần Min < Center < Max';
    if (trimUs.abs() > 200) return '$name: Trim trong khoảng ±200 µs';
    if (offsetUs.abs() > 300) return '$name: Offset trong khoảng ±300 µs';
    if (failsafeUs < minUs || failsafeUs > maxUs) return '$name: Failsafe phải nằm giữa Min và Max';
    return null;
  }
}

class CarConfig {
  static const size = 34;
  ServoChannel throttle, steering;
  int failsafeTimeoutMs, gearCount;
  List<int> gearLimit; // luôn 5 phần tử

  CarConfig({
    required this.throttle,
    required this.steering,
    required this.failsafeTimeoutMs,
    required this.gearCount,
    required this.gearLimit,
  });

  static CarConfig? parse(Uint8List p) {
    if (p.length != size) return null;
    final b = ByteData.sublistView(p);
    return CarConfig(
      throttle: ServoChannel.read(b, 0),
      steering: ServoChannel.read(b, 13),
      failsafeTimeoutMs: b.getUint16(26, _le),
      gearCount: b.getUint8(28),
      gearLimit: List<int>.generate(5, (i) => b.getUint8(29 + i)),
    );
  }

  Uint8List toBytes() {
    final b = ByteData(size);
    throttle.write(b, 0);
    steering.write(b, 13);
    b.setUint16(26, failsafeTimeoutMs, _le);
    b.setUint8(28, gearCount);
    for (var i = 0; i < 5; i++) {
      b.setUint8(29 + i, gearLimit[i]);
    }
    return b.buffer.asUint8List();
  }

  CarConfig copy() => CarConfig(
        throttle: throttle.copy(),
        steering: steering.copy(),
        failsafeTimeoutMs: failsafeTimeoutMs,
        gearCount: gearCount,
        gearLimit: List<int>.from(gearLimit),
      );

  String? validate() {
    final e = throttle.validate('Ga') ?? steering.validate('Lái');
    if (e != null) return e;
    if (failsafeTimeoutMs < 100 || failsafeTimeoutMs > 3000) {
      return 'Thời gian failsafe trong khoảng 100–3000 ms';
    }
    if (gearCount < 1 || gearCount > 5) return 'Số lượng số trong khoảng 1–5';
    for (var i = 0; i < gearCount; i++) {
      if (gearLimit[i] < 1 || gearLimit[i] > 100) return 'Giới hạn ga số ${i + 1} phải 1–100%';
    }
    return null;
  }
}

// ---------------- Ping (F1) ----------------
/// PING: `seq:u16` · `t_send:u32` (ms)
Uint8List encodePing(int seq, int tSendMs) {
  final b = ByteData(6)
    ..setUint16(0, seq & 0xFFFF, _le)
    ..setUint32(2, tSendMs & 0xFFFFFFFF, _le);
  return encodeFrame(PacketType.ping, b.buffer.asUint8List());
}

/// IDENTIFY: `duration_ms:u16`
Uint8List encodeIdentify(int durationMs) {
  final b = ByteData(2)..setUint16(0, durationMs.clamp(0, 0xFFFF).toInt(), _le);
  return encodeFrame(PacketType.identify, b.buffer.asUint8List());
}

class Pong {
  final int seq, tSendMs, uptimeMs;
  const Pong(this.seq, this.tSendMs, this.uptimeMs);

  /// PONG: `seq:u16` · `t_send:u32` · `uptime:u32`
  static Pong? parse(Uint8List p) {
    if (p.length != 10) return null;
    final b = ByteData.sublistView(p);
    return Pong(b.getUint16(0, _le), b.getUint32(2, _le), b.getUint32(6, _le));
  }
}
