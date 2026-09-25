import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/car_profile.dart';
import '../protocol/protocol.dart';
import '../transport/transport.dart';

enum LinkState { disconnected, connecting, connected, lost }

/// Quản lý kết nối, vòng gửi lệnh điều khiển, telemetry và cấu hình.
class CarController extends ChangeNotifier {
  static const controlPeriod = Duration(milliseconds: 25); // 40 Hz
  static const linkTimeout = Duration(milliseconds: 1000); // không có telemetry -> "mất tín hiệu"
  static const _ackKey = 0x2000;

  CarTransport? _transport;
  StreamSubscription? _inSub, _lostSub;
  Timer? _controlTimer, _watchdog;
  bool _sending = false;
  int _seq = 0;
  final Map<int, Completer<Frame>> _waiters = {};

  LinkState state = LinkState.disconnected;
  String? error;

  /// Giá trị gốc 10 kênh, −1..1 (CH1 ở vị trí 0). Firmware hiện tại (giao thức v1)
  /// chỉ nhận CH1 = lái, CH2 = ga; CH3–CH10 sẽ gửi khi có giao thức v2 (Sprint 4).
  final List<double> values = List<double>.filled(10, 0);

  /// Vị trí nút bật/tắt (0/1) và công tắc 3 nấc (0/1/2) theo kênh — giữ nguyên khi thoát màn Lái
  final Map<int, int> switchPos = {};

  /// Khi true: gửi Center cho cần ga/lái (đang sửa bố cục — H5)
  bool holdNeutral = false;

  /// Số lượng số theo hồ sơ đang lái (null = theo cấu hình đọc từ xe)
  int? gearCountOverride;

  /// Khoá nhận diện kết nối hiện tại (vd "wifi:192.168.4.1:4210"), để ping nhanh dùng lại kết nối
  String? connectedKey;

  int gear = 1;
  Telemetry? telemetry;
  DateTime? lastTelemetryAt;
  CarConfig? config;

  double get throttle => values[CarProfile.throttleCh - 1];
  set throttle(double v) => values[CarProfile.throttleCh - 1] = v;
  double get steering => values[CarProfile.steeringCh - 1];
  set steering(double v) => values[CarProfile.steeringCh - 1] = v;

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
      values.fillRange(0, values.length, 0);
      connectedKey = key;
      lastTelemetryAt = DateTime.now();
      _controlTimer = Timer.periodic(controlPeriod, (_) => _sendControl());
      _watchdog = Timer.periodic(const Duration(milliseconds: 200), (_) => _checkLink());
      WakelockPlus.enable();
      _setState(LinkState.connected);
    } catch (e) {
      error = 'Kết nối thất bại: ${_msg(e)}';
      await _teardown();
      _setState(LinkState.disconnected);
    }
  }

  Future<void> disconnect() async {
    throttle = 0;
    steering = 0;
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
    error = 'Mất kết nối với xe';
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
      if (!w.isCompleted) w.completeError(StateError('Đã ngắt kết nối'));
    }
    _waiters.clear();
    try {
      await _transport?.close();
    } catch (_) {}
    _transport = null;
    connectedKey = null;
    telemetry = null;
    _sending = false;
    WakelockPlus.disable();
  }

  // ---------------- Điều khiển ----------------
  void setThrottle(double v) {
    throttle = v.clamp(-1.0, 1.0).toDouble();
    notifyListeners();
  }

  void setSteering(double v) {
    steering = v.clamp(-1.0, 1.0).toDouble();
    notifyListeners();
  }

  /// Báo giao diện vẽ lại sau khi sửa trực tiếp `values`
  void refresh() => notifyListeners();

  /// Đặt giá trị kênh `ch` (1..10), −1..1
  void setChannel(int ch, double v) {
    if (ch < 1 || ch > values.length) return;
    values[ch - 1] = v.clamp(-1.0, 1.0).toDouble();
    notifyListeners();
  }

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
    _sending = true;
    final neutral = holdNeutral;
    t.send(_controlFrame(neutral ? 0 : throttle, neutral ? 0 : steering)).catchError((_) {}).whenComplete(() => _sending = false);
  }

  void _checkLink() {
    final last = lastTelemetryAt;
    if (state == LinkState.connected &&
        last != null &&
        DateTime.now().difference(last) > linkTimeout) {
      _setState(LinkState.lost);
    }
  }

  // ---------------- Nhận dữ liệu ----------------
  void _onData(Uint8List data) {
    final f = decodeFrame(data);
    if (f == null) return;

    final key = (f.type == PacketType.ack && f.payload.isNotEmpty)
        ? (_ackKey | f.payload[0])
        : f.type;
    final w = _waiters.remove(key);
    if (w != null && !w.isCompleted) w.complete(f);

    if (f.type == PacketType.telemetry) {
      final t = Telemetry.parse(f.payload);
      if (t == null) return;
      telemetry = t;
      lastTelemetryAt = DateTime.now();
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
      if (t == null) throw StateError('Chưa kết nối');
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
    throw TimeoutException('Xe không phản hồi');
  }

  // ---------------- Cấu hình ----------------
  Future<CarConfig> _fetchConfig() async {
    final f = await _request(encodeFrame(PacketType.configGet), PacketType.configData);
    final c = CarConfig.parse(f.payload);
    if (c == null) throw Exception('Dữ liệu cấu hình không hợp lệ');
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
    if (f.payload.length < 2 || f.payload[1] != 1) throw Exception('Xe từ chối cấu hình');
    config = c;
    if (gear > c.gearCount) gear = c.gearCount;
    notifyListeners();
  }

  Future<void> saveConfig() async {
    final f = await _request(encodeFrame(PacketType.configSave), _ackKey | PacketType.configSave);
    if (f.payload.length < 2 || f.payload[1] != 1) throw Exception('Lưu thất bại');
  }

  Future<void> resetConfig() async {
    final f = await _request(encodeFrame(PacketType.configReset), PacketType.configData);
    final c = CarConfig.parse(f.payload);
    if (c == null) throw Exception('Dữ liệu cấu hình không hợp lệ');
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
  Future<bool> syncProfile(CarProfile p, {bool force = false}) async {
    final want = p.toCarConfig();
    final have = config;
    if (!force && have != null && listEquals(have.toBytes(), want.toBytes())) return false;
    await writeProfile(p, persist: true);
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

  // ---------------- Tiện ích ----------------
  void _setState(LinkState s) {
    state = s;
    notifyListeners();
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
