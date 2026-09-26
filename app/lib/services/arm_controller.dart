// Trạng thái kết nối và ARM (Sprint 4 — R1–R3). Chỉ khi ARMED mới gửi kết quả mixer;
// READY gửi failsafeUs của từng kênh. Hồ sơ tắt cơ chế ARM (`enabled` = false) thì tự ARM
// mỗi khi đủ điều kiện, không cần người dùng nhấn giữ nút ARM.
import 'package:flutter/foundation.dart';

import '../l10n/lang.dart';

enum ArmState {
  disconnected('Chưa kết nối', 'Not connected'),
  connected('Đang đồng bộ…', 'Syncing…'),
  ready('Sẵn sàng', 'Ready'),
  armed('ARMED', 'ARMED');

  const ArmState(this._vi, this._en);
  final String _vi, _en;
  String get label => tr(_vi, _en);
}

/// Điều kiện ARM (R2), do màn Lái tính rồi đưa vào
class ArmCheck {
  const ArmCheck({
    this.profileValid = true,
    this.throttleAtRest = true,
    this.editing = false,
    this.armConditionOk = true,
    this.paused = false,
    this.linkOk = true,
  });
  final bool profileValid, throttleAtRest, editing, armConditionOk;

  /// Màn Lái đang bị che (mở Cấu hình) hoặc app xuống nền
  final bool paused;

  /// Đang nhận telemetry của xe (không ở trạng thái mất tín hiệu)
  final bool linkOk;
}

class ArmController extends ChangeNotifier {
  ArmController({this.autoArm = false});

  /// false = không dùng cơ chế ARM: tự ARM mỗi khi đủ điều kiện, kể cả sau khi bị DISARM
  bool enabled = true;
  bool autoArm;
  ArmState state = ArmState.disconnected;

  /// Lý do DISARM gần nhất (hiện cho người dùng), null nếu người dùng tự DISARM
  String? disarmReason;

  /// Đồng bộ failsafe thất bại sau 3 lần: ở lại CONNECTED, không cho ARM (E6)
  bool syncFailed = false;

  bool get armed => state == ArmState.armed;

  /// autoArm chỉ tự ARM một lần sau mỗi lần kết nối; DISARM rồi thì phải bấm ARM
  bool _autoPending = false;

  void _set(ArmState s) {
    if (s == state) return;
    state = s;
    notifyListeners();
  }

  void onConnected() {
    syncFailed = false;
    disarmReason = null;
    _set(ArmState.connected);
  }

  void onFailsafeSync(bool ok) {
    if (state == ArmState.disconnected) return;
    syncFailed = !ok;
    if (ok) {
      if (state == ArmState.connected) {
        _autoPending = autoArm;
        _set(ArmState.ready);
      }
    } else {
      notifyListeners();
    }
  }

  void onDisconnected() {
    _autoPending = false;
    if (state == ArmState.armed) disarmReason = tr('Mất kết nối', 'Connection lost');
    _set(ArmState.disconnected);
  }

  /// Telemetry báo xe đang failsafe
  void onCarFailsafe() => disarm(tr('Xe đang failsafe', 'Car is in failsafe'));

  /// Lý do không ARM được, hoặc null nếu được (R2)
  String? canArm(ArmCheck c) {
    if (state == ArmState.armed) return null;
    if (state != ArmState.ready) return syncFailed ? tr('Không đồng bộ được failsafe với xe', 'Could not sync failsafe with the car') : tr('Chưa sẵn sàng (${state.label})', 'Not ready (${state.label})');
    if (!c.profileValid) return tr('Hồ sơ còn lỗi, sửa trong Cấu hình trước', 'Profile has errors, fix them in Settings first');
    if (c.editing) return tr('Đang sửa bố cục', 'Editing layout');
    if (c.paused) return tr('Màn Lái đang ẩn', 'Drive screen hidden');
    if (!c.linkOk) return tr('Mất tín hiệu', 'Signal lost');
    if (!c.throttleAtRest) {
      return enabled
          ? tr('Thả cần ga trước khi ARM', 'Release the throttle before arming')
          : tr('Thả cần ga để bắt đầu lái', 'Release the throttle to start driving');
    }
    if (!c.armConditionOk) return tr('Điều kiện ARM chưa đúng', 'ARM condition not met');
    return null;
  }

  /// ARM; trả về lý do nếu không được
  String? arm(ArmCheck c) {
    final e = canArm(c);
    if (e == null && state == ArmState.ready) {
      disarmReason = null;
      _autoPending = false;
      _set(ArmState.armed);
    }
    return e;
  }

  /// DISARM về READY (R3). `reason` = null khi người dùng tự bấm.
  void disarm([String? reason]) {
    _autoPending = false;
    if (state != ArmState.armed) return;
    disarmReason = reason;
    _set(ArmState.ready);
  }

  /// Gọi mỗi chu kỳ: tự DISARM khi `armCondition` sai, đang sửa bố cục hoặc màn Lái bị che;
  /// bật `autoArm` thì tự ARM lần đầu sau khi kết nối, khi đủ điều kiện (R2, R3).
  /// Tắt cơ chế ARM thì tự ARM lại mỗi khi đủ điều kiện.
  void tick(ArmCheck c) {
    if (state == ArmState.armed) {
      if (!c.armConditionOk) disarm(tr('Điều kiện ARM chuyển sai', 'ARM condition became false'));
      if (c.editing) disarm(tr('Đang sửa bố cục', 'Editing layout'));
      if (c.paused) disarm(tr('Màn Lái đang ẩn', 'Drive screen hidden'));
    } else if ((_autoPending || !enabled) && state == ArmState.ready && canArm(c) == null) {
      arm(c);
    }
  }
}
