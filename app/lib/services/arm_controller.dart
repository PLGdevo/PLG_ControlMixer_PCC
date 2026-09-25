// Trạng thái kết nối và ARM (Sprint 4 — R1–R3). Chỉ khi ARMED mới gửi kết quả mixer;
// READY gửi failsafeUs của từng kênh.
import 'package:flutter/foundation.dart';

enum ArmState {
  disconnected('Chưa kết nối'),
  connected('Đang đồng bộ…'),
  ready('Sẵn sàng'),
  armed('ARMED');

  const ArmState(this.label);
  final String label;
}

/// Điều kiện ARM (R2), do màn Lái tính rồi đưa vào
class ArmCheck {
  const ArmCheck({
    this.profileValid = true,
    this.throttleAtRest = true,
    this.editing = false,
    this.armConditionOk = true,
  });
  final bool profileValid, throttleAtRest, editing, armConditionOk;
}

class ArmController extends ChangeNotifier {
  ArmController({this.autoArm = false});

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
    if (state == ArmState.armed) disarmReason = 'Mất kết nối';
    _set(ArmState.disconnected);
  }

  /// Telemetry báo xe đang failsafe
  void onCarFailsafe() => disarm('Xe đang failsafe');

  /// Lý do không ARM được, hoặc null nếu được (R2)
  String? canArm(ArmCheck c) {
    if (state == ArmState.armed) return null;
    if (state != ArmState.ready) return syncFailed ? 'Không đồng bộ được failsafe với xe' : 'Chưa sẵn sàng (${state.label})';
    if (!c.profileValid) return 'Hồ sơ còn lỗi, sửa trong Cấu hình trước';
    if (c.editing) return 'Đang sửa bố cục';
    if (!c.throttleAtRest) return 'Thả cần ga trước khi ARM';
    if (!c.armConditionOk) return 'Điều kiện ARM chưa đúng';
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

  /// Gọi mỗi chu kỳ: tự DISARM khi `armCondition` sai hoặc đang sửa bố cục;
  /// bật `autoArm` thì tự ARM lần đầu sau khi kết nối, khi đủ điều kiện (R2, R3)
  void tick(ArmCheck c) {
    if (state == ArmState.armed) {
      if (!c.armConditionOk) disarm('Điều kiện ARM chuyển sai');
      if (c.editing) disarm('Đang sửa bố cục');
    } else if (_autoPending && state == ArmState.ready && canArm(c) == null) {
      arm(c);
    }
  }
}
