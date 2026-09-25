// Thêm / sửa một luật mix (Sprint 4 — U4), có xem trước. Trả về luật đã sửa qua Navigator.pop.
// Làm việc trên hồ sơ nháp: tạo Input hằng số mới được thêm thẳng vào hồ sơ nháp.
import 'package:flutter/material.dart';

import '../models/car_profile.dart';
import '../models/input_def.dart';
import '../models/mixer_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/condition_builder.dart';
import '../widgets/mix_preview.dart';
import '../widgets/number_field.dart';

class MixRuleScreen extends StatefulWidget {
  const MixRuleScreen({super.key, required this.rule, required this.profile});

  final MixRule rule; // bản sao để sửa
  final CarProfile profile; // hồ sơ nháp (Input, điều kiện, các luật khác)

  @override
  State<MixRuleScreen> createState() => _MixRuleScreenState();
}

class _MixRuleScreenState extends State<MixRuleScreen> {
  static const _newConst = '\u0000const';

  MixRule get r => widget.rule;
  CarProfile get p => widget.profile;

  String? get _error => r.validate(p.inputMap, {for (final c in p.conditions) c.id});

  void _upd(VoidCallback f) => setState(f);

  Widget _section(String title, List<Widget> children) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title.toUpperCase(), style: AppText.caption.copyWith(color: t.textMuted)),
        const SizedBox(height: Gap.xs),
        ...children,
      ]),
    );
  }

  Widget _pct(String label, double v, ValueChanged<double> set, {int min = -100, int max = 100, int step = 5}) =>
      NumberField(
        label: label,
        unit: '%',
        value: v.round(),
        min: min,
        max: max,
        step: step,
        onChanged: (x) => _upd(() => set(x.toDouble())),
      );

  Future<void> _pickSource(String? v) async {
    if (v == null) return;
    if (v != _newConst) {
      _upd(() => r.source = v);
      return;
    }
    final ctrl = TextEditingController(text: '100');
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Input hằng số'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          decoration: const InputDecoration(labelText: 'Giá trị (−100…+100%)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))?.clamp(-100.0, 100.0)),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val == null) return;
    final existing = p.inputs.where((i) => i.type == InputType.constant && i.constPct == val).firstOrNull;
    final label = val == val.roundToDouble() ? '${val.round()}' : '$val';
    final d = existing ??
        (InputDef(
          id: InputDef.uniqueId('k_${label.replaceAll('-', 'm').replaceAll('.', '_')}', p.inputs.map((i) => i.id)),
          name: 'Hằng $label%',
          type: InputType.constant,
          constPct: val,
        ));
    _upd(() {
      if (existing == null) p.inputs.add(d);
      r.source = d.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = _error;
    final src = p.input(r.source);
    return Scaffold(
      appBar: AppBar(title: const Text('Luật mix')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          TextFormField(
            initialValue: r.name,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'Tên luật (tuỳ chọn)', counterText: ''),
            onChanged: (v) => _upd(() => r.name = v.trim()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật luật'),
            value: r.enabled,
            onChanged: (v) => _upd(() => r.enabled = v),
          ),
          _section('Nguồn', [
            DropdownButtonFormField<String>(
              key: ValueKey('src-${r.source}-${p.inputs.length}'),
              initialValue: src == null ? null : r.source,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Input'),
              items: [
                for (final d in p.inputs)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text(d.type == InputType.constant ? '${d.name} (hằng số)' : '${d.name} · ${d.type.label.toLowerCase()}',
                        overflow: TextOverflow.ellipsis),
                  ),
                const DropdownMenuItem(value: _newConst, child: Text('+ Hằng số…')),
              ],
              onChanged: _pickSource,
            ),
          ]),
          _section('Điều kiện', [
            ConditionBuilder(
              value: r.condition,
              inputs: p.inputs,
              named: p.conditions,
              onChanged: (e) => _upd(() => r.condition = e),
            ),
          ]),
          _section('Tính giá trị', [
            _pct('Weight', r.weightPct, (v) => r.weightPct = v, min: -200, max: 200),
            _pct('Offset', r.offsetPct, (v) => r.offsetPct = v),
            if (src?.isUnipolar ?? false)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _upd(() {
                    r
                      ..weightPct = 200
                      ..offsetPct = -100;
                  }),
                  child: const Text('Toàn dải (0…100% → Min…Max)'),
                ),
              ),
            const SizedBox(height: Gap.s),
            SegmentedButton<CurveType>(
              showSelectedIcon: false,
              segments: [for (final c in CurveType.values) ButtonSegment(value: c, label: Text(c.label))],
              selected: {r.curve.type},
              onSelectionChanged: (s) => _upd(() => r.curve.type = s.first),
            ),
            if (r.curve.type == CurveType.expo) _pct('Expo', r.curve.expoPct, (v) => r.curve.expoPct = v),
            if (r.curve.type == CurveType.points)
              for (var i = 0; i < 5; i++)
                _pct('Tại ${MixCurve.xs[i].round()}%', r.curve.points[i], (v) => r.curve.points[i] = v),
            _pct('Min', r.minPct, (v) => r.minPct = v),
            _pct('Max', r.maxPct, (v) => r.maxPct = v),
          ]),
          _section('Đích', [
            DropdownButtonFormField<int>(
              key: ValueKey('dest-${r.destCh}'),
              initialValue: r.destCh,
              decoration: const InputDecoration(labelText: 'Kênh'),
              items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text(p.chLabel(i)))],
              onChanged: (v) => _upd(() => r.destCh = v ?? r.destCh),
            ),
            if (!p.ch(r.destCh).enabled)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Text('${p.chLabel(r.destCh)} đang tắt: luật không có tác dụng tới khi bật kênh.',
                    style: AppText.label.copyWith(color: t.warn, fontSize: 12)),
              ),
            const SizedBox(height: Gap.s),
            DropdownButtonFormField<Combine>(
              key: ValueKey('comb-${r.combine}'),
              initialValue: r.combine,
              decoration: const InputDecoration(labelText: 'Gộp với luật khác cùng kênh'),
              items: [for (final c in Combine.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (v) => _upd(() => r.combine = v ?? r.combine),
            ),
            NumberField(
              label: 'Priority (cao chạy sau)',
              value: r.priority,
              min: 0,
              max: 9,
              onChanged: (v) => _upd(() => r.priority = v),
            ),
          ]),
          _section('Khoá an toàn khi đổi đích', [
            SegmentedButton<bool?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('Tự động')),
                ButtonSegment(value: true, label: Text('Bật')),
                ButtonSegment(value: false, label: Text('Tắt')),
              ],
              selected: {r.safety.requireNeutral},
              onSelectionChanged: (s) => _upd(() => r.safety.requireNeutral = s.first),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              r.requiresNeutral(src)
                  ? 'Điều kiện đổi khi nguồn đang lệch tâm thì giữ trạng thái cũ tới khi nguồn về vùng chết.'
                  : 'Điều kiện đổi là luật tác động / ngừng ngay.',
              style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
            ),
            if (r.requiresNeutral(src)) _pct('Vùng chết', r.safety.deadzonePct, (v) => r.safety.deadzonePct = v, min: 0, max: 50, step: 1),
          ]),
          _section('Xem trước', [
            if (err == null) MixPreview(profile: p, rule: r) else Text('Sửa lỗi để xem trước', style: AppText.label.copyWith(color: t.textMuted)),
          ]),
          const SizedBox(height: Gap.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: Row(children: [
                  AppIcon(AppIcons.warning, color: t.bad, mini: true),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(err, style: AppText.label.copyWith(color: t.bad))),
                ]),
              ),
            FilledButton.icon(
              onPressed: err == null ? () => Navigator.pop(context, r) : null,
              icon: const AppIcon(AppIcons.save, mini: true),
              label: const Text('Xong'),
            ),
          ]),
        ),
      ),
    );
  }
}
