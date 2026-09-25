// Trình dựng điều kiện (Sprint 4 — U4): mỗi hàng `Input · toán tử · giá trị · (trễ)` hoặc một
// Condition đặt tên; nhóm hàng bằng Tất cả (AND) / Một trong (OR); mỗi hàng có thể Phủ định.
// Biểu thức lồng sâu hơn (tạo từ file nhập) chỉ xem được, có nút xoá để dựng lại.
import 'package:flutter/material.dart';

import '../models/condition.dart';
import '../models/input_def.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

enum _Group { all, any }

class _Row {
  _Row({this.input, this.ref, this.op = CmpOp.eq, this.value = 1, this.hyst = 0, this.negate = false});

  String? input; // Input (so sánh) — hoặc
  String? ref; // Condition đặt tên
  CmpOp op;
  double value, hyst;
  bool negate;

  Expr? toExpr() {
    final Expr leaf;
    if (ref != null) {
      leaf = ExprRef(ref!);
    } else if (input != null) {
      leaf = ExprCmp(input: input!, op: op, value: value, hyst: op.ordered ? hyst : 0);
    } else {
      return null;
    }
    return negate ? ExprNot(leaf) : leaf;
  }

  static _Row? of(Expr e) {
    var neg = false;
    if (e is ExprNot) {
      neg = true;
      e = e.arg;
    }
    return switch (e) {
      ExprCmp(:final input, :final op, :final value, :final hyst) =>
        _Row(input: input, op: op, value: value, hyst: hyst, negate: neg),
      ExprRef(:final id) => _Row(ref: id, negate: neg),
      _ => null,
    };
  }
}

class ConditionBuilder extends StatefulWidget {
  const ConditionBuilder({
    super.key,
    required this.value,
    required this.inputs,
    required this.named,
    required this.onChanged,
  });

  final Expr value;
  final List<InputDef> inputs;
  final List<ConditionDef> named;
  final ValueChanged<Expr> onChanged;

  @override
  State<ConditionBuilder> createState() => _ConditionBuilderState();
}

class _ConditionBuilderState extends State<ConditionBuilder> {
  _Group group = _Group.all;
  List<_Row> rows = [];
  bool complex = false;

  @override
  void initState() {
    super.initState();
    _parse(widget.value);
  }

  void _parse(Expr e) {
    complex = false;
    rows = [];
    switch (e) {
      case ExprTrue():
        break;
      case ExprAnd(:final args) || ExprOr(:final args):
        group = e is ExprOr ? _Group.any : _Group.all;
        for (final a in args) {
          final r = _Row.of(a);
          if (r == null) {
            complex = true;
            rows = [];
            return;
          }
          rows.add(r);
        }
      default:
        final r = _Row.of(e);
        if (r == null) {
          complex = true;
        } else {
          rows.add(r);
        }
    }
  }

  Expr _build() {
    final list = [for (final r in rows) r.toExpr()].whereType<Expr>().toList();
    if (list.isEmpty) return const ExprTrue();
    if (list.length == 1) return list.single;
    return group == _Group.any ? ExprOr(list) : ExprAnd(list);
  }

  void _emit() {
    setState(() {});
    widget.onChanged(_build());
  }

  List<InputDef> get _usable => widget.inputs.where((i) => i.type != InputType.constant).toList();

  void _add() {
    final first = _usable.firstOrNull;
    rows.add(_Row(
      input: first?.id,
      ref: first == null ? widget.named.firstOrNull?.id : null,
      value: first == null || first.isAxis ? 50 : 1,
      op: first == null || first.isAxis ? CmpOp.ge : CmpOp.eq,
    ));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (complex) {
      final names = {for (final i in widget.inputs) i.id: i.name, for (final c in widget.named) c.id: c.name};
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.value.describe((id) => names[id] ?? id), style: AppText.body.copyWith(color: t.text)),
        const SizedBox(height: Gap.xs),
        Text('Điều kiện lồng nhiều tầng: chỉ xem được ở đây.',
            style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              complex = false;
              rows = [];
              _emit();
            },
            child: const Text('Xoá và dựng lại'),
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isEmpty)
        Text('Luôn đúng — luật luôn chạy.', style: AppText.label.copyWith(color: t.textMuted))
      else if (rows.length > 1)
        SegmentedButton<_Group>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Group.all, label: Text('Tất cả (AND)')),
            ButtonSegment(value: _Group.any, label: Text('Một trong (OR)')),
          ],
          selected: {group},
          onSelectionChanged: (s) {
            group = s.first;
            _emit();
          },
        ),
      for (var i = 0; i < rows.length; i++) _rowCard(rows[i], i),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: rows.length < Expr.maxCmp && (_usable.isNotEmpty || widget.named.isNotEmpty) ? _add : null,
          icon: const AppIcon(AppIcons.plus, mini: true),
          label: const Text('Thêm điều kiện'),
        ),
      ),
    ]);
  }

  Widget _rowCard(_Row r, int i) {
    final t = context.tokens;
    final input = r.input == null ? null : widget.inputs.where((d) => d.id == r.input).firstOrNull;
    const refPrefix = 'ref:';
    return Card(
      margin: const EdgeInsets.only(top: Gap.s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.xs, Gap.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('src-$i-${r.input}-${r.ref}'),
                initialValue: r.ref != null ? '$refPrefix${r.ref}' : r.input,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Khi'),
                items: [
                  for (final d in _usable) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
                  for (final c in widget.named)
                    DropdownMenuItem(value: '$refPrefix${c.id}', child: Text('Điều kiện "${c.name}"')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v.startsWith(refPrefix)) {
                    r
                      ..ref = v.substring(refPrefix.length)
                      ..input = null;
                  } else {
                    final d = widget.inputs.firstWhere((x) => x.id == v);
                    final wasAxis = input?.isAxis ?? false;
                    r
                      ..ref = null
                      ..input = v;
                    if (d.isAxis != wasAxis) {
                      r
                        ..op = d.isAxis ? CmpOp.ge : CmpOp.eq
                        ..value = d.isAxis ? 50 : 1
                        ..hyst = 0;
                    }
                  }
                  _emit();
                },
              ),
            ),
            IconButton(
              tooltip: 'Xoá',
              onPressed: () {
                rows.removeAt(i);
                _emit();
              },
              icon: AppIcon(AppIcons.delete, color: t.textMuted, mini: true),
            ),
          ]),
          if (r.ref == null && input != null) ...[
            const SizedBox(height: Gap.xs),
            Row(children: [
              DropdownButton<CmpOp>(
                value: r.op,
                items: [for (final o in CmpOp.values) DropdownMenuItem(value: o, child: Text(o.symbol))],
                onChanged: (o) {
                  if (o == null) return;
                  r.op = o;
                  if (!o.ordered) r.hyst = 0;
                  _emit();
                },
              ),
              const SizedBox(width: Gap.s),
              Expanded(child: _valueEditor(r, input, i)),
            ]),
            if (r.op.ordered && input.isAxis)
              _numField(ValueKey('hyst-$i-${r.input}'), 'Trễ (hysteresis)', r.hyst, 0, 200, (v) {
                r.hyst = v;
                _emit();
              }),
          ],
          Row(children: [
            Checkbox(
              value: r.negate,
              onChanged: (v) {
                r.negate = v ?? false;
                _emit();
              },
            ),
            Text('Phủ định (KHÔNG)', style: AppText.label.copyWith(color: t.text)),
          ]),
        ]),
      ),
    );
  }

  Widget _valueEditor(_Row r, InputDef d, int i) {
    switch (d.type) {
      case InputType.binary:
        return SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 0, label: Text('Tắt (0)')), ButtonSegment(value: 1, label: Text('Bật (1)'))],
          selected: {r.value == 0 ? 0.0 : 1.0},
          onSelectionChanged: (s) {
            r.value = s.first;
            _emit();
          },
        );
      case InputType.ternary:
        return SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: -1, label: Text('Trái')),
            ButtonSegment(value: 0, label: Text('Giữa')),
            ButtonSegment(value: 1, label: Text('Phải')),
          ],
          selected: {r.value.clamp(-1, 1).roundToDouble()},
          onSelectionChanged: (s) {
            r.value = s.first;
            _emit();
          },
        );
      default:
        return _numField(ValueKey('val-$i-${r.input}'), d.isUnipolar ? 'Giá trị (0…100%)' : 'Giá trị (%)', r.value,
            d.isUnipolar ? 0 : -100, 100, (v) {
          r.value = v;
          _emit();
        });
    }
  }

  Widget _numField(Key key, String label, double v, double min, double max, ValueChanged<double> onChanged) =>
      TextFormField(
        key: key,
        initialValue: v == v.roundToDouble() ? v.round().toString() : v.toString(),
        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (s) {
          final x = double.tryParse(s.replaceAll(',', '.'));
          if (x != null) onChanged(x.clamp(min, max).toDouble());
        },
      );
}
