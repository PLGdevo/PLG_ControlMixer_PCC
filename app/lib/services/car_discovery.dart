// Dò xe trong mạng (chế độ Router: IP do router cấp nên có thể đổi).
// Gửi DISCOVER broadcast tới cổng 4211, xe trả HERE thẳng về máy hỏi.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../protocol/net_protocol.dart';
import '../protocol/protocol.dart';

class FoundCar {
  final String id; // MAC gốc của xe
  final String ip;
  final int port;
  final String name;
  final NetMode mode;

  const FoundCar({required this.id, required this.ip, required this.port, required this.name, required this.mode});
}

abstract final class CarDiscovery {
  /// Gom các xe trả lời trong `timeout`. Có `id` thì trả về ngay khi thấy đúng xe đó.
  /// `targets` / `port` chỉ để test; mặc định là broadcast của mọi mạng IPv4 trên máy.
  static Future<List<FoundCar>> scan({
    String? id,
    Duration timeout = const Duration(milliseconds: 1500),
    List<InternetAddress>? targets,
    int port = discoveryPort,
  }) async {
    final RawDatagramSocket sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      return const [];
    }
    sock.broadcastEnabled = true;
    final nonce = Random().nextInt(0x10000);
    final found = <String, FoundCar>{};
    final hit = Completer<void>();

    sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      for (var d = sock.receive(); d != null; d = sock.receive()) {
        final f = decodeFrame(d.data);
        if (f == null || f.type != PacketType.here) continue;
        final h = HereInfo.parse(f.payload);
        if (h == null || h.nonce != nonce) continue;
        // Dùng địa chỉ gửi gói trả lời: đó là đường chắc chắn tới được xe
        found[h.id] = FoundCar(id: h.id, ip: d.address.address, port: h.port, name: h.name, mode: h.mode);
        if (id != null && h.id == id.toUpperCase() && !hit.isCompleted) hit.complete();
      }
    });

    final frame = encodeDiscover(nonce);
    final dest = targets ?? await _broadcastTargets();
    final end = DateTime.now().add(timeout);
    // Gửi 3 lần phòng mất gói, dừng sớm khi thấy xe cần tìm
    for (var i = 0; i < 3 && !hit.isCompleted; i++) {
      for (final a in dest) {
        try {
          sock.send(frame, a, port);
        } catch (_) {}
      }
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) break;
      await Future.any([hit.future, Future<void>.delayed(left < _gap ? left : _gap)]);
    }
    final left = end.difference(DateTime.now());
    if (!hit.isCompleted && left > Duration.zero) {
      await Future.any([hit.future, Future<void>.delayed(left)]);
    }
    sock.close();
    return found.values.toList();
  }

  static const _gap = Duration(milliseconds: 300);

  /// 255.255.255.255 và broadcast /24 của từng địa chỉ IPv4 trên máy
  /// (một số Android bỏ gói gửi tới 255.255.255.255)
  static Future<List<InternetAddress>> _broadcastTargets() async {
    final out = <String>{'255.255.255.255'};
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          final b = a.rawAddress;
          if (b.length == 4 && b[0] != 127) out.add('${b[0]}.${b[1]}.${b[2]}.255');
        }
      }
    } catch (_) {}
    return [for (final s in out) InternetAddress(s)];
  }
}
