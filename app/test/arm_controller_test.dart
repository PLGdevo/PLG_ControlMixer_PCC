// N5: ArmController — các cạnh của máy trạng thái R1, điều kiện ARM R2, tự DISARM R3.
import 'package:flutter_test/flutter_test.dart';
import 'package:rc_controller/services/arm_controller.dart';

void main() {
  ArmController ready({bool auto = false}) => ArmController(autoArm: auto)
    ..onConnected()
    ..onFailsafeSync(true);

  test('DISCONNECTED → CONNECTED → READY → ARMED → READY → DISCONNECTED', () {
    final a = ArmController();
    expect(a.state, ArmState.disconnected);
    a.onConnected();
    expect(a.state, ArmState.connected);
    expect(a.arm(const ArmCheck()), isNotNull); // chưa đồng bộ failsafe
    a.onFailsafeSync(true);
    expect(a.state, ArmState.ready);
    expect(a.arm(const ArmCheck()), isNull);
    expect(a.state, ArmState.armed);
    a.disarm();
    expect(a.state, ArmState.ready);
    expect(a.disarmReason, isNull);
    a.onDisconnected();
    expect(a.state, ArmState.disconnected);
  });

  test('đồng bộ failsafe lỗi: ở lại CONNECTED, không cho ARM', () {
    final a = ArmController()
      ..onConnected()
      ..onFailsafeSync(false);
    expect(a.state, ArmState.connected);
    expect(a.syncFailed, isTrue);
    expect(a.arm(const ArmCheck()), contains('failsafe'));
  });

  test('không ARM được khi ga lệch nghỉ, đang sửa bố cục, hồ sơ lỗi, armCondition sai', () {
    final a = ready();
    expect(a.arm(const ArmCheck(throttleAtRest: false)), contains('ga'));
    expect(a.arm(const ArmCheck(editing: true)), contains('bố cục'));
    expect(a.arm(const ArmCheck(profileValid: false)), contains('lỗi'));
    expect(a.arm(const ArmCheck(armConditionOk: false)), contains('Điều kiện'));
    expect(a.state, ArmState.ready);
  });

  test('tự DISARM: mất kết nối, xe failsafe, armCondition sai, vào sửa bố cục', () {
    final a = ready()..arm(const ArmCheck());
    a.onCarFailsafe();
    expect((a.state, a.disarmReason), (ArmState.ready, 'Xe đang failsafe'));

    a.arm(const ArmCheck());
    a.tick(const ArmCheck(armConditionOk: false));
    expect(a.state, ArmState.ready);

    a.arm(const ArmCheck());
    a.tick(const ArmCheck(editing: true));
    expect(a.state, ArmState.ready);

    a.arm(const ArmCheck());
    a.onDisconnected();
    expect((a.state, a.disarmReason), (ArmState.disconnected, 'Mất kết nối'));
  });

  test('autoArm: tự ARM một lần sau kết nối khi đủ điều kiện; DISARM rồi thì không tự ARM lại', () {
    final a = ready(auto: true);
    a.tick(const ArmCheck(throttleAtRest: false));
    expect(a.state, ArmState.ready);
    a.tick(const ArmCheck());
    expect(a.state, ArmState.armed);
    a.disarm();
    a.tick(const ArmCheck());
    expect(a.state, ArmState.ready);
    a
      ..onDisconnected()
      ..onConnected()
      ..onFailsafeSync(true)
      ..tick(const ArmCheck());
    expect(a.state, ArmState.armed);
  });

  test('autoArm tắt thì tick không bao giờ ARM', () {
    final a = ready()..tick(const ArmCheck());
    expect(a.state, ArmState.ready);
  });
}
