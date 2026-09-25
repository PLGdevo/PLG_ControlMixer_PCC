// Giữ trạng thái và giá trị % của mọi Input (Sprint 4 — I2, P2). Widget trên màn Lái ghi vào đây;
// ConditionEngine đọc `state`, MixerEngine đọc `value`. Mảng cấp sẵn, không cấp phát trong vòng gửi.
import 'dart:typed_data';

import '../models/input_def.dart';

class InputManager {
  InputManager(List<InputDef> defs) {
    load(defs);
  }

  List<InputDef> _defs = const [];
  Map<String, int> _index = const {};
  Float64List state = Float64List(0);
  Float64List value = Float64List(0);

  List<InputDef> get defs => _defs;
  Map<String, int> get index => _index;

  /// Nạp lại danh sách Input (sau khi sửa hồ sơ). Input giữ nguyên mã thì giữ trạng thái.
  void load(List<InputDef> defs) {
    final old = {for (final e in _index.entries) e.key: state[e.value]};
    _defs = [for (final d in defs) d.copy()];
    _index = {for (var i = 0; i < _defs.length; i++) _defs[i].id: i};
    state = Float64List(_defs.length);
    value = Float64List(_defs.length);
    for (var i = 0; i < _defs.length; i++) {
      final d = _defs[i];
      _put(i, d.type == InputType.constant ? d.constPct : (old[d.id] ?? d.restState));
    }
  }

  int indexOf(String id) => _index[id] ?? -1;

  InputDef? def(String id) {
    final i = indexOf(id);
    return i < 0 ? null : _defs[i];
  }

  void _put(int i, double s) {
    state[i] = s;
    value[i] = _defs[i].valueOf(s);
  }

  /// Đặt trạng thái trực tiếp (I2)
  void setState(String id, double s) {
    final i = indexOf(id);
    if (i >= 0 && _defs[i].type != InputType.constant) _put(i, s);
  }

  /// Cần gạt / núm: vị trí −100…+100 (sau tự về, vùng chết)
  void setPosition(String id, double pos) {
    final i = indexOf(id);
    if (i >= 0 && _defs[i].isAxis) _put(i, _defs[i].stateFromPosition(pos));
  }

  /// Nút bật/tắt: `pos` 0/1. Công tắc 3 nấc: `pos` 0/1/2 → trạng thái −1/0/1.
  void setSwitch(String id, int pos) {
    final i = indexOf(id);
    if (i < 0) return;
    switch (_defs[i].type) {
      case InputType.binary:
        _put(i, pos >= 1 ? 1 : 0);
      case InputType.ternary:
        _put(i, (pos.clamp(0, 2) - 1).toDouble());
      default:
        break;
    }
  }

  double stateOf(String id) {
    final i = indexOf(id);
    return i < 0 ? 0 : state[i];
  }

  double valueOf(String id) {
    final i = indexOf(id);
    return i < 0 ? 0 : value[i];
  }

  /// Mọi Input về trạng thái nghỉ (I3)
  void resetToRest() {
    for (var i = 0; i < _defs.length; i++) {
      _put(i, _defs[i].restState);
    }
  }
}
