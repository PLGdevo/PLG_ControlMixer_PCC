// Chạy Condition (Sprint 4 — K1–K3, M5). Biểu thức được biên dịch một lần thành cây nút có sẵn;
// mỗi chu kỳ chỉ đọc mảng trạng thái Input, không cấp phát.
import 'dart:typed_data';

import '../models/condition.dart';

abstract class CondNode {
  bool eval(Float64List s, int epoch);
  void reset() {}
}

class _True extends CondNode {
  @override
  bool eval(Float64List s, int epoch) => true;
}

class _False extends CondNode {
  @override
  bool eval(Float64List s, int epoch) => false;
}

/// So sánh có hysteresis (K2): `>= v, hyst h` đúng khi ≥ v, sai khi < v − h, ở giữa giữ kết quả trước
class _Cmp extends CondNode {
  _Cmp(this.idx, this.op, this.v, this.h);
  final int idx;
  final CmpOp op;
  final double v, h;
  bool last = false;

  static const eqTol = 0.5; // == / != trên axis so với sai số ±0,5%

  @override
  bool eval(Float64List s, int epoch) {
    final x = s[idx];
    switch (op) {
      case CmpOp.eq:
        return (x - v).abs() <= eqTol;
      case CmpOp.ne:
        return (x - v).abs() > eqTol;
      case CmpOp.ge:
        last = last ? x >= v - h : x >= v;
      case CmpOp.gt:
        last = last ? x > v - h : x > v;
      case CmpOp.le:
        last = last ? x <= v + h : x <= v;
      case CmpOp.lt:
        last = last ? x < v + h : x < v;
    }
    return last;
  }

  @override
  void reset() => last = false;
}

/// AND / OR tính **mọi** nhánh (không dừng sớm) để trạng thái trễ của các nhánh luôn cập nhật
class _And extends CondNode {
  _And(this.kids);
  final List<CondNode> kids;
  @override
  bool eval(Float64List s, int epoch) {
    var r = true;
    for (final k in kids) {
      if (!k.eval(s, epoch)) r = false;
    }
    return r;
  }
}

class _Or extends CondNode {
  _Or(this.kids);
  final List<CondNode> kids;
  @override
  bool eval(Float64List s, int epoch) {
    var r = false;
    for (final k in kids) {
      if (k.eval(s, epoch)) r = true;
    }
    return r;
  }
}

class _Not extends CondNode {
  _Not(this.kid);
  final CondNode kid;
  @override
  bool eval(Float64List s, int epoch) => !kid.eval(s, epoch);
}

/// Condition đặt tên: một nút dùng chung, chỉ tính một lần mỗi chu kỳ (K3)
class _Shared extends CondNode {
  CondNode node = _False();
  int _epoch = -1;
  bool _value = false;
  @override
  bool eval(Float64List s, int epoch) {
    if (epoch != _epoch) {
      _epoch = epoch;
      _value = node.eval(s, epoch);
    }
    return _value;
  }

  @override
  void reset() => _epoch = -1;
}

class ConditionEngine {
  /// `inputIndex`: mã Input → vị trí trong mảng trạng thái (InputManager.index)
  ConditionEngine(this.inputIndex, List<ConditionDef> defs) {
    for (final d in defs) {
      _named[d.id] = _Shared();
    }
    for (final d in defs) {
      _named[d.id]!.node = _compile(d.expr, {d.id});
    }
  }

  final Map<String, int> inputIndex;
  final Map<String, _Shared> _named = {};
  final List<CondNode> _all = [];
  int _epoch = 0;

  int get epoch => _epoch;

  /// Gọi đầu mỗi chu kỳ, trước khi tính các Condition
  void beginCycle() => _epoch++;

  /// Biên dịch một biểu thức. Input không tồn tại hoặc tham chiếu vòng → luôn sai.
  CondNode compile(Expr e) => _compile(e, const {});

  CondNode _compile(Expr e, Set<String> visiting) {
    final CondNode n = switch (e) {
      ExprTrue() => _True(),
      ExprCmp(:final input, :final op, :final value, :final hyst) =>
        inputIndex.containsKey(input) ? _Cmp(inputIndex[input]!, op, value, hyst) : _False(),
      ExprAnd(:final args) => _And([for (final a in args) _compile(a, visiting)]),
      ExprOr(:final args) => _Or([for (final a in args) _compile(a, visiting)]),
      ExprNot(:final arg) => _Not(_compile(arg, visiting)),
      ExprRef(:final id) => visiting.contains(id) ? _False() : (_named[id] ?? _False()),
    };
    if (n is! _Shared) _all.add(n);
    return n;
  }

  /// Tính một Condition đã biên dịch trong chu kỳ hiện tại
  bool eval(CondNode n, Float64List state) => n.eval(state, _epoch);

  /// Mọi trạng thái trễ về sai (mất kết nối, DISARM, thoát màn Lái, xe failsafe)
  void reset() {
    for (final n in _all) {
      n.reset();
    }
    for (final n in _named.values) {
      n.reset();
    }
  }
}
