import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../protocol/net_protocol.dart';
import '../protocol/protocol.dart';
import '../services/arm_controller.dart';
import '../services/condition_engine.dart';
import '../services/output_pipeline.dart';
import '../services/ping_service.dart';
import '../transport/transport.dart';

enum LinkState { disconnected, connecting, connected, lost }

/// Quản lý kết nối, vòng gửi lệnh điều khiển, telemetry, cấu hình và ARM.
/// Mỗi chu kỳ: Input → Condition → Mixer (OutputPipeline); chỉ khi ARMED mới gửi kết quả mixer (R1).
class CarController extends ChangeNotifier {
  CarController() {
    arm.addListener(_onArmChanged);
  }

  static const linkTimeout = Duration(milliseconds: 1000); // không có telemetry -> "mất tín hiệu"
  static const _ackKey = 0x2000;
  static const _netKey = 0x4100; // NET_DATA theo section

  CarTransport? _transport;
  StreamSubscription? _inSub, _lostSub;
  Timer? _controlTimer, _watchdog;
  bool _sending = false;
  int _seq = 0;
  int? _syncedHash; // failsafeHash đã được xe xác nhận trong lần kết nối này (E6)
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

  /// Khoá nhận diện kết nối hiện tại (vd "wifi:192.168.4.1:4210"), để ping nhanh dùng lại kết nối
  String? connectedKey;

  /// Hồ sơ đang được nối (kể cả bước dò xe trong mạng trước khi mở kết nối); null = không nối xe nào
  String? connectingKey;

  void setConnecting(String? key) {
    connectingKey = key;
    notifyListeners();
  }

  Telemetry? telemetry;
  DateTime? lastTelemetryAt;
  CarConfig? config;

  /// Xe có firmware n kênh (trả lời INFO_GET); null = firmware cũ, chỉ lái CH1/CH2
  CarInfo? carInfo;
  bool get multiChannel => carInfo != null;

  /// Số kênh xe xuất ra được
  int get carChannels => carInfo?.channels ?? 2;

  /// µs từng kênh vừa gửi xuống xe (n kênh), rỗng khi chưa ARM / chưa vào màn Lái
  List<int> lastSentUs = const [];

  /// Kết quả mixer gần nhất (10 kênh %), null nếu chưa nạp hồ sơ
  List<double>? get channelPct => pipeline?.lastPct;

  CarTransport? get transport => _transport;
  String? get transportName => _transport?.name;
  bool get isConnected => state == LinkState.connected || state == LinkState.lost;

  // ---------------- Kết nối ----------------
  /// `expectId`: mã xe (MAC) của hồ sơ; xe trả lời mã khác thì từ chối (IP đã thuộc về xe khác)
  Future<void> connect(CarTransport t, {String? key, String? expectId}) async {
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
      carInfo = await _probeInfo();
      final got = carInfo?.id;
      if (expectId != null && got != null && got != expectId.toUpperCase()) {
        throw Exception(tr(
            'sai xe: địa chỉ này là xe $got, không phải xe $expectId của hồ sơ. '
                'Đã thay mạch xe thì bấm "Quên mã xe" trong Cấu hình',
            'wrong car: this address is car $got, not car $expectId of this profile. '
                'If the car board was replaced, tap "Forget car ID" in Car settings'));
      }

      connectedKey = key;
      arm.onConnected();
      lastTelemetryAt = DateTime.now();
      _controlTimer = Timer.periodic(t.controlPeriod, (_) => _sendControl()); // WiFi 100 Hz, BLE 50 Hz
      _watchdog = Timer.periodic(const Duration(milliseconds: 200), (_) => _checkLink());
      _startLinkStats(t);
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
      // Gửi lệnh trung tính (n kênh: 0 kênh = xe xuất failsafe) vài lần trước khi ngắt
      for (var i = 0; i < 3; i++) {
        try {
          await t.send(multiChannel ? _controlUsFrame(const []) : _controlFrame(0, 0));
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
    _stopLinkStats();
    try {
      await _transport?.close();
    } catch (_) {}
    _transport = null;
    connectedKey = null;
    telemetry = null;
    testing = false;
    testPct.clear();
    _liveApply?.cancel();
    carInfo = null;
    _syncedHash = null;
    lastSentUs = const [];
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
    arm.enabled = p.arm.enabled;
    arm.autoArm = p.arm.autoArm;
    // Tắt cơ chế ARM thì bỏ qua điều kiện ARM riêng
    final a = p.arm.enabled ? p.arm.armCondition : null;
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

  /// Điều kiện ARM đầy đủ: phần màn Lái đưa vào ([armCheck]) + điều kiện ARM riêng + tín hiệu xe.
  /// Tín hiệu ổn = đang nhận telemetry và xe không báo failsafe (xe nhận được lệnh của app).
  /// null khi chưa vào màn Lái.
  ArmCheck? currentArmCheck() {
    final s = armCheck?.call();
    if (s == null) return null;
    return ArmCheck(
      profileValid: s.profileValid,
      throttleAtRest: s.throttleAtRest,
      editing: s.editing,
      paused: s.paused,
      armConditionOk: armConditionOk,
      linkOk: state == LinkState.connected && !(telemetry?.failsafe ?? false),
    );
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

  Uint8List _controlFrame(double thr, double steer) {
    _seq = (_seq + 1) & 0xFF;
    return encodeControl(
      throttle: (thr * 1000).round(),
      steering: (steer * 1000).round(),
      gear: 1, // app không có hộp số; xe giữ giới hạn ga 100% (toCarConfig)
      seq: _seq,
    );
  }

  Uint8List _controlUsFrame(List<int> us) {
    _seq = (_seq + 1) & 0xFFFF;
    return encodeControlUs(_seq, us);
  }

  void _sendControl() {
    final t = _transport;
    if (t == null || _sending) return; // bỏ gói nếu gói trước chưa gửi xong (tránh dồn trễ)
    final pl = pipeline;
    List<double>? pct;
    if (pl != null) {
      pct = pl.mixed();
      final check = currentArmCheck();
      if (check != null) arm.tick(check);
    }
    final Uint8List frame;
    if (multiChannel) {
      // n kênh: app áp servo (O2), xe xuất thẳng µs. READY gửi failsafeUs (R1);
      // chưa vào màn Lái thì gửi 0 kênh để giữ kết nối, xe xuất failsafe của nó.
      final List<int> all;
      if (pl == null) {
        all = const [];
      } else if (arm.armed) {
        all = pl.toUsList(pct!);
      } else {
        all = testing ? pl.toUsList(pl.testPct(testPct)) : pl.failsafeUs();
      }
      lastSentUs = all.length > carChannels ? all.sublist(0, carChannels) : all;
      frame = _controlUsFrame(lastSentUs);
    } else {
      // Firmware cũ (2 kênh): xe tự áp servo, chỉ nhận CH1 (chân lái) và CH2 (chân ga).
      // Chưa ARM → gửi trung tính.
      var thr = 0.0, steer = 0.0;
      if (pl != null && (arm.armed || testing)) {
        final v = arm.armed ? pct! : pl.testPct(testPct);
        steer = v[0] / 100;
        thr = v[1] / 100;
      }
      frame = _controlFrame(thr, steer);
    }
    _sending = true;
    t.send(frame).catchError((_) {}).whenComplete(() => _sending = false);
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
      _telAt.add(_linkClock.elapsedMilliseconds);
      if (t.failsafe && arm.armed) arm.onCarFailsafe();
      if (state == LinkState.lost) state = LinkState.connected;
      notifyListeners();
    }
  }

  // ---------------- Chất lượng liên kết (như tay RC) ----------------
  static const _lqWindowMs = 2000;
  static const _telemetryPeriodMs = 100; // firmware gửi telemetry 10 Hz

  /// Ngưỡng báo "Tín hiệu yếu" trên màn Lái
  static const weakLq = 70, slowPingMs = 200;

  /// Ping ngầm 1 lần/giây suốt lúc kết nối (xe trả PONG ngay, không ảnh hưởng failsafe)
  PingService? _pinger;
  final _linkClock = Stopwatch();
  final _telAt = Queue<int>(); // thời điểm nhận telemetry (ms theo _linkClock)
  bool _background = false;

  void _startLinkStats(CarTransport t) {
    _telAt.clear();
    _linkClock
      ..reset()
      ..start();
    _pinger = PingService(t)..addListener(notifyListeners);
    if (!_background) _pinger!.start(intervalMs: 1000);
  }

  void _stopLinkStats() {
    _pinger?.dispose();
    _pinger = null;
    _linkClock.stop();
    _telAt.clear();
  }

  /// App xuống nền thì ngừng ping ngầm, lên lại thì đo tiếp từ đầu
  set background(bool v) {
    if (_background == v) return;
    _background = v;
    final p = _pinger;
    if (p == null) return;
    if (v) {
      p.stop();
    } else {
      p.window.clear();
      p.start(intervalMs: 1000);
    }
  }

  /// Ping trung bình 20 gói gần nhất (ms); null = chưa nối hoặc chưa có PONG nào
  double? get pingMs => _pinger?.stats.avgMs;

  /// LQ (%): tỉ lệ gói telemetry (10 Hz) về tới trong 2 giây gần nhất. null = chưa nối / mới nối
  int? get linkQuality {
    if (_pinger == null) return null;
    final now = _linkClock.elapsedMilliseconds;
    while (_telAt.isNotEmpty && now - _telAt.first > _lqWindowMs) {
      _telAt.removeFirst();
    }
    final span = min(now, _lqWindowMs);
    if (span < 500) return null;
    // Cho lệch 1 gói: nhịp loop của xe làm chu kỳ telemetry dài hơn 100 ms một chút
    final expected = span / _telemetryPeriodMs - 1;
    return (_telAt.length * 100 / expected).round().clamp(0, 100);
  }

  /// Tín hiệu yếu nhưng chưa mất hẳn: LQ thấp hoặc ping cao
  bool get weakLink =>
      state == LinkState.connected && ((linkQuality ?? 100) < weakLq || (pingMs ?? 0) > slowPingMs);

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
  /// Firmware n kênh trả INFO; firmware cũ không trả lời → null (lái 2 kênh như cũ).
  /// Thử đủ lâu: xe vừa được nối lại có thể trả lời chậm, mà lỡ bị coi là firmware cũ thì cả phiên
  /// chỉ còn CH1/CH2 và trim / các kênh khác không có tác dụng.
  Future<CarInfo?> _probeInfo() async {
    try {
      final f = await _request(encodeFrame(PacketType.infoGet), PacketType.info,
          retries: 3, timeout: const Duration(milliseconds: 500));
      return CarInfo.parse(f.payload);
    } on TimeoutException {
      return null;
    }
  }

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
    notifyListeners();
  }

  /// Ghi cấu hình của hồ sơ xuống xe. `persist` = lưu vào flash của xe.
  Future<void> writeProfile(CarProfile p, {required bool persist}) async {
    await applyConfig(p.toCarConfig());
    if (persist) await saveConfig();
  }

  /// App là nguồn đúng (0.5): đưa phần xe cần giữ khi mất sóng xuống xe. Trả về true nếu đã ghi.
  /// - n kênh: gửi FS_WRITE (failsafe từng kênh + thời gian), xe lưu NVS và trả hash để so (E6).
  /// - firmware cũ: xe tự áp servo/failsafe nên ghi cả cấu hình CH1/CH2 (CONFIG_SET + SAVE).
  /// Kết quả được báo cho ArmController: đồng bộ được thì READY, lỗi thì không cho ARM (E6, R1).
  Future<bool> syncProfile(CarProfile p, {bool force = false}) async {
    if (!multiChannel) return _syncLegacy(p, force: force);
    final hash = p.failsafeHash();
    if (!force && _syncedHash == hash) {
      arm.onFailsafeSync(true);
      return false;
    }
    try {
      final f = await _request(encodeFsWrite(p.failsafeBytes()), PacketType.fsAck,
          timeout: const Duration(seconds: 1));
      final a = FsAck.parse(f.payload);
      if (a == null || !a.ok) throw Exception(tr('Xe từ chối failsafe', 'The car rejected the failsafe'));
      if (a.hash != hash) {
        throw Exception(tr('Xe nhận failsafe bị sai (hash không khớp)', 'The car received a corrupted failsafe (hash mismatch)'));
      }
    } catch (_) {
      arm.onFailsafeSync(false);
      rethrow;
    }
    _syncedHash = hash;
    arm.onFailsafeSync(true);
    return true;
  }

  Future<bool> _syncLegacy(CarProfile p, {required bool force}) async {
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

  // ---------------- Cấu hình trực tiếp ----------------
  /// Màn Cấu hình mở trên xe đang nối: bản nháp được nạp vào vòng gửi, sửa gì có tác dụng ngay.
  /// `true` khi hồ sơ trong vòng gửi do màn Cấu hình nạp (không có màn Lái bên dưới).
  bool _liveOwnsPipeline = false;
  bool _live = false;
  Timer? _liveApply;

  /// Thử trên xe: chưa ARM vẫn xuất kênh theo cấu hình đang sửa (cần gạt ở vị trí nghỉ, kênh đang
  /// thử theo [testPct]) thay cho failsafe. Tự tắt khi ngắt kết nối hoặc rời màn Cấu hình.
  bool testing = false;

  /// Kênh đang được kéo thử ở màn Cấu hình: số kênh → %
  final Map<int, double> testPct = {};

  bool get live => _live;

  /// Lý do chưa bật được Thử trên xe, null nếu được
  String? get testBlock {
    if (!_live || !isConnected) return tr('Chưa kết nối xe', 'Car not connected');
    if (state == LinkState.lost) return tr('Mất tín hiệu', 'Signal lost');
    if (arm.armed) return tr('Đang ARM ở màn Lái', 'Armed on the drive screen');
    if (arm.state != ArmState.ready) {
      return arm.syncFailed
          ? tr('Không đồng bộ được failsafe với xe', 'Could not sync failsafe with the car')
          : tr('Chưa sẵn sàng (${arm.state.label})', 'Not ready (${arm.state.label})');
    }
    return null;
  }

  /// Bắt đầu / cập nhật cấu hình trực tiếp với bản nháp hợp lệ `p` (truyền bản sao)
  void updateLive(CarProfile p) {
    if (!_live) {
      _live = true;
      _liveOwnsPipeline = pipeline == null;
    }
    loadProfile(p);
    // Firmware cũ tự áp Center/trim/đảo chiều của CH1/CH2 → gửi cấu hình xuống xe (chưa lưu flash)
    if (!multiChannel && isConnected) {
      _liveApply?.cancel();
      _liveApply = Timer(const Duration(milliseconds: 300), () => applyConfig(p.toCarConfig()).catchError((_) {}));
    }
    notifyListeners();
  }

  void setTesting(bool on) {
    testing = on && testBlock == null;
    if (!testing) testPct.clear();
    notifyListeners();
  }

  /// Kéo thử kênh `ch` (null = thả tay, kênh về vị trí nghỉ)
  void setTest(int ch, double? pct) {
    if (pct == null) {
      testPct.remove(ch);
    } else {
      testPct[ch] = pct.clamp(-100.0, 100.0).toDouble();
    }
  }

  /// Rời màn Cấu hình: tắt thử, trả vòng gửi về hồ sơ đã lưu `saved`
  void endLive(CarProfile? saved) {
    if (!_live || _disposed) return;
    _live = false;
    testing = false;
    testPct.clear();
    _liveApply?.cancel();
    if (_liveOwnsPipeline) {
      unloadProfile();
    } else if (saved != null) {
      loadProfile(saved);
    }
    _liveOwnsPipeline = false;
    if (!multiChannel && isConnected && saved != null) {
      applyConfig(saved.toCarConfig()).catchError((_) {});
    }
    notifyListeners();
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

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    arm.removeListener(_onArmChanged);
    _teardown();
    super.dispose();
  }
}
