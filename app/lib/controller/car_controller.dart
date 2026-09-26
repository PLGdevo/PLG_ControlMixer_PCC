import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../protocol/net_protocol.dart';
import '../protocol/protocol.dart';
import '../services/arm_controller.dart';
import '../services/condition_engine.dart';
import '../services/output_pipeline.dart';
import '../transport/transport.dart';

enum LinkState { disconnected, connecting, connected, lost }

/// Quản lý kết nối, vòng gửi lệnh điều khiển, telemetry, cấu hình và ARM.
/// Mỗi chu kỳ: Input → Condition → Mixer (OutputPipeline); chỉ khi ARMED mới gửi kết quả mixer (R1).
class CarController extends ChangeNotifier {
  CarController() {
    arm.addListener(_onArmChanged);
  }

  static const controlPeriod = Duration(milliseconds: 25); // 40 Hz
  static const linkTimeout = Duration(milliseconds: 1000); // không có telemetry -> "mất tín hiệu"
  static const _ackKey = 0x2000;
  static const _netKey = 0x4100; // NET_DATA theo section

  CarTransport? _transport;
  StreamSubscription? _inSub, _lostSub;
  Timer? _controlTimer, _watchdog;
  bool _sending = false;
  int _seq = 0;
  final Map<int, Completer<Frame>> _waiters = {};

  LinkState state = LinkState.disconnected;
  String? error;

  /// Trạng thái ARM (R1–R3)
  final ArmController arm = ArmController();

  /// Chuỗi tính giá trị gửi đi của hồ sơ đang lái (null = chưa vào màn Lái)
  OutputPipeline? pipeline;
  CondNode? _armCond;

  /// Màn Lái cung cấp điều kiện ARM (R2) để tick mỗi chu kỳ
  ArmCheck Function()? armCheck;

  /// Vị trí cần gạt / núm (−100…+100) theo mã Input
  final Map<String, double> positions = {};

  /// Vị trí nút bật/tắt (0/1) và công tắc 3 nấc (0/1/2) theo mã Input — giữ nguyên khi thoát màn Lái
  final Map<String, int> switchPos = {};

  /// Số lượng số theo hồ sơ đang lái (null = theo cấu hình đọc từ xe)
  int? gearCountOverride;

  /// Khoá nhận diện kết nối hiện tại (vd "wifi:192.168.4.1:4210"), để ping nhanh dùng lại kết nối
  String? connectedKey;

  int gear = 1;
  Telemetry? telemetry;
  DateTime? lastTelemetryAt;
  CarConfig? config;

  /// Kết quả mixer gần nhất (10 kênh %), null nếu chưa nạp hồ sơ
  List<double>? get channelPct => pipeline?.lastPct;

  CarTransport? get transport => _transport;
  String? get transportName => _transport?.name;
  bool get isConnected => state == LinkState.connected || state == LinkState.lost;
  int get gearCount => gearCountOverride ?? config?.gearCount ?? 3;

  // ---------------- Kết nối ----------------
  Future<void> connect(CarTransport t, {String? key}) async {
    if (state != LinkState.disconnected) await disconnect();
    error = null;
    _setState(LinkState.connecting);
    try {
      _transport = t;
      await t.open();
      _inSub = t.incoming.listen(_onData);
      _lostSub = t.onLinkLost.listen((_) => _onTransportLost());

      // Bắt tay: xe phải trả lời cấu hình thì mới coi là kết nối thành công
      config = await _fetchConfig();

      gear = 1;
      connectedKey = key;
      arm.onConnected();
      lastTelemetryAt = DateTime.now();
      _controlTimer = Timer.periodic(controlPeriod, (_) => _sendControl());
      _watchdog = Timer.periodic(const Duration(milliseconds: 200), (_) => _checkLink());
      WakelockPlus.enable();
      _setState(LinkState.connected);
    } catch (e) {
      error = tr('Kết nối thất bại: ${_msg(e)}', 'Connection failed: ${_msg(e)}');
      await _teardown();
      _setState(LinkState.disconnected);
    }
  }

  Future<void> disconnect() async {
    final t = _transport;
    if (t != null && isConnected) {
      // Gửi lệnh trung tính vài lần trước khi ngắt
      for (var i = 0; i < 3; i++) {
        try {
          await t.send(_controlFrame(0, 0));
        } catch (_) {}
      }
    }
    await _teardown();
    _setState(LinkState.disconnected);
  }

  Future<void> _onTransportLost() async {
    error = tr('Mất kết nối với xe', 'Lost connection to the car');
    await _teardown();
    _setState(LinkState.disconnected);
  }

  Future<void> _teardown() async {
    _controlTimer?.cancel();
    _watchdog?.cancel();
    _controlTimer = null;
    _watchdog = null;
    await _inSub?.cancel();
    await _lostSub?.cancel();
    _inSub = null;
    _lostSub = null;
    for (final w in _waiters.values) {
      if (!w.isCompleted) w.completeError(StateError(tr('Đã ngắt kết nối', 'Disconnected')));
    }
    _waiters.clear();
    try {
      await _transport?.close();
    } catch (_) {}
    _transport = null;
    connectedKey = null;
    telemetry = null;
    _sending = false;
    arm.onDisconnected();
    WakelockPlus.disable();
  }

  void _onArmChanged() {
    if (!arm.armed) pipeline?.reset(); // DISARM: hysteresis + khoá an toàn về ban đầu
    notifyListeners();
  }

  // ---------------- Hồ sơ / Input ----------------
  /// Nạp (hoặc nạp lại sau khi sửa) hồ sơ đang lái; vị trí Input được giữ nguyên
  void loadProfile(CarProfile p) {
    final pl = pipeline;
    if (pl == null) {
      pipeline = OutputPipeline(p);
    } else {
      pl.update(p);
    }
    arm.autoArm = p.arm.autoArm;
    final a = p.arm.armCondition;
    _armCond = a == null ? null : pipeline!.mixer.conditions.compile(a);
    final im = pipeline!.inputs;
    positions.forEach(im.setPosition);
    switchPos.forEach(im.setSwitch);
  }

  /// Rời màn Lái: DISARM, bỏ hồ sơ khỏi vòng gửi
  void unloadProfile() {
    arm.disarm(tr('Thoát màn Lái', 'Left the drive screen'));
    armCheck = null;
    pipeline = null;
    _armCond = null;
  }

  /// Điều kiện ARM riêng của hồ sơ (R2) đang đúng
  bool get armConditionOk {
    final n = _armCond, pl = pipeline;
    if (n == null || pl == null) return true;
    return pl.mixer.conditions.eval(n, pl.inputs.state);
  }

  /// Cần gạt / núm gắn Input `id`: vị trí −100…+100
  void setPosition(String id, double pos, {bool notify = true}) {
    final v = pos.clamp(-100.0, 100.0).toDouble();
    positions[id] = v;
    pipeline?.inputs.setPosition(id, v);
    if (notify) notifyListeners();
  }

  /// Nút / công tắc gắn Input `id`: nấc 0/1 (bật/tắt) hoặc 0/1/2 (3 nấc)
  void setSwitch(String id, int pos, {bool notify = true}) {
    switchPos[id] = pos;
    pipeline?.inputs.setSwitch(id, pos);
    if (notify) notifyListeners();
  }

  double position(String id) => positions[id] ?? 0;
  int switchOf(String id) => switchPos[id] ?? 0;

  // ---------------- Điều khiển ----------------
  /// Báo giao diện vẽ lại sau khi sửa trực tiếp vị trí Input
  void refresh() => notifyListeners();

  void gearUp() {
    if (gear < gearCount) {
      gear++;
      notifyListeners();
    }
  }

  void gearDown() {
    if (gear > 1) {
      gear--;
      notifyListeners();
    }
  }

  Uint8List _controlFrame(double thr, double steer) {
    _seq = (_seq + 1) & 0xFF;
    return encodeControl(
      throttle: (thr * 1000).round(),
      steering: (steer * 1000).round(),
      gear: gear,
      seq: _seq,
    );
  }

  void _sendControl() {
    final t = _transport;
    if (t == null || _sending) return; // bỏ gói nếu gói trước chưa gửi xong (tránh dồn trễ)
    final pl = pipeline;
    var thr = 0.0, steer = 0.0;
    if (pl != null) {
      final pct = pl.mixed();
      final check = armCheck?.call();
      if (check != null) {
        arm.tick(ArmCheck(
          profileValid: check.profileValid,
          throttleAtRest: check.throttleAtRest,
          editing: check.editing,
          armConditionOk: armConditionOk,
        ));
      }
      // Giao thức v1 (cầu nối Sprint 3): xe tự áp servo, chỉ nhận CH1 (chân lái) và CH2 (chân ga).
      // Hộp số app đã áp lên kênh Ga người dùng chọn; xe giữ giới hạn 100% (toCarConfig).
      // Chưa ARM → gửi trung tính (giao thức v2 sẽ gửi failsafeUs — R1).
      if (arm.armed) {
        steer = pl.gearedPct(pct, 1, gear: gear) / 100;
        thr = pl.gearedPct(pct, 2, gear: gear) / 100;
      }
    }
    _sending = true;
    t.send(_controlFrame(thr, steer)).catchError((_) {}).whenComplete(() => _sending = false);
  }

  void _checkLink() {
    final last = lastTelemetryAt;
    if (state == LinkState.connected &&
        last != null &&
        DateTime.now().difference(last) > linkTimeout) {
      arm.disarm(tr('Mất tín hiệu', 'Signal lost'));
      _setState(LinkState.lost);
    }
  }

  // ---------------- Nhận dữ liệu ----------------
  void _onData(Uint8List data) {
    final f = decodeFrame(data);
    if (f == null) return;

    final key = switch (f.type) {
      PacketType.ack when f.payload.isNotEmpty => _ackKey | f.payload[0],
      PacketType.netData when f.payload.isNotEmpty => _netKey | f.payload[0],
      _ => f.type,
    };
    final w = _waiters.remove(key);
    if (w != null && !w.isCompleted) w.complete(f);

    if (f.type == PacketType.telemetry) {
      final t = Telemetry.parse(f.payload);
      if (t == null) return;
      telemetry = t;
      lastTelemetryAt = DateTime.now();
      if (t.failsafe && arm.armed) arm.onCarFailsafe();
      if (state == LinkState.lost) state = LinkState.connected;
      notifyListeners();
    }
  }

  /// Gửi yêu cầu và chờ phản hồi, tự thử lại nếu hết thời gian
  Future<Frame> _request(
    Uint8List frame,
    int expectKey, {
    int retries = 3,
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    for (var i = 0; i < retries; i++) {
      final t = _transport;
      if (t == null) throw StateError(tr('Chưa kết nối', 'Not connected'));
      final c = Completer<Frame>();
      _waiters[expectKey] = c;
      try {
        await t.send(frame);
        return await c.future.timeout(timeout);
      } on TimeoutException {
        continue;
      } finally {
        _waiters.remove(expectKey);
      }
    }
    throw TimeoutException(tr('Xe không phản hồi', 'The car is not responding'));
  }

  // ---------------- Cấu hình ----------------
  Future<CarConfig> _fetchConfig() async {
    final f = await _request(encodeFrame(PacketType.configGet), PacketType.configData);
    final c = CarConfig.parse(f.payload);
    if (c == null) throw Exception(tr('Dữ liệu cấu hình không hợp lệ', 'Invalid configuration data'));
    return c;
  }

  /// Áp dụng ngay trên xe (chưa lưu flash)
  Future<void> applyConfig(CarConfig c) async {
    final err = c.validate();
    if (err != null) throw Exception(err);
    final f = await _request(
      encodeFrame(PacketType.configSet, c.toBytes()),
      _ackKey | PacketType.configSet,
    );
    if (f.payload.length < 2 || f.payload[1] != 1) throw Exception(tr('Xe từ chối cấu hình', 'The car rejected the configuration'));
    config = c;
    if (gear > c.gearCount) gear = c.gearCount;
    notifyListeners();
  }

  Future<void> saveConfig() async {
    final f = await _request(encodeFrame(PacketType.configSave), _ackKey | PacketType.configSave);
    if (f.payload.length < 2 || f.payload[1] != 1) throw Exception(tr('Lưu thất bại', 'Save failed'));
  }

  Future<void> resetConfig() async {
    final f = await _request(encodeFrame(PacketType.configReset), PacketType.configData);
    final c = CarConfig.parse(f.payload);
    if (c == null) throw Exception(tr('Dữ liệu cấu hình không hợp lệ', 'Invalid configuration data'));
    config = c;
    if (gear > c.gearCount) gear = c.gearCount;
    notifyListeners();
  }

  /// Ghi cấu hình của hồ sơ xuống xe. `persist` = lưu vào flash của xe.
  Future<void> writeProfile(CarProfile p, {required bool persist}) async {
    await applyConfig(p.toCarConfig());
    if (persist) await saveConfig();
  }

  /// App là nguồn đúng (0.5): đưa cấu hình hồ sơ xuống xe nếu khác cấu hình xe đang có.
  /// Firmware v1 tự áp servo/failsafe nên phải ghi cả CH1/CH2; khi có giao thức v2
  /// (Sprint 4) hàm này chỉ còn gửi FS_WRITE. Trả về true nếu đã ghi.
  /// Kết quả được báo cho ArmController: đồng bộ được thì READY, lỗi thì không cho ARM (E6, R1).
  Future<bool> syncProfile(CarProfile p, {bool force = false}) async {
    final want = p.toCarConfig();
    final have = config;
    if (!force && have != null && listEquals(have.toBytes(), want.toBytes())) {
      arm.onFailsafeSync(true);
      return false;
    }
    try {
      await writeProfile(p, persist: true);
    } catch (_) {
      arm.onFailsafeSync(false);
      rethrow;
    }
    arm.onFailsafeSync(true);
    return true;
  }

  /// Trim nhanh từ màn hình lái (áp dụng ngay, bấm "Lưu" ở màn cấu hình để giữ lại)
  Future<void> adjustSteeringTrim(int deltaUs) async {
    final c = config;
    if (c == null) return;
    final n = c.copy();
    n.steering.trimUs = (n.steering.trimUs + deltaUs).clamp(-200, 200).toInt();
    await applyConfig(n);
  }

  // ---------------- Mạng của xe (dac_ta_wifi_3_che_do.md) ----------------
  /// Cấu hình mạng nằm trên xe (xe cần nó lúc khởi động), không nằm trong hồ sơ
  Future<NetStatus> readNetStatus() async {
    final s = NetStatus.parse(await _netGet(NetSection.status));
    if (s == null) throw Exception(tr('Dữ liệu trạng thái mạng không hợp lệ', 'Invalid network status data'));
    return s;
  }

  Future<NetConfig> readNetConfig() async {
    final g = await _netGet(NetSection.general);
    final a = await _netGet(NetSection.ap);
    final s = await _netGet(NetSection.sta);
    final c = NetConfig.parse(g, a, s);
    if (c == null) throw Exception(tr('Dữ liệu cấu hình mạng không hợp lệ (firmware cũ?)', 'Invalid network configuration data (old firmware?)'));
    return c;
  }

  Future<Uint8List> _netGet(int section) async {
    final f = await _request(encodeFrame(PacketType.netGet, [section]), _netKey | section);
    return f.payload;
  }

  /// Ghi cả 3 phần vào bản chờ trên xe rồi lưu. Xe trả ACK rồi tự khởi động lại, app ngắt kết nối.
  Future<void> applyNetConfig(NetConfig c) async {
    final errors = c.validate();
    if (errors.isNotEmpty) throw Exception(errors.values.first);
    for (final s in NetConfig.sections) {
      await _netCommand(PacketType.netSet, c.sectionBytes(s), tr('Xe từ chối cấu hình mạng', 'The car rejected the network configuration'));
    }
    await _netCommand(PacketType.netApply, const [], tr('Xe từ chối cấu hình mạng', 'The car rejected the network configuration'));
    await disconnect();
  }

  /// Khởi động lại xe vào chế độ cấu hình (WiFi tạm)
  Future<void> enterNetSetup() async {
    await _netCommand(PacketType.netSetup, const [], tr('Xe không vào được chế độ cấu hình', 'The car could not enter setup mode'));
    await disconnect();
  }

  /// Mạng của xe về mặc định (WiFi riêng RC-CAR / 12345678, 192.168.4.1, UDP 4210)
  Future<void> resetNetConfig() async {
    await _netCommand(PacketType.netReset, const [], tr('Xe không khôi phục được mạng', 'The car could not reset its network'));
    await disconnect();
  }

  Future<void> _netCommand(int type, List<int> payload, String failMsg) async {
    final f = await _request(encodeFrame(type, payload), _ackKey | type);
    final status = f.payload.length < 2 ? NetAck.fail : f.payload[1];
    if (status == NetAck.busy) throw Exception(tr('Xe đang chạy: dừng xe (nhả ga) rồi thử lại', 'The car is moving: stop it (release throttle) and try again'));
    if (status != NetAck.ok) throw Exception(failMsg);
  }

  // ---------------- Tiện ích ----------------
  void _setState(LinkState s) {
    state = s;
    notifyListeners();
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  @override
  void dispose() {
    arm.removeListener(_onArmChanged);
    _teardown();
    super.dispose();
  }
}
