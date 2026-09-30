// Ping nhanh (F4): kiểm tra xe có phản hồi không mà không cần kết nối hẳn.
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller/car_controller.dart';
import '../l10n/lang.dart';
import '../protocol/protocol.dart';
import '../transport/ble_transport.dart';
import '../transport/transport.dart';
import '../transport/udp_transport.dart';
import 'ping_service.dart';

class QuickPingResult {
  final bool ok;
  final double? rttMs;
  final String? error;

  const QuickPingResult.ok(this.rttMs)
      : ok = true,
        error = null;
  const QuickPingResult.fail(this.error)
      : ok = false,
        rttMs = null;

  String get label => ok ? '✓ ${rttMs!.round()} ms' : '✗ ${error ?? tr('Không phản hồi', 'No response')}';
}

abstract final class QuickPing {
  /// WiFi: 3 gói UDP thẳng tới IP:port. BLE: kết nối tạm → 3 ping → ngắt.
  /// `connectedHere`: đang kết nối đúng hồ sơ này (cùng IP/port) → ping qua kết nối hiện có.
  /// `expectId` (WiFi): mã xe của hồ sơ; PONG không mang mã xe nên hỏi INFO trước, sai xe thì báo lỗi.
  static Future<QuickPingResult> run({
    required bool ble,
    String? ip,
    int? port,
    String? bleId,
    CarController? controller,
    bool connectedHere = false,
    String? expectId,
  }) async {
    final c = controller;
    if (connectedHere && c != null && c.isConnected && c.transport != null) {
      return _measure(c.transport!, close: false);
    }
    final CarTransport t;
    if (ble) {
      if (bleId == null || bleId.isEmpty) return QuickPingResult.fail(tr('Chưa có MAC', 'No MAC yet'));
      t = BleTransport(BluetoothDevice.fromId(bleId));
    } else {
      if (ip == null || port == null) return QuickPingResult.fail(tr('Thiếu IP/port', 'Missing IP/port'));
      t = UdpTransport(ip, port);
    }
    try {
      await t.open();
    } catch (e) {
      try {
        await t.close();
      } catch (_) {}
      return QuickPingResult.fail(ble ? tr('Không kết nối được', 'Could not connect') : tr('IP không hợp lệ', 'Invalid IP'));
    }
    if (!ble && expectId != null) {
      final got = await _carId(t);
      if (got != null && got != expectId.toUpperCase()) {
        try {
          await t.close();
        } catch (_) {}
        return QuickPingResult.fail(tr('Sai xe: IP này là xe $got', 'Wrong car: this IP is car $got'));
      }
    }
    return _measure(t, close: true);
  }

  /// Hỏi INFO lấy mã xe; null = không trả lời hoặc firmware cũ không gửi mã (khi đó để ping tự báo)
  static Future<String?> _carId(CarTransport t) async {
    final got = Completer<String?>();
    final sub = t.incoming.listen((d) {
      final f = decodeFrame(d);
      if (f == null || f.type != PacketType.info || got.isCompleted) return;
      got.complete(CarInfo.parse(f.payload)?.id);
    });
    try {
      for (var i = 0; i < 3 && !got.isCompleted; i++) {
        try {
          await t.send(encodeFrame(PacketType.infoGet));
        } catch (_) {}
        await Future.any([got.future, Future<void>.delayed(const Duration(milliseconds: 300))]);
      }
      return got.isCompleted ? await got.future : null;
    } finally {
      await sub.cancel();
    }
  }

  static Future<QuickPingResult> _measure(CarTransport t, {required bool close}) async {
    final svc = PingService(t);
    try {
      final s = await svc.burst(count: 3, intervalMs: 150);
      return s.hasData ? QuickPingResult.ok(s.avgMs) : QuickPingResult.fail(tr('Không phản hồi', 'No response'));
    } catch (_) {
      return QuickPingResult.fail(tr('Không phản hồi', 'No response'));
    } finally {
      svc.dispose();
      if (close) {
        try {
          await t.close();
        } catch (_) {}
      }
    }
  }
}
