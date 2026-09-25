// Hồ sơ xe (E1): kết nối + toàn bộ cấu hình, sửa được khi chưa nối xe.
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../layout/layout_templates.dart';
import '../protocol/protocol.dart';
import 'channel_config.dart';
import 'control_layout.dart';
import 'mix_rule.dart';
import 'ping_config.dart';

enum ConnType { wifi, ble }

class WifiConn {
  String ip;
  int port;
  String? ssid;

  WifiConn({this.ip = '192.168.4.1', this.port = 4210, this.ssid});

  Map<String, dynamic> toJson() => {'ip': ip, 'port': port, 'ssid': ssid};

  factory WifiConn.fromJson(Map<String, dynamic> j) => WifiConn(
        ip: j['ip'] as String? ?? '192.168.4.1',
        port: j['port'] as int? ?? 4210,
        ssid: j['ssid'] as String?,
      );
}

class BleConn {
  String mac;
  String deviceName;

  BleConn({this.mac = '', this.deviceName = ''});

  Map<String, dynamic> toJson() => {'mac': mac, 'deviceName': deviceName};

  factory BleConn.fromJson(Map<String, dynamic> j) =>
      BleConn(mac: j['mac'] as String? ?? '', deviceName: j['deviceName'] as String? ?? '');
}

class GearConfig {
  static const maxGears = 5;
  int gearCount;
  List<int> maxThrottle; // % cho từng số, luôn 5 phần tử

  GearConfig({this.gearCount = 3, List<int>? maxThrottle})
      : maxThrottle = maxThrottle ?? [30, 60, 100, 100, 100];

  Map<String, dynamic> toJson() => {'gearCount': gearCount, 'maxThrottle': maxThrottle};

  factory GearConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return GearConfig();
    final list = (j['maxThrottle'] as List?)?.map((e) => e as int).toList() ?? [30, 60, 100, 100, 100];
    while (list.length < maxGears) {
      list.add(100);
    }
    return GearConfig(gearCount: j['gearCount'] as int? ?? 3, maxThrottle: list.take(maxGears).toList());
  }
}

class CarProfile {
  static const schemaVersion = 1;
  static const steeringCh = 1; // channels[0]
  static const throttleCh = 2; // channels[1]

  String id;
  String name;
  String? icon;
  ConnType connType;
  WifiConn? wifi;
  BleConn? ble;
  GearConfig gears;
  int failsafeTimeoutMs;
  List<ChannelConfig> channels; // đúng 10 phần tử
  List<MixRule> mixes; // tối đa MixRule.maxRules (20)
  PingConfig ping;
  List<ControlLayout> layouts;
  String activeLayoutId;
  DateTime updatedAt;
  DateTime? lastSyncedAt;
  String? lastSyncedHash;
  DateTime? lastConnectedAt;

  CarProfile({
    required this.id,
    required this.name,
    this.icon,
    required this.connType,
    this.wifi,
    this.ble,
    GearConfig? gears,
    this.failsafeTimeoutMs = 400,
    List<ChannelConfig>? channels,
    List<MixRule>? mixes,
    PingConfig? ping,
    List<ControlLayout>? layouts,
    String? activeLayoutId,
    DateTime? updatedAt,
    this.lastSyncedAt,
    this.lastSyncedHash,
    this.lastConnectedAt,
  })  : gears = gears ?? GearConfig(),
        channels = channels ?? ChannelConfig.defaultList(),
        mixes = mixes ?? [],
        ping = ping ?? PingConfig(),
        layouts = layouts ?? [],
        activeLayoutId = activeLayoutId ?? '',
        updatedAt = updatedAt ?? DateTime.now() {
    if (this.layouts.isEmpty) this.layouts.add(LayoutTemplates.standard());
    if (!this.layouts.any((l) => l.id == this.activeLayoutId)) this.activeLayoutId = this.layouts.first.id;
  }

  static String newId() {
    final r = Random();
    String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }

  ChannelConfig ch(int index) => channels[index - 1];
  ChannelConfig get steering => ch(steeringCh);
  ChannelConfig get throttle => ch(throttleCh);

  ControlLayout get activeLayout =>
      layouts.firstWhere((l) => l.id == activeLayoutId, orElse: () => layouts.first);

  /// Mô tả kết nối cho thẻ hồ sơ
  String get connLabel => connType == ConnType.wifi
      ? '${wifi?.ip ?? '?'}:${wifi?.port ?? '?'}'
      : (ble?.deviceName.isNotEmpty == true ? ble!.deviceName : (ble?.mac ?? '?'));

  /// Khoá nhận diện kết nối, khớp với `CarController.connectedKey`
  String get connKey => connType == ConnType.wifi
      ? 'wifi:${wifi?.ip}:${wifi?.port}'
      : 'ble:${(ble?.mac ?? '').toUpperCase()}';

  /// Phần tử điều khiển kênh `ch` trên bố cục đang dùng (null = chưa gán)
  ControlItem? controlOf(int ch) => activeLayout.itemForChannel(ch);

  /// Gán kênh `ch` vào phần tử `item` của bố cục `l` (mặc định bố cục đang dùng) và bật kênh.
  /// Trả về phần tử bị gỡ kênh này (nếu có).
  ControlItem? assignChannel(ControlItem item, int ch, {bool y = false, ControlLayout? l}) {
    final moved = (l ?? activeLayout).assignChannel(item, ch, y: y);
    this.ch(ch).enabled = true;
    return moved;
  }

  /// Đồng bộ bố cục sau khi bật/tắt kênh: kênh đang tắt được gỡ khỏi mọi phần tử.
  /// Phần tử vẫn giữ nguyên trên màn (cấu hình riêng), chỉ hiện "Chưa gán kênh".
  void syncLayouts() {
    for (final c in channels.where((c) => !c.enabled)) {
      for (final l in layouts) {
        l.unassignChannel(c.index);
      }
    }
  }

  /// Đưa cấu hình (kênh, mix, hộp số, failsafe) về mặc định; giữ tên, kết nối, bố cục
  void resetConfig() {
    channels = ChannelConfig.defaultList();
    mixes = [];
    gears = GearConfig();
    failsafeTimeoutMs = 400;
    syncLayouts();
  }

  // ---------------- Đổi qua lại với cấu hình firmware v1 (B5) ----------------
  static ServoChannel _servo(ChannelConfig c) => ServoChannel(
        minUs: c.minUs,
        centerUs: c.centerUs,
        maxUs: c.maxUs,
        trimUs: c.trimUs,
        offsetUs: c.offsetUs,
        reverse: c.reverse,
        failsafeUs: c.failsafeUs,
      );

  static void _fromServo(ChannelConfig c, ServoChannel s) {
    c
      ..minUs = s.minUs
      ..centerUs = s.centerUs
      ..maxUs = s.maxUs
      ..trimUs = s.trimUs
      ..offsetUs = s.offsetUs
      ..reverse = s.reverse
      ..failsafeUs = s.failsafeUs;
  }

  /// Gói cấu hình firmware hiện tại (2 kênh): CH1 → lái, CH2 → ga
  CarConfig toCarConfig() => CarConfig(
        throttle: _servo(throttle),
        steering: _servo(steering),
        failsafeTimeoutMs: failsafeTimeoutMs,
        gearCount: gears.gearCount,
        gearLimit: List<int>.from(gears.maxThrottle),
      );

  /// Nạp cấu hình kiểu cũ (đọc từ xe) vào CH1/CH2
  void applyCarConfig(CarConfig c) {
    _fromServo(steering, c.steering);
    _fromServo(throttle, c.throttle);
    failsafeTimeoutMs = c.failsafeTimeoutMs;
    gears = GearConfig(gearCount: c.gearCount, maxThrottle: List<int>.from(c.gearLimit));
  }

  // ---------------- Kiểm tra (E7) ----------------
  /// Lỗi của các trường chung (tên, kết nối, hộp số, failsafe). `otherNames` để chống trùng tên.
  Map<String, String> validateGeneral({Iterable<String> otherNames = const []}) {
    final e = <String, String>{};
    final n = name.trim();
    if (n.isEmpty || n.length > 32) {
      e['name'] = 'Tên xe dài 1–32 ký tự';
    } else if (otherNames.any((o) => o.trim().toLowerCase() == n.toLowerCase())) {
      e['name'] = 'Đã có xe khác tên này';
    }
    if (connType == ConnType.wifi) {
      final w = wifi;
      if (w == null || !isValidIpv4(w.ip)) e['ip'] = 'Địa chỉ IPv4 không hợp lệ';
      if (w == null || w.port < 1 || w.port > 65535) e['port'] = 'Port trong khoảng 1–65535';
    } else {
      final b = ble;
      if (b == null || (b.mac.trim().isEmpty && b.deviceName.trim().isEmpty)) {
        e['ble'] = 'Cần chọn xe hoặc nhập MAC/tên';
      } else if (b.mac.trim().isNotEmpty && !isValidMac(b.mac.trim())) {
        e['ble'] = 'MAC dạng AA:BB:CC:DD:EE:FF';
      }
    }
    if (failsafeTimeoutMs < 100 || failsafeTimeoutMs > 3000) {
      e['failsafeTimeout'] = 'Thời gian failsafe trong khoảng 100–3000 ms';
    }
    if (gears.gearCount < 1 || gears.gearCount > GearConfig.maxGears) e['gearCount'] = 'Số lượng số 1–5';
    for (var i = 0; i < gears.gearCount; i++) {
      final g = gears.maxThrottle[i];
      if (g < 1 || g > 100) e['gear$i'] = 'Ga tối đa số ${i + 1} phải 1–100%';
    }
    return e;
  }

  /// Bố cục thiếu phần tử cho kênh Ga hoặc Lái (H5). Trả về câu lỗi hoặc null.
  String? missingMainControl() {
    for (final l in layouts) {
      if (l.itemForChannel(throttleCh) == null) return 'Bố cục "${l.name}" chưa có phần tử cho kênh Ga (CH$throttleCh)';
      if (l.itemForChannel(steeringCh) == null) return 'Bố cục "${l.name}" chưa có phần tử cho kênh Lái (CH$steeringCh)';
    }
    return null;
  }

  /// Toàn bộ lỗi của hồ sơ, dạng danh sách câu, dùng để khoá nút Lưu
  List<String> validateAll({Iterable<String> otherNames = const []}) {
    final errs = <String>[...validateGeneral(otherNames: otherNames).values];
    for (final c in channels) {
      final e = c.validate();
      if (e.isNotEmpty) errs.add('${c.label}: ${e.values.first}');
    }
    final miss = missingMainControl();
    if (miss != null) errs.add(miss);
    final mixErr = MixRule.validateAll(mixes);
    if (mixErr != null) errs.add(mixErr);
    return errs;
  }

  static bool isValidIpv4(String s) {
    final parts = s.trim().split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) return false;
      if (p.length > 1 && p.startsWith('0')) return false;
      return int.parse(p) <= 255;
    });
  }

  static bool isValidMac(String s) => RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$').hasMatch(s);

  // ---------------- Hash failsafe (E5) ----------------
  /// Byte failsafe gửi trong FS_WRITE (C1): `timeout_ms:u16` · `fs[10]:u16`, little-endian
  Uint8List failsafeBytes() {
    final b = ByteData(22)..setUint16(0, failsafeTimeoutMs, Endian.little);
    for (var i = 0; i < 10; i++) {
      b.setUint16(2 + i * 2, channels[i].failsafeUs, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// FNV-1a 32 bit trên [failsafeBytes]; xe tính giống hệt để trả trong FS_ACK.
  /// Chỉ failsafe: sửa trim, Min/Max, mix, hộp số, bố cục không làm hồ sơ thành "chưa đồng bộ".
  int failsafeHash() {
    var h = 0x811c9dc5;
    for (final b in failsafeBytes()) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  // ---------------- JSON ----------------
  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'icon': icon,
        'connType': connType.name,
        'wifi': wifi?.toJson(),
        'ble': ble?.toJson(),
        'gears': gears.toJson(),
        'failsafeTimeoutMs': failsafeTimeoutMs,
        'channels': channels.map((c) => c.toJson()).toList(),
        'mixes': mixes.map((m) => m.toJson()).toList(),
        'ping': ping.toJson(),
        'layouts': layouts.map((l) => l.toJson()).toList(),
        'activeLayoutId': activeLayoutId,
        'updatedAt': updatedAt.toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastSyncedHash': lastSyncedHash,
        'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      };

  /// `j` phải đã qua ProfileMigration.migrate
  factory CarProfile.fromJson(Map<String, dynamic> j) {
    DateTime? dt(String k) => j[k] == null ? null : DateTime.tryParse(j[k] as String);
    final chList = (j['channels'] as List? ?? const [])
        .map((e) => ChannelConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    final channels = List.generate(
      10,
      (i) => chList.where((c) => c.index == i + 1).firstOrNull ?? ChannelConfig.defaults(i + 1),
    );
    return CarProfile(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Xe',
      icon: j['icon'] as String?,
      connType: ConnType.values.asNameMap()[j['connType']] ?? ConnType.wifi,
      wifi: j['wifi'] == null ? null : WifiConn.fromJson(j['wifi'] as Map<String, dynamic>),
      ble: j['ble'] == null ? null : BleConn.fromJson(j['ble'] as Map<String, dynamic>),
      gears: GearConfig.fromJson(j['gears'] as Map<String, dynamic>?),
      failsafeTimeoutMs: j['failsafeTimeoutMs'] as int? ?? 400,
      channels: channels,
      mixes: (j['mixes'] as List? ?? const []).map((e) => MixRule.fromJson(e as Map<String, dynamic>)).toList(),
      ping: PingConfig.fromJson(j['ping'] as Map<String, dynamic>?),
      layouts: (j['layouts'] as List? ?? const [])
          .map((e) => ControlLayout.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeLayoutId: j['activeLayoutId'] as String?,
      updatedAt: dt('updatedAt'),
      lastSyncedAt: dt('lastSyncedAt'),
      lastSyncedHash: j['lastSyncedHash'] as String?,
      lastConnectedAt: dt('lastConnectedAt'),
    );
  }

  CarProfile copy() => CarProfile.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

/// Mẫu khởi đầu ở bước 3 tạo xe (E3)
enum ProfileTemplate {
  basic('Xe cơ bản 2 kênh', 'Lái (CH1) và Ga (CH2)'),
  lightsHorn('Xe có đèn/còi', 'Thêm Đèn (CH3, bật/tắt) và Còi (CH4, nhấn giữ)'),
  copy('Sao chép từ xe khác', 'Lấy kênh, mix, hộp số và bố cục của một xe có sẵn');

  const ProfileTemplate(this.label, this.description);
  final String label, description;

  /// Áp mẫu lên hồ sơ mới (giữ id, tên, kết nối)
  void applyTo(CarProfile p, {CarProfile? source}) {
    if (this == ProfileTemplate.copy) {
      final s = source;
      if (s == null) return;
      final c = s.copy();
      p
        ..channels = c.channels
        ..mixes = c.mixes
        ..gears = c.gears
        ..failsafeTimeoutMs = c.failsafeTimeoutMs
        ..ping = c.ping
        ..layouts = c.layouts
        ..activeLayoutId = c.activeLayoutId;
      return;
    }
    p
      ..channels = ChannelConfig.defaultList()
      ..mixes = []
      ..layouts = [LayoutTemplates.standard()];
    p.activeLayoutId = p.layouts.first.id;
    if (this == ProfileTemplate.lightsHorn) {
      final l = p.activeLayout;
      p.ch(3)
        ..name = 'Đèn'
        ..enabled = true
        ..failsafeUs = 1000;
      p.ch(4)
        ..name = 'Còi'
        ..enabled = true
        ..failsafeUs = 1000;
      LayoutTemplates.addControl(l, ItemKind.toggle, channel: 3);
      LayoutTemplates.addControl(l, ItemKind.button, channel: 4);
    }
  }
}
