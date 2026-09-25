// Trang chi tiết một kênh đầu ra (Sprint 4 — O1). Kênh nhận giá trị từ luật mix; trang này chỉnh
// Min/Center/Max, trim, offset, reverse, failsafe và liệt kê các luật đang ghi vào kênh. Sửa trên hồ sơ nháp.
import 'package:flutter/material.dart';

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
  late final _nameCtrl = TextEditingController(text: ch.name);
  double _preview = 0;

  ChannelConfig get ch => widget.profile.ch(widget.index);
  bool get isMain => ch.index == CarProfile.steeringCh || ch.index == CarProfile.throttleCh;

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
          Builder(builder: (context) {
            final rules = widget.profile.mixer.where((r) => r.destCh == ch.index).toList();
            final inputs = widget.profile.inputMap;
            return InputDecorator(
              decoration: const InputDecoration(labelText: 'Luật mix ghi vào kênh này'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (rules.isEmpty)
                  Text('Chưa có luật nào — kênh ra Center (hoặc failsafe nếu tắt).',
                      style: AppText.body.copyWith(color: t.textMuted)),
                for (final r in rules)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${r.describe(inputs)}${r.enabled ? '' : ' (đang tắt)'}',
                        style: AppText.body.copyWith(color: r.enabled ? t.text : t.disabled)),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: widget.onOpenMix, child: const Text('Sửa ở tab Mix')),
                ),
              ]),
            );
          }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật kênh'),
            subtitle: Text(isMain ? 'Kênh Ga/Lái luôn bật' : 'Kênh tắt luôn ra failsafe, luật mix ghi vào bị bỏ qua'),
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
            title: const Text('Đảo chiều (Reverse)'),
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
