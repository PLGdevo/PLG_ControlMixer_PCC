import 'dart:async';
import 'dart:typed_data';

/// Lớp truyền dữ liệu trừu tượng — WiFi (UDP) và BLE cùng dùng chung giao thức.
abstract class CarTransport {
  String get name;

  /// Mỗi phần tử là 1 khung hoàn chỉnh nhận từ xe
  Stream<Uint8List> get incoming;

  /// Phát ra khi tầng dưới báo mất kết nối (vd BLE bị ngắt)
  Stream<void> get onLinkLost;

  Future<void> open();
  Future<void> send(Uint8List data);
  Future<void> close();
}
