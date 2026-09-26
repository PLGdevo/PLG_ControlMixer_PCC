// Trang sửa một Input (Sprint 4 — U2). Trả về bản đã sửa qua Navigator.pop, hoặc null nếu huỷ.
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../models/input_def.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/number_field.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key, required this.input, required this.takenIds, required this.idLocked, this.usedBy = 0});

  final InputDef input;

  /// Mã Input khác đang có trong hồ sơ (chống trùng)
  final Set<String> takenIds;

  /// Mã bị khoá khi đã có luật dùng Input (U2)
  final bool idLocked;
  final int usedBy;

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  late final InputDef d = widget.input.copy();
  late final _name = TextEditingController(text: d.name);
  late final _id = TextEditingController(text: d.id);

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    super.dispose();
  }

  String? get _error {
    final e = d.validate();
    if (e != null) return e;
    if (widget.takenIds.contains(d.id)) return tr('Đã có Input khác mã "${d.id}"', 'Another Input already has ID "${d.id}"');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = _error;
    final discrete = d.type == InputType.binary || d.type == InputType.ternary;
    return Scaffold(
      appBar: AppBar(title: Text(d.name.trim().isEmpty ? 'Input' : d.name)),
      body: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          TextField(
            controller: _name,
            maxLength: 24,
            decoration: InputDecoration(labelText: tr('Tên', 'Name')),
            onChanged: (v) => setState(() => d.name = v.trim()),
          ),
          TextField(
            controller: _id,
            enabled: !widget.idLocked,
            maxLength: 24,
            decoration: InputDecoration(
              labelText: tr('Mã (dùng trong điều kiện)', 'ID (used in conditions)'),
              helperText: widget.idLocked ? tr('Đang được ${widget.usedBy} luật dùng nên không đổi được mã', 'Used by ${widget.usedBy} rule(s), so the ID cannot change') : 'a–z, 0–9, "_"',
            ),
            onChanged: (v) => setState(() => d.id = v.trim()),
          ),
          const SizedBox(height: Gap.m),
          Text(tr('KIỂU', 'TYPE'), style: AppText.caption.copyWith(color: t.textMuted)),
          const SizedBox(height: Gap.xs),
          SegmentedButton<InputType>(
            showSelectedIcon: false,
            segments: [for (final ty in InputType.values) ButtonSegment(value: ty, label: Text(ty.label))],
            selected: {d.type},
            onSelectionChanged: widget.idLocked ? null : (s) => setState(() => d.type = s.first),
          ),
          if (widget.idLocked)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text(tr('Kiểu bị khoá vì Input đang được luật dùng.', 'The type is locked because rules use this Input.'),
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
            ),
          const SizedBox(height: Gap.m),
          if (d.type == InputType.axis) ...[
            Text(tr('DẢI GIÁ TRỊ', 'VALUE RANGE'), style: AppText.caption.copyWith(color: t.textMuted)),
            const SizedBox(height: Gap.xs),
            SegmentedButton<AxisRange>(
              showSelectedIcon: false,
              segments: [for (final r in AxisRange.values) ButtonSegment(value: r, label: Text(r.label))],
              selected: {d.range},
              onSelectionChanged: (s) => setState(() => d.range = s.first),
            ),
            const SizedBox(height: Gap.s),
            Text(
              d.range == AxisRange.unipolar
                  ? tr('Cần ở thấp nhất = 0%, cao nhất = 100%. Muốn phủ cả Min…Max của kênh thì dùng nút "Toàn dải" trong luật mix.', 'Stick at the bottom = 0%, top = 100%. To cover the full Min…Max of a channel use "Full range" in the mix rule.')
                  : tr('Cần ở giữa = 0%, hai đầu = −100% / +100%.', 'Stick centered = 0%, ends = −100% / +100%.'),
              style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
            ),
          ],
          if (discrete) ...[
            Text(tr('GIÁ TRỊ ĐƯA VÀO MIXER', 'VALUES SENT TO THE MIXER'), style: AppText.caption.copyWith(color: t.textMuted)),
            NumberField(
              label: d.type == InputType.binary ? tr('Khi tắt', 'When off') : tr('Nấc trái', 'Left position'),
              unit: '%',
              value: d.levels.offPct.round(),
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() => d.levels.offPct = v.toDouble()),
            ),
            if (d.type == InputType.ternary)
              NumberField(
                label: tr('Nấc giữa', 'Middle position'),
                unit: '%',
                value: d.levels.midPct.round(),
                min: -100,
                max: 100,
                step: 5,
                onChanged: (v) => setState(() => d.levels.midPct = v.toDouble()),
              ),
            NumberField(
              label: d.type == InputType.binary ? tr('Khi bật', 'When on') : tr('Nấc phải', 'Right position'),
              unit: '%',
              value: d.levels.onPct.round(),
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() => d.levels.onPct = v.toDouble()),
            ),
            Text(
              tr(
                  'Điều kiện so theo trạng thái (${d.type == InputType.binary ? '0 = tắt, 1 = bật' : '−1 / 0 / 1'}), '
                      'không phụ thuộc các giá trị % ở trên.',
                  'Conditions compare the state (${d.type == InputType.binary ? '0 = off, 1 = on' : '−1 / 0 / 1'}), '
                      'not the % values above.'),
              style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
            ),
          ],
          if (d.type == InputType.constant)
            NumberField(
              label: tr('Giá trị', 'Value'),
              unit: '%',
              value: d.constPct.round(),
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() => d.constPct = v.toDouble()),
            ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.m),
              child: Row(children: [
                AppIcon(AppIcons.warning, color: t.bad, mini: true),
                const SizedBox(width: Gap.s),
                Expanded(child: Text(err, style: AppText.label.copyWith(color: t.bad))),
              ]),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.m),
          child: FilledButton.icon(
            onPressed: err == null ? () => Navigator.pop(context, d) : null,
            icon: const AppIcon(AppIcons.save, mini: true),
            label: Text(tr('Xong', 'Done')),
          ),
        ),
      ),
    );
  }
}
