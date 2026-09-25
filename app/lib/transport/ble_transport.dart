import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

class BleUuids {
  static final service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final rx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // app ghi
  static final tx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // xe notify
}

class BleTransport implements CarTransport {
  BleTransport(this.device);

  final BluetoothDevice device;
  BluetoothCharacteristic? _rx;
  StreamSubscription? _valueSub, _stateSub;
  final _in = StreamController<Uint8List>.broadcast();
  final _lost = StreamController<void>.broadcast();
  bool _closing = false;

  @override
  String get name =>
      'BLE ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}';

  @override
  Stream<Uint8List> get incoming => _in.stream;

  @override
  Stream<void> get onLinkLost => _lost.stream;

  @override
  Future<void> open() async {
    _closing = false;
    await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
    if (Platform.isAndroid) {
      // Gói cấu hình 38 byte cần MTU lớn hơn mặc định (23)
      try {
        await device.requestMtu(185);
      } catch (_) {}
    }
    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid == BleUuids.service,
      orElse: () => throw Exception('Thiết bị không có service điều khiển RC'),
    );
    _rx = svc.characteristics.firstWhere((c) => c.uuid == BleUuids.rx);
    final tx = svc.characteristics.firstWhere((c) => c.uuid == BleUuids.tx);

    _valueSub = tx.onValueReceived.listen((v) => _in.add(Uint8List.fromList(v)));
    await tx.setNotifyValue(true);

    _stateSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_closing) _lost.add(null);
    });
  }

  @override
  Future<void> send(Uint8List data) async {
    await _rx?.write(data, withoutResponse: true);
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _valueSub?.cancel();
    await _stateSub?.cancel();
    _valueSub = null;
    _stateSub = null;
    _rx = null;
    await device.disconnect();
  }
}
