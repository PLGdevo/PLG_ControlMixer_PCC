// Thêm / sửa một luật mix (G5), có xem trước (G6). Trả về luật đã sửa qua Navigator.pop.
import 'package:flutter/material.dart';

import '../models/channel_config.dart';
import '../models/mix_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/mix_preview.dart';
import '../widgets/number_field.dart';

class MixRuleScreen extends StatefulWidget {
  const MixRuleScreen({super.key, required this.rule, required this.others, required this.channels});

  final MixRule rule; // bản sao để sửa
  final List<MixRule> others; // các luật còn lại (theo thứ tự), để dò vòng lặp
  final List<ChannelConfig> channels;

  @override
  State<MixRuleScreen> createState() => _MixRuleScreenState();
}

class _MixRuleScreenState extends State<MixRuleScreen> {
  MixRule get r => widget.rule;

  String? get _error {
    final e = r.validate();
    if (e != null) return e;
    final all = [...widget.others, r].where((x) => x.enabled).toList();
    final cycle = MixRule.findCycle(all);
    if (cycle != null) return 'Tạo vòng lặp: ${cycle.map((c) => 'CH$c').join(' → ')}';
    return null;
  }

  void _upd(VoidCallback f) => setState(f);

  String _chName(int n) {
    final c = widget.channels[n - 1];
    return c.name == 'Kênh $n' ? 'CH$n' : 'CH$n · ${c.name}';
  }

  Widget _chPicker(String label, int? value, ValueChanged<int?> onChanged, {bool allowNone = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: DropdownButtonFormField<int?>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          if (allowNone) const DropdownMenuItem<int?>(value: null, child: Text('Không (luôn chạy)')),
          for (var i = 1; i <= 10; i++) DropdownMenuItem<int?>(value: i, child: Text(_chName(i))),
        ],
        onChanged: (v) => _upd(() => onChanged(v)),
      ),
    );
  }

  Widget _pct(String label, double v, ValueChanged<double> set, {int min = -100, int max = 100}) => NumberField(
        label: label,
        unit: '%',
        value: v.round(),
        min: min,
        max: max,
        step: 5,
        onChanged: (x) => _upd(() => set(x.toDouble())),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = _error;
    final isSelect = r.type == MixType.select;
    return Scaffold(
      appBar: AppBar(title: const Text('Luật mix')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          SegmentedButton<MixType>(
            showSelectedIcon: false,
            segments: [for (final m in MixType.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {r.type},
            onSelectionChanged: (s) => _upd(() => r.type = s.first),
          ),
          const SizedBox(height: Gap.m),
          if (!isSelect) ...[
            _chPicker('Kênh nguồn', r.sourceCh, (v) => r.sourceCh = v ?? r.sourceCh),
            _chPicker('Kênh đích', r.targetCh, (v) => r.targetCh = v ?? r.targetCh),
            _chPicker('Điều kiện bằng nút (gate)', r.gateCh, (v) => r.gateCh = v, allowNone: true),
          ] else ...[
            _chPicker('Kênh nguồn (thường là cần gạt)', r.sourceCh, (v) => r.sourceCh = v ?? r.sourceCh),
            _chPicker('Nút chọn', r.selectCh, (v) => r.selectCh = v ?? r.selectCh),
            _chPicker('Đích khi nút BẬT', r.targetOnCh, (v) => r.targetOnCh = v ?? r.targetOnCh),
            _chPicker('Đích khi nút TẮT', r.targetOffCh, (v) => r.targetOffCh = v ?? r.targetOffCh),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: DropdownButtonFormField<MixMode>(
              key: ValueKey(r.mode),
              initialValue: r.mode,
              decoration: const InputDecoration(labelText: 'Khi kênh đích đang có nguồn điều khiển'),
              items: [for (final m in MixMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: (m) => _upd(() => r.mode = m ?? r.mode),
            ),
          ),
          const Divider(),
          ...switch (r.type) {
            MixType.threshold => [
                _pct('Bật khi nguồn ≥', r.onAtPct, (v) => r.onAtPct = v),
                _pct('Tắt khi nguồn <', r.offBelowPct, (v) => r.offBelowPct = v),
                _pct('Giá trị khi BẬT', r.onValuePct, (v) => r.onValuePct = v),
                _pct('Giá trị khi TẮT', r.offValuePct, (v) => r.offValuePct = v),
                Text('Nguồn nằm giữa hai ngưỡng thì giữ trạng thái trước. Trạng thái ban đầu là TẮT.',
                    style: AppText.label.copyWith(color: t.textMuted)),
              ],
            MixType.linear => [
                _pct('Hệ số (gain)', r.gainPct, (v) => r.gainPct = v, min: -200, max: 200),
                _pct('Độ lệch (offset)', r.offsetPct, (v) => r.offsetPct = v),
                Text('Đích = nguồn × hệ số + độ lệch, kẹp trong −100…+100%.',
                    style: AppText.label.copyWith(color: t.textMuted)),
              ],
            MixType.curve => [
                for (var i = 0; i < 5; i++)
                  _pct('Tại nguồn ${MixRule.curveXs[i].round()}%', r.curvePts[i], (v) => r.curvePts[i] = v),
              ],
            MixType.select => [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Khoá an toàn'),
                  subtitle: const Text('Chỉ đổi kênh đích khi nguồn đã về giữa'),
                  value: r.requireNeutralToSwitch,
                  onChanged: (v) => _upd(() => r.requireNeutralToSwitch = v),
                ),
                if (r.requireNeutralToSwitch)
                  NumberField(
                    label: 'Vùng coi là "giữa"',
                    unit: '%',
                    value: r.neutralDeadzonePct.round(),
                    min: 0,
                    max: 50,
                    onChanged: (v) => _upd(() => r.neutralDeadzonePct = v.toDouble()),
                  ),
              ],
          },
          const Divider(),
          Text('Xem trước', style: AppText.title.copyWith(color: t.text)),
          const SizedBox(height: Gap.s),
          MixPreview(rule: r, channels: widget.channels),
          const SizedBox(height: Gap.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
          padding: const EdgeInsets.all(Gap.m),
          child: Row(
            children: [
              if (err != null) ...[
                AppIcon(AppIcons.warning, color: t.bad, mini: true),
                const SizedBox(width: Gap.s),
                Expanded(child: Text(err, style: AppText.label.copyWith(color: t.bad))),
              ] else
                const Spacer(),
              const SizedBox(width: Gap.s),
              FilledButton(
                onPressed: err == null ? () => Navigator.pop(context, r) : null,
                child: const Text('Xong'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
