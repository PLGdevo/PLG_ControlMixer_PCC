// Condition (Sprint 4 — K1–K3): cây biểu thức quyết định luật mix có được chạy hay không.
// So sánh trên **trạng thái** của Input (I2), có hysteresis cho so sánh lớn/nhỏ.
import 'input_def.dart';

enum CmpOp {
  eq('=='),
  ne('!='),
  gt('>'),
  lt('<'),
  ge('>='),
  le('<=');

  const CmpOp(this.symbol);
  final String symbol;

  bool get ordered => this == gt || this == lt || this == ge || this == le;

  static CmpOp? parse(String? s) => values.where((o) => o.symbol == s).firstOrNull;
}

sealed class Expr {
  const Expr();

  static const maxDepth = 4, maxCmp = 8;

  Map<String, dynamic> toJson();

  static Expr fromJson(Object? j) {
    if (j is! Map) return const ExprTrue();
    return switch (j['op']) {
      'cmp' => ExprCmp(
          input: j['input'] as String? ?? '',
          op: CmpOp.parse(j['cmp'] as String?) ?? CmpOp.eq,
          value: (j['value'] as num?)?.toDouble() ?? 0,
          hyst: (j['hyst'] as num?)?.toDouble() ?? 0,
        ),
      'and' => ExprAnd([for (final a in (j['args'] as List? ?? const [])) fromJson(a)]),
      'or' => ExprOr([for (final a in (j['args'] as List? ?? const [])) fromJson(a)]),
      'not' => ExprNot(fromJson(j['arg'])),
      'ref' => ExprRef(j['id'] as String? ?? ''),
      _ => const ExprTrue(),
    };
  }

  /// Số tầng lồng của AND / OR / NOT (phép so sánh, `ref`, `true` không tính tầng)
  int get depth => switch (this) {
        ExprAnd(:final args) || ExprOr(:final args) =>
          1 + args.fold<int>(0, (m, a) => a.depth > m ? a.depth : m),
        ExprNot(:final arg) => 1 + arg.depth,
        _ => 0,
      };

  /// Số phép so sánh
  int get cmpCount => switch (this) {
        ExprCmp() => 1,
        ExprAnd(:final args) || ExprOr(:final args) => args.fold<int>(0, (s, a) => s + a.cmpCount),
        ExprNot(:final arg) => arg.cmpCount,
        _ => 0,
      };

  /// Mọi Input được tham chiếu trực tiếp (không đi qua `ref`)
  Iterable<String> get inputs sync* {
    switch (this) {
      case ExprCmp(:final input):
        yield input;
      case ExprAnd(:final args) || ExprOr(:final args):
        for (final a in args) {
          yield* a.inputs;
        }
      case ExprNot(:final arg):
        yield* arg.inputs;
      default:
        break;
    }
  }

  /// Mọi Condition đặt tên được tham chiếu trực tiếp
  Iterable<String> get refs sync* {
    switch (this) {
      case ExprRef(:final id):
        yield id;
      case ExprAnd(:final args) || ExprOr(:final args):
        for (final a in args) {
          yield* a.refs;
        }
      case ExprNot(:final arg):
        yield* arg.refs;
      default:
        break;
    }
  }

  bool get isTrue => this is ExprTrue;

  /// Mô tả ngắn cho thẻ luật (M6). `nameOf` đổi mã Input/Condition thành tên hiển thị.
  String describe(String Function(String id) nameOf) => switch (this) {
        ExprTrue() => 'luôn đúng',
        ExprCmp(:final input, :final op, :final value, :final hyst) =>
          '${nameOf(input)} ${op.symbol} ${_num(value)}${hyst > 0 ? ' (trễ ${_num(hyst)})' : ''}',
        ExprAnd(:final args) => args.map((a) => _paren(a, nameOf)).join(' VÀ '),
        ExprOr(:final args) => args.map((a) => _paren(a, nameOf)).join(' HOẶC '),
        ExprNot(:final arg) => 'KHÔNG ${_paren(arg, nameOf)}',
        ExprRef(:final id) => nameOf(id),
      };

  static String _paren(Expr e, String Function(String) nameOf) =>
      e is ExprAnd || e is ExprOr ? '(${e.describe(nameOf)})' : e.describe(nameOf);

  static String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// Kiểm tra (K1, V). `inputs`: Input của hồ sơ; `conditionIds`: Condition đặt tên đang có.
  String? validate(Map<String, InputDef> inputs, Set<String> conditionIds) {
    if (depth > maxDepth) return 'Điều kiện lồng quá $maxDepth tầng';
    if (cmpCount > maxCmp) return 'Điều kiện có quá $maxCmp phép so sánh';
    return _check(inputs, conditionIds);
  }

  String? _check(Map<String, InputDef> inputs, Set<String> conditionIds) {
    switch (this) {
      case ExprCmp(:final input, :final op, :final hyst):
        if (!inputs.containsKey(input)) return 'Điều kiện dùng Input "$input" không tồn tại';
        if (hyst < 0 || hyst > 200) return 'Độ trễ trong khoảng 0–200';
        if (hyst > 0 && !op.ordered) return 'Độ trễ chỉ dùng với so sánh lớn/nhỏ';
      case ExprAnd(:final args) || ExprOr(:final args):
        if (args.isEmpty) return 'Nhóm điều kiện trống';
        for (final a in args) {
          final e = a._check(inputs, conditionIds);
          if (e != null) return e;
        }
      case ExprNot(:final arg):
        return arg._check(inputs, conditionIds);
      case ExprRef(:final id):
        if (!conditionIds.contains(id)) return 'Điều kiện "$id" không tồn tại';
      case ExprTrue():
        break;
    }
    return null;
  }

  /// Đổi mã Input `from` thành `to` (khi đổi mã Input)
  Expr renameInput(String from, String to) => switch (this) {
        ExprCmp(:final input, :final op, :final value, :final hyst) =>
          ExprCmp(input: input == from ? to : input, op: op, value: value, hyst: hyst),
        ExprAnd(:final args) => ExprAnd([for (final a in args) a.renameInput(from, to)]),
        ExprOr(:final args) => ExprOr([for (final a in args) a.renameInput(from, to)]),
        ExprNot(:final arg) => ExprNot(arg.renameInput(from, to)),
        _ => this,
      };
}

class ExprTrue extends Expr {
  const ExprTrue();
  @override
  Map<String, dynamic> toJson() => {'op': 'true'};
}

class ExprCmp extends Expr {
  const ExprCmp({required this.input, required this.op, required this.value, this.hyst = 0});
  final String input;
  final CmpOp op;
  final double value;
  final double hyst;

  @override
  Map<String, dynamic> toJson() => {
        'op': 'cmp',
        'input': input,
        'cmp': op.symbol,
        'value': value,
        if (hyst > 0) 'hyst': hyst,
      };
}

class ExprAnd extends Expr {
  const ExprAnd(this.args);
  final List<Expr> args;
  @override
  Map<String, dynamic> toJson() => {'op': 'and', 'args': [for (final a in args) a.toJson()]};
}

class ExprOr extends Expr {
  const ExprOr(this.args);
  final List<Expr> args;
  @override
  Map<String, dynamic> toJson() => {'op': 'or', 'args': [for (final a in args) a.toJson()]};
}

class ExprNot extends Expr {
  const ExprNot(this.arg);
  final Expr arg;
  @override
  Map<String, dynamic> toJson() => {'op': 'not', 'arg': arg.toJson()};
}

class ExprRef extends Expr {
  const ExprRef(this.id);
  final String id;
  @override
  Map<String, dynamic> toJson() => {'op': 'ref', 'id': id};
}

/// Condition đặt tên (K3): dùng lại ở nhiều luật, mọi luật tham chiếu dùng chung trạng thái trễ
class ConditionDef {
  static const maxConditions = 32;

  String id;
  String name;
  Expr expr;

  ConditionDef({required this.id, required this.name, this.expr = const ExprTrue()});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'expr': expr.toJson()};

  factory ConditionDef.fromJson(Map<String, dynamic> j) => ConditionDef(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        expr: Expr.fromJson(j['expr']),
      );

  ConditionDef copy() => ConditionDef.fromJson(toJson());

  /// Tìm vòng tham chiếu giữa các Condition đặt tên; trả về đường đi (đầu = cuối) hoặc null
  static List<String>? findRefCycle(List<ConditionDef> defs) {
    final byId = {for (final d in defs) d.id: d};
    final state = <String, int>{}; // 1 đang thăm, 2 xong
    final stack = <String>[];
    List<String>? dfs(String u) {
      state[u] = 1;
      stack.add(u);
      for (final v in byId[u]?.expr.refs ?? const <String>[]) {
        if (state[v] == 1) return [...stack.sublist(stack.indexOf(v)), v];
        if (state[v] == null && byId.containsKey(v)) {
          final c = dfs(v);
          if (c != null) return c;
        }
      }
      stack.removeLast();
      state[u] = 2;
      return null;
    }

    for (final d in defs) {
      if (state[d.id] == null) {
        final c = dfs(d.id);
        if (c != null) return c;
      }
    }
    return null;
  }
}
