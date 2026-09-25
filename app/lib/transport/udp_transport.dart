import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport.dart';

class UdpTransport implements CarTransport {
  UdpTransport(this.host, this.port);

  final String host;
  final int port;

  RawDatagramSocket? _socket;
  late InternetAddress _addr;
  final _in = StreamController<Uint8List>.broadcast();
  final _lost = StreamController<void>.broadcast();

  @override
  String get name => 'WiFi $host:$port';

  @override
  Stream<Uint8List> get incoming => _in.stream;

  @override
  Stream<void> get onLinkLost => _lost.stream;

  @override
  Future<void> open() async {
    _addr = InternetAddress(host); // ném lỗi nếu IP sai định dạng
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        while (true) {
          final d = s.receive();
          if (d == null) break;
          _in.add(d.data);
        }
      },
      onError: (_) => _lost.add(null),
    );
    _socket = s;
  }

  @override
  Future<void> send(Uint8List data) async {
    _socket?.send(data, _addr, port);
  }

  @override
  Future<void> close() async {
    _socket?.close();
    _socket = null;
  }
}
