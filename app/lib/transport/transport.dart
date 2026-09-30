import 'dart:async';
import 'dart:typed_data';

/// Lớp truyền dữ liệu trừu tượng — WiFi (UDP) và BLE cùng dùng chung giao thức.
abstract class CarTransport {
  String get name;

  /// Mỗi phần tử là 1 khung hoàn chỉnh nhận từ xe
  Stream<Uint8List> get incoming;

  /// Phát ra khi tầng dưới báo mất kết nối (vd BLE bị ngắt)
  Stream<void> get onLinkLost;

  /// Chu kỳ gửi lệnh lái. Gói ~22 byte: 100 Hz qua WiFi chỉ ~9 KB/s kể cả header, không đáng kể;
  /// BLE mỗi connection interval (7,5–50 ms) chỉ đẩy được vài gói nên chậm hơn.
  Duration get controlPeriod;

  Future<void> open();
  Future<void> send(Uint8List data);
  Future<void> close();
}
