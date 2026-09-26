// Ping nhanh (F4): kiểm tra xe có phản hồi không mà không cần kết nối hẳn.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller/car_controller.dart';
import '../l10n/lang.dart';
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
  /// Nếu đang kết nối đúng xe này thì ping qua kết nối hiện có.
  static Future<QuickPingResult> run({
    required bool ble,
    String? ip,
    int? port,
    String? bleId,
    CarController? controller,
    String? connectedKey,
  }) async {
    final key = ble ? 'ble:$bleId' : 'wifi:$ip:$port';
    final c = controller;
    if (c != null && c.isConnected && c.transport != null && connectedKey == key) {
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
    return _measure(t, close: true);
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
