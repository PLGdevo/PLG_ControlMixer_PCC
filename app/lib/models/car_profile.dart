// Hồ sơ xe (E1, Sprint 4 — J1): kết nối + toàn bộ cấu hình, sửa được khi chưa nối xe.
// Cấu hình điều khiển: Input (I) → Condition (K) → luật mix (M) → kênh (O).
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../l10n/lang.dart';
import '../layout/layout_templates.dart';
import '../protocol/protocol.dart';
import 'channel_config.dart';
import 'condition.dart';
import 'control_layout.dart';
import 'input_def.dart';
import 'mixer_rule.dart';
import 'ping_config.dart';

enum ConnType { wifi, ble }

class WifiConn {
  String ip; // chế độ Router: IP lần cuối thấy xe
  int port;
  String? ssid;

  /// MAC gốc của xe (đọc từ xe). Có thì app tự dò xe trong mạng khi IP đổi.
  String? carId;

  WifiConn({this.ip = '192.168.4.1', this.port = 4210, this.ssid, this.carId});

  Map<String, dynamic> toJson() => {'ip': ip, 'port': port, 'ssid': ssid, if (carId != null) 'carId': carId};

  factory WifiConn.fromJson(Map<String, dynamic> j) => WifiConn(
        ip: j['ip'] as String? ?? '192.168.4.1',
        port: j['port'] as int? ?? 4210,
        ssid: j['ssid'] as String?,
        carId: j['carId'] as String?,
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

/// Cài đặt ARM (R2)
class ArmConfig {
  bool autoArm;
  Expr? armCondition; // null = không có điều kiện riêng

  ArmConfig({this.autoArm = false, this.armCondition});

  Map<String, dynamic> toJson() => {
        'autoArm': autoArm,
        if (armCondition != null) 'armCondition': armCondition!.toJson(),
      };

  factory ArmConfig.fromJson(Map<String, dynamic>? j) => ArmConfig(
        autoArm: j?['autoArm'] as bool? ?? false,
        armCondition: j?['armCondition'] == null ? null : Expr.fromJson(j!['armCondition']),
      );
}

/// Giao thức đầu ra (O4)
class OutputConfig {
  String protocol;
  int periodMs;

  OutputConfig({this.protocol = 'rc_v2', this.periodMs = 25});

  Map<String, dynamic> toJson() => {'protocol': protocol, 'periodMs': periodMs};

  factory OutputConfig.fromJson(Map<String, dynamic>? j) =>
      OutputConfig(protocol: j?['protocol'] as String? ?? 'rc_v2', periodMs: j?['periodMs'] as int? ?? 25);
}

class CarProfile {
  static const schemaVersion = 2;

  String id;
  String name;
  String? icon;

  /// Ảnh đại diện: tên file trong thư mục ảnh của ProfileRepository, null = biểu tượng xe
  String? photo;
  ConnType connType;
  WifiConn? wifi;
  BleConn? ble;
  GearConfig gears;
  int failsafeTimeoutMs;
  List<ChannelConfig> channels; // đúng 10 phần tử

  /// Kênh Ga do người dùng chọn (null = không có): hộp số, kiểm tra thả ga khi ARM, cảnh báo cần ga
  int? throttleCh;

  /// Kênh Lái do người dùng chọn (null = không có): ô trim nhanh trên màn Lái
  int? steeringCh;
  List<InputDef> inputs;
  List<ConditionDef> conditions;
  List<MixRule> mixer;
  ArmConfig arm;
  OutputConfig output;
  PingConfig ping;
  List<ControlLayout> layouts;
  String activeLayoutId;
  DateTime updatedAt;
  DateTime? lastSyncedAt;
  String? lastSyncedHash;
  DateTime? lastConnectedAt;

  /// Hồ sơ mới (không truyền `inputs` / `layouts` / `mixer`) được dựng như mẫu "Xe cơ bản" (U5).
  /// Màn tạo xe luôn áp mẫu người dùng chọn lên hồ sơ, mặc định là mẫu "Trống".
  CarProfile({
    required this.id,
    required this.name,
    this.icon,
    this.photo,
    required this.connType,
    this.wifi,
    this.ble,
    GearConfig? gears,
    this.failsafeTimeoutMs = 400,
    List<ChannelConfig>? channels,
    this.throttleCh,
    this.steeringCh,
    List<InputDef>? inputs,
    List<ConditionDef>? conditions,
    List<MixRule>? mixer,
    ArmConfig? arm,
    OutputConfig? output,
    PingConfig? ping,
    List<ControlLayout>? layouts,
    String? activeLayoutId,
    DateTime? updatedAt,
    this.lastSyncedAt,
    this.lastSyncedHash,
    this.lastConnectedAt,
  })  : gears = gears ?? GearConfig(),
        channels = channels ?? ChannelConfig.defaultList(),
        inputs = inputs ?? [],
        conditions = conditions ?? [],
        mixer = mixer ?? [],
        arm = arm ?? ArmConfig(),
        output = output ?? OutputConfig(),
        ping = ping ?? PingConfig(),
        layouts = layouts ?? [],
        activeLayoutId = activeLayoutId ?? '',
        updatedAt = updatedAt ?? DateTime.now() {
    if (inputs == null && layouts == null && mixer == null) {
      ProfileTemplate.basic.applyTo(this);
    }
    if (this.layouts.isEmpty) this.layouts.add(LayoutTemplates.standard());
    if (!this.layouts.any((l) => l.id == this.activeLayoutId)) this.activeLayoutId = this.layouts.first.id;
  }

  static String newId() {
    final r = Random();
    String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }

  ChannelConfig ch(int index) => channels[index - 1];
  ChannelConfig? get throttle => throttleCh == null ? null : ch(throttleCh!);
  ChannelConfig? get steering => steeringCh == null ? null : ch(steeringCh!);

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

  // ---------------- Input · luật ----------------
  InputDef? input(String? id) => id == null ? null : inputs.where((i) => i.id == id).firstOrNull;

  Map<String, InputDef> get inputMap => {for (final i in inputs) i.id: i};

  /// Tên hiển thị của kênh: "CH3" hoặc "CH3 · Đèn"
  String chLabel(int n) {
    final c = ch(n);
    return c.hasDefaultName ? 'CH$n' : 'CH$n · ${c.name}';
  }

  /// Luật đang bật ghi vào kênh `ch`
  List<MixRule> rulesTo(int ch) => mixer.where((r) => r.enabled && r.destCh == ch).toList();

  /// Luật dùng Input `id` làm nguồn hoặc trong điều kiện
  List<MixRule> rulesUsing(String id) =>
      mixer.where((r) => r.source == id || r.condition.inputs.contains(id)).toList();

  /// Input (không phải hằng số) đang là nguồn của luật bật ghi vào kênh `ch`
  Set<String> driversOf(int ch) => {
        for (final r in rulesTo(ch))
          if (input(r.source)?.type != InputType.constant) r.source,
      };

  /// Input đang điều khiển kênh Ga / Lái đã chọn (rỗng nếu hồ sơ không chọn kênh đó)
  Set<String> get throttleInputs => throttleCh == null ? const {} : driversOf(throttleCh!);
  Set<String> get steeringInputs => steeringCh == null ? const {} : driversOf(steeringCh!);

  /// Input điều khiển kênh Ga (dùng cho cảnh báo tự về và "ga Giữ vị trí về Center" — H3b)
  bool isThrottleInput(String? id) => id != null && throttleInputs.contains(id);

  /// Luật "gắn nhanh" của Input (U5): không điều kiện, weight 100, offset 0, tuyến tính, replace, priority 0
  static bool isPlain(MixRule r) =>
      r.condition.isTrue &&
      r.weightPct == 100 &&
      r.offsetPct == 0 &&
      r.curve.isLinear &&
      r.minPct == -100 &&
      r.maxPct == 100 &&
      r.combine == Combine.replace &&
      r.priority == 0;

  /// Kênh mà Input được gắn nhanh tới; null nếu chưa gắn. Ném [StateError] nếu cấu hình
  /// phức tạp hơn (nhiều luật / có điều kiện) — khi đó giao diện chuyển sang tab Mix.
  int? quickRoute(String inputId) {
    final rs = rulesUsing(inputId);
    if (rs.isEmpty) return null;
    if (rs.length == 1 && rs.first.source == inputId && isPlain(rs.first)) return rs.first.destCh;
    throw StateError(tr('Input có cấu hình mix phức tạp', 'Input has a complex mix setup'));
  }

  bool canQuickRoute(String inputId) {
    try {
      quickRoute(inputId);
      return true;
    } on StateError {
      return false;
    }
  }

  /// Gắn nhanh Input → kênh (U5): tạo / sửa / xoá luật mặc định; gắn thì bật kênh
  void setQuickRoute(String inputId, int? ch) {
    mixer.removeWhere((r) => r.source == inputId && isPlain(r));
    if (ch == null) return;
    mixer.add(MixRule(id: InputDef.uniqueId('r_$inputId', mixer.map((r) => r.id)), source: inputId, destCh: ch));
    this.ch(ch).enabled = true;
  }

  /// Tạo Input mới phù hợp với loại phần tử
  InputDef createInput(ItemKind kind, {String? name, String? baseId}) {
    final type = InputDef.typeFor(kind);
    final base = baseId ??
        switch (kind) {
          ItemKind.stickH || ItemKind.stickV || ItemKind.stick2D => 'stick',
          ItemKind.knob => 'knob',
          ItemKind.toggle => 'toggle',
          ItemKind.switch3 => 'switch',
          _ => 'button',
        };
    final id = InputDef.uniqueId(base, inputs.map((i) => i.id));
    final n = inputs.where((i) => i.type == type).length + 1;
    final d = InputDef(id: id, name: name ?? '${kind.label} $n', type: type);
    if (d.name.length > 24) d.name = d.name.substring(0, 24);
    inputs.add(d);
    return d;
  }

  /// Xoá Input: gỡ khỏi mọi bố cục, các luật / điều kiện dùng nó bị tắt (K1)
  void deleteInput(String id) {
    inputs.removeWhere((i) => i.id == id);
    for (final l in layouts) {
      l.unbindInput(id);
    }
    for (final r in mixer) {
      if (r.source == id || r.condition.inputs.contains(id)) r.enabled = false;
    }
  }

  /// Đổi mã Input ở mọi nơi (bố cục, luật, điều kiện)
  void renameInput(String from, String to) {
    if (from == to) return;
    input(from)?.id = to;
    for (final l in layouts) {
      l.renameInput(from, to);
    }
    for (final r in mixer) {
      if (r.source == from) r.source = to;
      r.condition = r.condition.renameInput(from, to);
    }
    for (final c in conditions) {
      c.expr = c.expr.renameInput(from, to);
    }
    final a = arm.armCondition;
    if (a != null) arm.armCondition = a.renameInput(from, to);
  }

  /// Đưa cấu hình (kênh, mix, hộp số, failsafe) về mặc định; giữ tên, kết nối, Input, bố cục và
  /// kênh Ga/Lái đã chọn. Luật mix về dạng tối thiểu: Input đang điều khiển kênh Lái / Ga → kênh đó.
  void resetConfig() {
    final steer = steeringInputs.firstOrNull, thr = throttleInputs.firstOrNull;
    channels = ChannelConfig.defaultList(steeringCh: steeringCh, throttleCh: throttleCh);
    conditions = [];
    mixer = [
      if (steer != null) MixRule(id: 'r_steer', source: steer, destCh: steeringCh!),
      if (thr != null) MixRule(id: 'r_throttle', source: thr, destCh: throttleCh!),
    ];
    gears = GearConfig();
    failsafeTimeoutMs = 400;
    arm = ArmConfig();
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

  /// Gói cấu hình firmware v1 (2 kênh): CH1 → chân lái, CH2 → chân ga của xe, bất kể kênh Ga/Lái
  /// chọn trong hồ sơ. Hộp số do app áp lên kênh Ga đã chọn nên xe nhận giới hạn 100% mọi số.
  CarConfig toCarConfig() => CarConfig(
        throttle: _servo(ch(2)),
        steering: _servo(ch(1)),
        failsafeTimeoutMs: failsafeTimeoutMs,
        gearCount: gears.gearCount,
        gearLimit: List<int>.filled(GearConfig.maxGears, 100),
      );

  /// Nạp cấu hình kiểu cũ (đọc từ xe) vào CH1/CH2. Hộp số không nạp: xe chỉ giữ giới hạn 100%.
  void applyCarConfig(CarConfig c) {
    _fromServo(ch(1), c.steering);
    _fromServo(ch(2), c.throttle);
    failsafeTimeoutMs = c.failsafeTimeoutMs;
  }

  // ---------------- Kiểm tra (E7, V) ----------------
  /// Lỗi của các trường chung (tên, kết nối, hộp số, failsafe). `otherNames` để chống trùng tên.
  Map<String, String> validateGeneral({Iterable<String> otherNames = const []}) {
    final e = <String, String>{};
    final n = name.trim();
    if (n.isEmpty || n.length > 32) {
      e['name'] = tr('Tên xe dài 1–32 ký tự', 'Car name must be 1–32 characters');
    } else if (otherNames.any((o) => o.trim().toLowerCase() == n.toLowerCase())) {
      e['name'] = tr('Đã có xe khác tên này', 'Another car already has this name');
    }
    if (connType == ConnType.wifi) {
      final w = wifi;
      if (w == null || !isValidIpv4(w.ip)) e['ip'] = tr('Địa chỉ IPv4 không hợp lệ', 'Invalid IPv4 address');
      if (w == null || w.port < 1 || w.port > 65535) e['port'] = tr('Port trong khoảng 1–65535', 'Port must be 1–65535');
      final id = w?.carId;
      if (id != null && !isValidMac(id)) e['carId'] = tr('Mã xe dạng AA:BB:CC:DD:EE:FF', 'Car ID format: AA:BB:CC:DD:EE:FF');
    } else {
      final b = ble;
      if (b == null || (b.mac.trim().isEmpty && b.deviceName.trim().isEmpty)) {
        e['ble'] = tr('Cần chọn xe hoặc nhập MAC/tên', 'Pick a car or enter a MAC/name');
      } else if (b.mac.trim().isNotEmpty && !isValidMac(b.mac.trim())) {
        e['ble'] = tr('MAC dạng AA:BB:CC:DD:EE:FF', 'MAC format: AA:BB:CC:DD:EE:FF');
      }
    }
    if (failsafeTimeoutMs < 100 || failsafeTimeoutMs > 3000) {
      e['failsafeTimeout'] = tr('Thời gian failsafe trong khoảng 100–3000 ms', 'Failsafe timeout must be 100–3000 ms');
    }
    for (final (c, k) in [(throttleCh, 'throttleCh'), (steeringCh, 'steeringCh')]) {
      if (c != null && (c < 1 || c > 10)) e[k] = tr('Kênh phải trong CH1–CH10', 'Channel must be CH1–CH10');
    }
    if (throttleCh != null && throttleCh == steeringCh) e['steeringCh'] = tr('Kênh Lái trùng kênh Ga', 'Steering channel is the same as the throttle channel');
    if (gears.gearCount < 1 || gears.gearCount > GearConfig.maxGears) e['gearCount'] = tr('Số lượng số 1–5', 'Gear count must be 1–5');
    for (var i = 0; i < gears.gearCount; i++) {
      final g = gears.maxThrottle[i];
      if (g < 1 || g > 100) e['gear$i'] = tr('Ga tối đa số ${i + 1} phải 1–100%', 'Max throttle in gear ${i + 1} must be 1–100%');
    }
    return e;
  }

  /// Kênh Ga / Lái đã chọn nhưng chưa có luật, hoặc bố cục thiếu phần tử cho Input điều khiển nó (V).
  /// Chỉ là cảnh báo: hồ sơ không bắt buộc có kênh Ga/Lái, và người dùng có thể chọn kênh trước
  /// rồi mới dựng luật / bố cục. Trả về câu cảnh báo hoặc null.
  String? roleWarning({required bool throttle}) {
    final ch = throttle ? throttleCh : steeringCh;
    if (ch == null) return null;
    final label = throttle ? tr('Ga', 'throttle') : tr('Lái', 'steering');
    if (rulesTo(ch).isEmpty) return tr('Chưa có luật mix nào điều khiển kênh $label (CH$ch)', 'No mix rule drives the $label channel (CH$ch)');
    final drivers = driversOf(ch);
    if (drivers.isEmpty) return null; // chỉ có luật hằng số: không cần phần tử
    for (final l in layouts) {
      if (!drivers.any((d) => l.itemForInput(d) != null)) {
        return tr('Bố cục "${l.name}" chưa có phần tử cho kênh $label (CH$ch)', 'Layout "${l.name}" has no control for the $label channel (CH$ch)');
      }
    }
    return null;
  }

  /// Kiểm tra Input / Condition / luật (V)
  ({List<String> errors, List<String> warnings}) validateMixerPart() {
    final r = validateMixer(
      inputs: inputs,
      conditions: conditions,
      rules: mixer,
      disabledChannels: {for (final c in channels) if (!c.enabled) c.index},
    );
    final ids = inputMap;
    final condIds = {for (final c in conditions) c.id};
    final a = arm.armCondition;
    if (a != null) {
      final e = a.validate(ids, condIds);
      if (e != null) r.errors.add(tr('Điều kiện ARM: $e', 'ARM condition: $e'));
    }
    for (final l in layouts) {
      for (final it in l.items) {
        for (final id in it.inputIds) {
          final d = ids[id];
          if (d == null) {
            r.errors.add(tr('Bố cục "${l.name}": phần tử gắn Input "$id" không tồn tại', 'Layout "${l.name}": a control is bound to missing Input "$id"'));
          } else if (!d.accepts(it.kind)) {
            r.errors.add(tr('Bố cục "${l.name}": ${it.kind.label.toLowerCase()} không gắn được Input ${d.type.label.toLowerCase()} "${d.name}"', 'Layout "${l.name}": ${it.kind.label.toLowerCase()} cannot take ${d.type.label.toLowerCase()} Input "${d.name}"'));
          }
        }
      }
    }
    final used = {for (final m in mixer.where((m) => m.enabled)) ...[m.source, ...m.condition.inputs]};
    for (final id in used) {
      final d = ids[id];
      if (d == null || d.type == InputType.constant) continue;
      if (activeLayout.itemForInput(id) == null) {
        r.warnings.add(tr('Input "${d.name}" được luật mix dùng nhưng chưa có phần tử trên bố cục "${activeLayout.name}"', 'Input "${d.name}" is used by a mix rule but has no control on layout "${activeLayout.name}"'));
      }
    }
    for (final throttle in [true, false]) {
      final w = roleWarning(throttle: throttle);
      if (w != null) r.warnings.add(w);
    }
    return r;
  }

  /// Toàn bộ lỗi của hồ sơ, dạng danh sách câu, dùng để khoá nút Lưu
  List<String> validateAll({Iterable<String> otherNames = const []}) {
    final errs = <String>[...validateGeneral(otherNames: otherNames).values];
    for (final c in channels) {
      final e = c.validate();
      if (e.isNotEmpty) errs.add('${c.label}: ${e.values.first}');
    }
    errs.addAll(validateMixerPart().errors);
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
        if (photo != null) 'photo': photo,
        'connType': connType.name,
        'wifi': wifi?.toJson(),
        'ble': ble?.toJson(),
        'gears': gears.toJson(),
        'failsafeTimeoutMs': failsafeTimeoutMs,
        'channels': channels.map((c) => c.toJson()).toList(),
        'throttleCh': throttleCh,
        'steeringCh': steeringCh,
        'inputs': inputs.map((i) => i.toJson()).toList(),
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'mixer': mixer.map((m) => m.toJson()).toList(),
        'arm': arm.toJson(),
        'output': output.toJson(),
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
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        [for (final e in (j[k] as List? ?? const [])) f(e as Map<String, dynamic>)];
    final chList = list('channels', ChannelConfig.fromJson);
    final channels = List.generate(
      10,
      (i) => chList.where((c) => c.index == i + 1).firstOrNull ?? ChannelConfig.defaults(i + 1),
    );
    return CarProfile(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Xe',
      icon: j['icon'] as String?,
      photo: j['photo'] as String?,
      connType: ConnType.values.asNameMap()[j['connType']] ?? ConnType.wifi,
      wifi: j['wifi'] == null ? null : WifiConn.fromJson(j['wifi'] as Map<String, dynamic>),
      ble: j['ble'] == null ? null : BleConn.fromJson(j['ble'] as Map<String, dynamic>),
      gears: GearConfig.fromJson(j['gears'] as Map<String, dynamic>?),
      failsafeTimeoutMs: j['failsafeTimeoutMs'] as int? ?? 400,
      channels: channels,
      // Hồ sơ lưu trước khi chọn được kênh Ga/Lái (không có khoá): Lái CH1, Ga CH2 như cũ
      throttleCh: j.containsKey('throttleCh') ? j['throttleCh'] as int? : 2,
      steeringCh: j.containsKey('steeringCh') ? j['steeringCh'] as int? : 1,
      inputs: list('inputs', InputDef.fromJson),
      conditions: list('conditions', ConditionDef.fromJson),
      mixer: list('mixer', MixRule.fromJson),
      arm: ArmConfig.fromJson(j['arm'] as Map<String, dynamic>?),
      output: OutputConfig.fromJson(j['output'] as Map<String, dynamic>?),
      ping: PingConfig.fromJson(j['ping'] as Map<String, dynamic>?),
      layouts: list('layouts', ControlLayout.fromJson),
      activeLayoutId: j['activeLayoutId'] as String?,
      updatedAt: dt('updatedAt'),
      lastSyncedAt: dt('lastSyncedAt'),
      lastSyncedHash: j['lastSyncedHash'] as String?,
      lastConnectedAt: dt('lastConnectedAt'),
    );
  }

  CarProfile copy() => CarProfile.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

/// Mẫu khởi đầu ở bước 3 tạo xe (E3), dựng bằng Input + luật mặc định (U5)
enum ProfileTemplate {
  blank('Trống', 'Blank', 'Chưa có Input, luật mix hay kênh Ga/Lái. Tự thêm phần tử và gắn vào kênh bạn muốn',
      'No Inputs, mix rules or throttle/steering channels. Add controls yourself and route them to any channel'),
  basic('Xe cơ bản 2 kênh', 'Basic 2-channel car', 'Lái (CH1) và Ga (CH2)', 'Steering (CH1) and throttle (CH2)'),
  lightsHorn('Xe có đèn/còi', 'Car with lights/horn', 'Thêm Đèn (CH3, bật/tắt) và Còi (CH4, nhấn giữ)',
      'Adds Lights (CH3, on/off) and Horn (CH4, push)'),
  copy('Sao chép từ xe khác', 'Copy from another car', 'Lấy Input, mix, kênh, hộp số và bố cục của một xe có sẵn',
      'Takes Inputs, mix, channels, gears and layout from an existing car');

  const ProfileTemplate(this._vi, this._en, this._descVi, this._descEn);
  final String _vi, _en, _descVi, _descEn;

  String get label => tr(_vi, _en);
  String get description => tr(_descVi, _descEn);

  /// Áp mẫu lên hồ sơ mới (giữ id, tên, kết nối)
  void applyTo(CarProfile p, {CarProfile? source}) {
    if (this == ProfileTemplate.copy) {
      final s = source;
      if (s == null) return;
      final c = s.copy();
      p
        ..channels = c.channels
        ..throttleCh = c.throttleCh
        ..steeringCh = c.steeringCh
        ..inputs = c.inputs
        ..conditions = c.conditions
        ..mixer = c.mixer
        ..arm = c.arm
        ..output = c.output
        ..gears = c.gears
        ..failsafeTimeoutMs = c.failsafeTimeoutMs
        ..ping = c.ping
        ..layouts = c.layouts
        ..activeLayoutId = c.activeLayoutId;
      return;
    }
    if (this == ProfileTemplate.blank) {
      p
        ..channels = ChannelConfig.defaultList()
        ..throttleCh = null
        ..steeringCh = null
        ..inputs = []
        ..conditions = []
        ..mixer = []
        ..layouts = [LayoutTemplates.blank()];
      p.activeLayoutId = p.layouts.first.id;
      return;
    }
    p
      ..channels = ChannelConfig.defaultList(steeringCh: 1, throttleCh: 2)
      ..steeringCh = 1
      ..throttleCh = 2
      ..inputs = [
        InputDef(id: 'steer', name: tr('Lái', 'Steering')),
        InputDef(id: 'throttle', name: tr('Ga', 'Throttle')),
      ]
      ..conditions = []
      ..mixer = [
        MixRule(id: 'r_steer', source: 'steer', destCh: 1),
        MixRule(id: 'r_throttle', source: 'throttle', destCh: 2),
      ]
      ..layouts = [LayoutTemplates.standard()];
    p.activeLayoutId = p.layouts.first.id;
    if (this == ProfileTemplate.lightsHorn) {
      final l = p.activeLayout;
      p.ch(3)
        ..name = tr('Đèn', 'Lights')
        ..failsafeUs = 1000;
      p.ch(4)
        ..name = tr('Còi', 'Horn')
        ..failsafeUs = 1000;
      p.inputs.addAll([
        InputDef(id: 'light', name: tr('Đèn', 'Lights'), type: InputType.binary),
        InputDef(id: 'horn', name: tr('Còi', 'Horn'), type: InputType.binary),
      ]);
      p
        ..setQuickRoute('light', 3)
        ..setQuickRoute('horn', 4);
      LayoutTemplates.addControl(l, ItemKind.toggle, inputId: 'light');
      LayoutTemplates.addControl(l, ItemKind.button, inputId: 'horn');
    }
  }
}
