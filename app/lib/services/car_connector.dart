// Nối xe của một hồ sơ: dò xe trong mạng (chế độ Router), mở kết nối, đồng bộ failsafe.
// Dùng chung cho màn chính (thẻ xe) và thanh trên cùng của màn Lái / Cấu hình.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../transport/ble_transport.dart';
import '../transport/transport.dart';
import '../transport/udp_transport.dart';
import 'car_discovery.dart';

abstract final class CarConnector {
  /// Chế độ Router: IP do router cấp có thể đổi → dò xe theo mã xe, cập nhật hồ sơ nếu IP/port khác.
  /// Trả về hồ sơ (có thể đã sửa) và cờ "có thấy xe trong mạng".
  static Future<(CarProfile, bool)> locate(ProfileRepository repo, CarProfile p) async {
    final id = p.wifi?.carId;
    if (p.connType != ConnType.wifi || id == null) return (p, true);
    final hit = (await CarDiscovery.scan(id: id, timeout: const Duration(milliseconds: 1200)))
        .where((f) => f.id == id.toUpperCase())
        .firstOrNull;
    if (hit == null) return (p, false);
    final w = p.wifi!;
    if (hit.ip == w.ip && hit.port == w.port) return (p, true);
    final fresh = repo.get(p.id) ?? p;
    fresh.wifi!
      ..ip = hit.ip
      ..port = hit.port;
    await repo.save(fresh, touch: false);
    return (fresh, true);
  }

  /// Nối xe của hồ sơ `profileId`. Trả về các thông báo cho người dùng (lỗi / cảnh báo), rỗng = ổn.
  /// Đang nối một hồ sơ khác thì không làm gì.
  static Future<List<String>> connect(CarController c, ProfileRepository repo, String profileId) async {
    final profile = repo.get(profileId);
    if (profile == null || c.connectingKey != null || c.state == LinkState.connecting) return const [];
    // Nối xe nào thì xe đó thành xe đang chọn (một xe hoạt động tại một thời điểm, như tay RC)
    await repo.select(profileId);
    c.setConnecting(profile.connKey);
    try {
      return await _connect(c, repo, profile);
    } finally {
      c.setConnecting(null);
    }
  }

  static Future<List<String>> _connect(CarController c, ProfileRepository repo, CarProfile profile) async {
    final (p, found) = await locate(repo, profile);
    final CarTransport t;
    if (p.connType == ConnType.ble) {
      final mac = p.ble?.mac ?? '';
      if (mac.isEmpty) {
        return [tr('Hồ sơ chưa có MAC. Bấm Sửa để chọn xe BLE.', 'This profile has no MAC yet. Tap Edit to pick a BLE car.')];
      }
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      t = BleTransport(BluetoothDevice.fromId(mac));
    } else {
      t = UdpTransport(p.wifi!.ip, p.wifi!.port);
    }
    await c.connect(t, key: p.connKey, expectId: p.connType == ConnType.wifi ? p.wifi?.carId : null);
    if (c.error != null) {
      return [
        found
            ? c.error!
            : tr(
                '${c.error!}. Không thấy xe trong mạng: kiểm tra điện thoại và xe cùng router (không dùng mạng khách). '
                    'Xe không vào được router thì sau 15 giây tự phát WiFi riêng.',
                '${c.error!}. Car not found on the network: make sure the phone and the car use the same router '
                    '(not a guest network). If the car cannot join the router it starts its own WiFi after 15 seconds.')
      ];
    }
    final fresh = repo.get(p.id);
    if (fresh == null) return const [];
    fresh.lastConnectedAt = DateTime.now();
    // Hồ sơ nhập IP tay: ghi nhớ mã xe vừa nối, lần sau dò đúng xe khi IP đổi và không nhầm sang xe khác
    final id = c.carInfo?.id;
    if (fresh.connType == ConnType.wifi && fresh.wifi!.carId == null && id != null) fresh.wifi!.carId = id;
    await repo.save(fresh, touch: false);
    // Không có bước "đọc từ xe": hồ sơ trong app luôn được đưa xuống xe (E6)
    try {
      await c.syncProfile(fresh);
      final n = c.carChannels;
      if (!c.multiChannel) {
        return [
          tr('Firmware xe cũ: chỉ lái được CH1/CH2. Nạp firmware mới để dùng đủ kênh.',
              'Old car firmware: only CH1/CH2 can be driven. Flash the new firmware to use every channel.')
        ];
      }
      if (fresh.channels.any((ch) => ch.enabled && ch.index > n)) {
        return [tr('Xe chỉ có $n kênh: các kênh sau CH$n không xuất ra', 'The car has only $n channels: channels after CH$n are not output')];
      }
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      return [tr('Không đồng bộ được cấu hình với xe: $m', 'Could not sync the configuration with the car: $m')];
    }
    return const [];
  }
}
