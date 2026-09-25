// Trang sửa một Input (Sprint 4 — U2). Trả về bản đã sửa qua Navigator.pop, hoặc null nếu huỷ.
import 'package:flutter/material.dart';

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
    if (widget.takenIds.contains(d.id)) return 'Đã có Input khác mã "${d.id}"';
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
            decoration: const InputDecoration(labelText: 'Tên'),
            onChanged: (v) => setState(() => d.name = v.trim()),
          ),
          TextField(
            controller: _id,
            enabled: !widget.idLocked,
            maxLength: 24,
            decoration: InputDecoration(
              labelText: 'Mã (dùng trong điều kiện)',
              helperText: widget.idLocked ? 'Đang được ${widget.usedBy} luật dùng nên không đổi được mã' : 'a–z, 0–9, "_"',
            ),
            onChanged: (v) => setState(() => d.id = v.trim()),
          ),
          const SizedBox(height: Gap.m),
          Text('KIỂU', style: AppText.caption.copyWith(color: t.textMuted)),
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
              child: Text('Kiểu bị khoá vì Input đang được luật dùng.',
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
            ),
          const SizedBox(height: Gap.m),
          if (d.type == InputType.axis) ...[
            Text('DẢI GIÁ TRỊ', style: AppText.caption.copyWith(color: t.textMuted)),
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
                  ? 'Cần ở thấp nhất = 0%, cao nhất = 100%. Muốn phủ cả Min…Max của kênh thì dùng nút "Toàn dải" trong luật mix.'
                  : 'Cần ở giữa = 0%, hai đầu = −100% / +100%.',
              style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
            ),
          ],
          if (discrete) ...[
            Text('GIÁ TRỊ ĐƯA VÀO MIXER', style: AppText.caption.copyWith(color: t.textMuted)),
            NumberField(
              label: d.type == InputType.binary ? 'Khi tắt' : 'Nấc trái',
              unit: '%',
              value: d.levels.offPct.round(),
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() => d.levels.offPct = v.toDouble()),
            ),
            if (d.type == InputType.ternary)
              NumberField(
                label: 'Nấc giữa',
                unit: '%',
                value: d.levels.midPct.round(),
                min: -100,
                max: 100,
                step: 5,
                onChanged: (v) => setState(() => d.levels.midPct = v.toDouble()),
              ),
            NumberField(
              label: d.type == InputType.binary ? 'Khi bật' : 'Nấc phải',
              unit: '%',
              value: d.levels.onPct.round(),
              min: -100,
              max: 100,
              step: 5,
              onChanged: (v) => setState(() => d.levels.onPct = v.toDouble()),
            ),
            Text(
              'Điều kiện so theo trạng thái (${d.type == InputType.binary ? '0 = tắt, 1 = bật' : '−1 / 0 / 1'}), '
              'không phụ thuộc các giá trị % ở trên.',
              style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
            ),
          ],
          if (d.type == InputType.constant)
            NumberField(
              label: 'Giá trị',
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
            label: const Text('Xong'),
          ),
        ),
      ),
    );
  }
}
