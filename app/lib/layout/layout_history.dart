import 'dart:convert';

import '../models/control_layout.dart';

/// Hoàn tác / Làm lại khi sửa bố cục (H2), tối đa 30 bước
class LayoutHistory {
  LayoutHistory({this.limit = 30});

  final int limit;
  final List<String> _undo = [], _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  static String _snap(ControlLayout l) => jsonEncode(l.toJson());
  static ControlLayout _load(String s) => ControlLayout.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// Gọi TRƯỚC mỗi thay đổi, với trạng thái hiện tại
  void push(ControlLayout before) {
    _undo.add(_snap(before));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  ControlLayout? undo(ControlLayout current) {
    if (_undo.isEmpty) return null;
    _redo.add(_snap(current));
    return _load(_undo.removeLast());
  }

  ControlLayout? redo(ControlLayout current) {
    if (_redo.isEmpty) return null;
    _undo.add(_snap(current));
    return _load(_redo.removeLast());
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
