// Trang chi tiết một kênh đầu ra (Sprint 4 — O1). Kênh nhận giá trị từ luật mix; trang này chỉnh
// Min/Center/Max, trim, offset, reverse, failsafe và liệt kê các luật đang ghi vào kênh. Sửa trên hồ sơ nháp.
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../services/output_pipeline.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/number_field.dart';

class ChannelDetailScreen extends StatefulWidget {
  const ChannelDetailScreen({super.key, required this.profile, required this.index, required this.onOpenMix});

  final CarProfile profile;
  final int index; // 1..10

  /// Về tab Mix để thêm / sửa luật của kênh này
  final VoidCallback onOpenMix;

  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen> {
  late final _nameCtrl = TextEditingController(text: ch.displayName);
  double _preview = 0;

  ChannelConfig get ch => widget.profile.ch(widget.index);
  /// CH1/CH2: firmware v1 luôn xuất (chân lái / ga của xe)
  bool get isMain => ch.alwaysOn;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// µs xe sẽ xuất ra tại vị trí `pct`, tính cả đảo chiều, trim và offset
  int _outUs(double pct) => OutputPipeline.toUs(ch, pct);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = ch.validate();
    return Scaffold(
      appBar: AppBar(title: Text('${ch.label} · ${ch.displayName}')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.l),
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: 20,
            decoration: InputDecoration(labelText: tr('Tên kênh', 'Channel name'), errorText: err['name']),
            onChanged: (v) => setState(() => ch.name = v),
          ),
          const SizedBox(height: Gap.s),
          Builder(builder: (context) {
            final rules = widget.profile.mixer.where((r) => r.destCh == ch.index).toList();
            final inputs = widget.profile.inputMap;
            return InputDecorator(
              decoration: InputDecoration(labelText: tr('Luật mix ghi vào kênh này', 'Mix rules writing to this channel')),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (rules.isEmpty)
                  Text(tr('Chưa có luật nào — kênh ra Center (hoặc failsafe nếu tắt).', 'No rules yet — the channel outputs Center (or failsafe when off).'),
                      style: AppText.body.copyWith(color: t.textMuted)),
                for (final r in rules)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${r.describe(inputs)}${r.enabled ? '' : tr(' (đang tắt)', ' (off)')}',
                        style: AppText.body.copyWith(color: r.enabled ? t.text : t.disabled)),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: widget.onOpenMix, child: Text(tr('Sửa ở tab Mix', 'Edit in the Mix tab'))),
                ),
              ]),
            );
          }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bật kênh', 'Channel on')),
            subtitle: Text(isMain ? tr('CH1/CH2 luôn bật: firmware xe hiện tại luôn xuất hai kênh này', 'CH1/CH2 are always on: the current car firmware always outputs these two channels') : tr('Kênh tắt luôn ra failsafe, luật mix ghi vào bị bỏ qua', 'A disabled channel always outputs failsafe; mix rules into it are ignored')),
            value: ch.enabled,
            onChanged: isMain ? null : (v) => setState(() => ch.enabled = v),
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
            title: Text(tr('Đảo chiều (Reverse)', 'Reverse')),
            value: ch.reverse,
            onChanged: (v) => setState(() => ch.reverse = v),
          ),
          NumberField(label: 'Failsafe', unit: ' µs', value: ch.failsafeUs, min: 500, max: 2500, step: 10,
              error: err['failsafe'], onChanged: (v) => setState(() => ch.failsafeUs = v)),
          if (isMain && (ch.minUs < 800 || ch.maxUs > 2200))
            Padding(
              padding: const EdgeInsets.only(top: Gap.s),
              child: Row(children: [
                AppIcon(AppIcons.warning, color: t.warn, mini: true),
                const SizedBox(width: Gap.s),
                Expanded(
                  child: Text(tr('Firmware xe hiện tại chỉ nhận 800–2200 µs cho CH1/CH2.', 'The current car firmware only accepts 800–2200 µs on CH1/CH2.'),
                      style: AppText.label.copyWith(color: t.warn)),
                ),
              ]),
            ),
          const Divider(),
          Text(tr('Xem trước', 'Preview'), style: AppText.title.copyWith(color: t.text)),
          const SizedBox(height: Gap.xs),
          Text(tr('Kéo thử để thấy giá trị xe sẽ xuất ra.', 'Drag to see the value the car will output.'), style: AppText.label.copyWith(color: t.textMuted)),
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
              _Metric(label: tr('Vị trí', 'Position'), value: '${_preview.round()}%'),
              _Metric(label: tr('Xung ra', 'Output pulse'), value: err.isEmpty ? '${_outUs(_preview)} µs' : '--'),
              _Metric(label: tr('Tâm thực tế', 'Actual center'), value: '${ch.effectiveCenter} µs'),
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
