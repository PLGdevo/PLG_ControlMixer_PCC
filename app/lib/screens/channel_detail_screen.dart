// Trang chi tiết một kênh (B3) — gán kênh vào phần tử trên màn Lái (B2, B4). Sửa trực tiếp trên hồ sơ nháp.
import 'package:flutter/material.dart';

import '../layout/layout_templates.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/control_layout.dart';
import '../services/output_pipeline.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/number_field.dart';

class ChannelDetailScreen extends StatefulWidget {
  const ChannelDetailScreen({super.key, required this.profile, required this.index});

  final CarProfile profile;
  final int index; // 1..10

  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

/// Tên một "chỗ gán kênh" của phần tử (cần 2 trục có hai chỗ X/Y)
String controlSlotName(ControlItem it, {bool y = false}) {
  final l = it.style.labelText;
  final name = l != null && l.trim().isNotEmpty ? '${it.kind.label} "$l"' : it.kind.label;
  if (it.kind != ItemKind.stick2D) return name;
  return '$name · trục ${y ? 'Y' : 'X'}';
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen> {
  late final _nameCtrl = TextEditingController(text: ch.name);
  double _preview = 0;

  ChannelConfig get ch => widget.profile.ch(widget.index);
  ControlLayout get layout => widget.profile.activeLayout;
  bool get isMain => ch.index == CarProfile.steeringCh || ch.index == CarProfile.throttleCh;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Phần tử đang giữ kênh này và trục (true = trục Y của cần 2 trục)
  (ControlItem, bool)? get _bound {
    final it = layout.itemForChannel(ch.index);
    if (it == null) return null;
    return (it, it.channelY == ch.index);
  }

  String _chShort(int n) {
    final c = widget.profile.ch(n);
    return c.name == 'Kênh $n' ? 'CH$n' : 'CH$n (${c.name})';
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  /// Chọn phần tử điều khiển cho kênh: phần tử có sẵn trên màn Lái, tạo mới, hoặc bỏ gán
  Future<void> _pickControl() async {
    final t = context.tokens;
    final bound = _bound;
    final slots = <(ControlItem, bool)>[
      for (final it in layout.items.where((i) => i.kind.isControl)) ...[
        (it, false),
        if (it.kind == ItemKind.stick2D) (it, true),
      ],
    ];
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.l),
            children: [
              Text('Gán ${ch.label} vào', style: AppText.title.copyWith(color: t.text)),
              const SizedBox(height: Gap.xs),
              Text('Bố cục "${layout.name}". Mỗi kênh chỉ có một phần tử trên bố cục.',
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
              ListTile(
                leading: const AppIcon(AppIcons.close),
                title: const Text('Chưa gán'),
                selected: bound == null,
                onTap: () => Navigator.pop(ctx, false),
              ),
              if (slots.isNotEmpty) ...[
                const Divider(),
                Text('PHẦN TỬ TRÊN MÀN LÁI', style: AppText.caption.copyWith(color: t.textMuted)),
                for (final (it, y) in slots)
                  Builder(builder: (_) {
                    final cur = y ? it.channelY : it.channel;
                    final mine = cur == ch.index;
                    return ListTile(
                      leading: const AppIcon(AppIcons.addControl),
                      title: Text(controlSlotName(it, y: y)),
                      subtitle: Text(
                          cur == null ? 'Chưa gán kênh' : (mine ? 'Đang gán kênh này' : 'Đang gán ${_chShort(cur)}')),
                      selected: mine,
                      onTap: () => Navigator.pop(ctx, (it, y)),
                    );
                  }),
              ],
              const Divider(),
              Text('TẠO PHẦN TỬ MỚI TRÊN MÀN LÁI', style: AppText.caption.copyWith(color: t.textMuted)),
              for (final k in ItemKind.controls)
                ListTile(
                  leading: const AppIcon(AppIcons.plus),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(ctx, k),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case false: // Chưa gán
        if (bound == null) return;
        if (isMain) {
          _snack('Kênh Ga/Lái luôn cần một phần tử trên màn Lái. Hãy chọn phần tử khác thay vì bỏ gán.');
          return;
        }
        setState(() => layout.unassignChannel(ch.index));
      case (ControlItem it, bool y):
        final cur = y ? it.channelY : it.channel;
        if (cur == ch.index) return;
        if (cur != null) {
          final ok = await _confirm(
            'Phần tử đang được dùng',
            '${controlSlotName(it, y: y)} đang gán ${_chShort(cur)}. '
                'Thay bằng ${ch.label}? ${_chShort(cur)} sẽ thành chưa gán.',
            'Thay',
          );
          if (!ok || !mounted) return;
          if (cur == CarProfile.steeringCh || cur == CarProfile.throttleCh) {
            _snack('Nhớ gán lại ${_chShort(cur)} vào một phần tử khác trước khi lưu.');
          }
        }
        setState(() => widget.profile.assignChannel(it, ch.index, y: y));
      case ItemKind k:
        final added = LayoutTemplates.addControl(layout, k, channel: ch.index);
        if (added == null) {
          _snack('Màn Lái không còn chỗ trống đủ lớn. Vào Sửa bố cục để dọn chỗ.');
          return;
        }
        setState(() => ch.enabled = true);
        _snack('Đã thêm ${k.label.toLowerCase()} lên màn Lái. Chỉnh vị trí và cấu hình riêng ở Sửa bố cục.');
    }
  }

  /// µs xe sẽ xuất ra tại vị trí `pct`, tính cả đảo chiều, trim và offset
  int _outUs(double pct) => OutputPipeline.toUs(ch, pct);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = ch.validate();
    final bound = _bound;
    return Scaffold(
      appBar: AppBar(title: Text('${ch.label} · ${ch.name}')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: 20,
            decoration: InputDecoration(labelText: 'Tên kênh', errorText: err['name']),
            onChanged: (v) => setState(() => ch.name = v),
          ),
          const SizedBox(height: Gap.s),
          InkWell(
            onTap: _pickControl,
            borderRadius: BorderRadius.circular(Radii.card),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Phần tử điều khiển'),
              child: Row(children: [
                Expanded(
                  child: Text(
                    bound == null ? 'Chưa gán — kênh không có trên màn Lái' : controlSlotName(bound.$1, y: bound.$2),
                    style: AppText.body.copyWith(color: bound == null ? t.textMuted : t.text),
                  ),
                ),
                AppIcon(AppIcons.edit, mini: true, color: t.textMuted),
              ]),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật kênh'),
            subtitle: Text(isMain
                ? 'Kênh Ga/Lái luôn cần có trên màn Lái'
                : 'Tắt kênh thì kênh được gỡ khỏi phần tử; phần tử vẫn ở trên màn Lái'),
            value: ch.enabled,
            onChanged: isMain
                ? null
                : (v) => setState(() {
                      ch.enabled = v;
                      if (!v) widget.profile.syncLayouts();
                    }),
          ),
          const Divider(),
          NumberField(label: 'Min', unit: ' µs', value: ch.minUs, min: 500, max: 2500, step: 10,
              error: err['min'], onChanged: (v) => setState(() => ch.minUs = v)),
          NumberField(label: 'Center', unit: ' µs', value: ch.centerUs, min: 500, max: 2500, step: 5,
              error: err['center'], onChanged: (v) => setState(() => ch.centerUs = v)),
          NumberField(label: 'Max', unit: ' µs', value: ch.maxUs, min: 500, max: 2500, step: 10,
              error: err['max'], onChanged: (v) => setState(() => ch.maxUs = v)),
          const Divider(),
          NumberField(label: 'Trim', unit: ' µs', value: ch.trimUs, min: -200, max: 200,
              error: err['trim'], onChanged: (v) => setState(() => ch.trimUs = v)),
          NumberField(label: 'Offset', unit: ' µs', value: ch.offsetUs, min: -300, max: 300,
              error: err['offset'], onChanged: (v) => setState(() => ch.offsetUs = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đảo chiều (Reverse)'),
            value: ch.reverse,
            onChanged: (v) => setState(() => ch.reverse = v),
          ),
          NumberField(label: 'Failsafe', unit: ' µs', value: ch.failsafeUs, min: 500, max: 2500, step: 10,
              error: err['failsafe'], onChanged: (v) => setState(() => ch.failsafeUs = v)),
          if (bound != null && bound.$1.kind.isSwitchLike)
            NumberField(
              label: 'Giá trị khi tắt',
              unit: '%',
              value: ch.offValuePct.round(),
              min: -100,
              max: 100,
              step: 5,
              error: err['off'],
              onChanged: (v) => setState(() => ch.offValuePct = v.toDouble()),
            ),
          if (isMain && (ch.minUs < 800 || ch.maxUs > 2200))
            Padding(
              padding: const EdgeInsets.only(top: Gap.s),
              child: Row(children: [
                AppIcon(AppIcons.warning, color: t.warn, mini: true),
                const SizedBox(width: Gap.s),
                Expanded(
                  child: Text('Firmware xe hiện tại chỉ nhận 800–2200 µs cho Ga/Lái.',
                      style: AppText.label.copyWith(color: t.warn)),
                ),
              ]),
            ),
          const Divider(),
          Text('Xem trước', style: AppText.title.copyWith(color: t.text)),
          const SizedBox(height: Gap.xs),
          Text('Kéo thử để thấy giá trị xe sẽ xuất ra.', style: AppText.label.copyWith(color: t.textMuted)),
          Slider(
            value: _preview,
            min: -100,
            max: 100,
            onChanged: err.isEmpty ? (v) => setState(() => _preview = v) : null,
            onChangeEnd: (_) => setState(() => _preview = 0),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Metric(label: 'Vị trí', value: '${_preview.round()}%'),
              _Metric(label: 'Xung ra', value: err.isEmpty ? '${_outUs(_preview)} µs' : '--'),
              _Metric(label: 'Tâm thực tế', value: '${ch.effectiveCenter} µs'),
            ],
          ),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(children: [
      Text(label.toUpperCase(), style: AppText.caption.copyWith(color: t.textMuted)),
      Text(value, style: AppText.metric.copyWith(color: t.text)),
    ]);
  }
}
