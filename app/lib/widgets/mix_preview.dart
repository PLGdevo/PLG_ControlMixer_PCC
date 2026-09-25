// Xem trước luật mix (Sprint 4 — U4): giả lập mọi Input dùng trong luật, chạy cùng MixerEngine với
// toàn bộ luật của hồ sơ (luật đang sửa thay bản cũ) và hiện mọi kênh bị ảnh hưởng.
import 'package:flutter/material.dart';

import '../models/car_profile.dart';
import '../models/input_def.dart';
import '../models/mixer_rule.dart';
import '../services/input_manager.dart';
import '../services/mixer_engine.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class MixPreview extends StatefulWidget {
  const MixPreview({super.key, required this.profile, required this.rule});

  final CarProfile profile;
  final MixRule rule;

  @override
  State<MixPreview> createState() => _MixPreviewState();
}

class _MixPreviewState extends State<MixPreview> {
  late InputManager im;
  late MixerEngine engine;
  final Map<String, double> pos = {};
  final Map<String, int> sw = {};
  List<double> out = List.filled(10, 0);

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(MixPreview old) {
    super.didUpdateWidget(old);
    _rebuild();
  }

  List<MixRule> get _rules {
    final r = widget.rule;
    final list = [for (final m in widget.profile.mixer) m.id == r.id ? r : m];
    if (!list.any((m) => m.id == r.id)) list.add(r);
    return list;
  }

  /// Input cần giả lập: nguồn và mọi Input trong điều kiện của luật này
  List<InputDef> get _controls {
    final ids = {widget.rule.source, ...widget.rule.condition.inputs};
    for (final c in widget.profile.conditions) {
      if (widget.rule.condition.refs.contains(c.id)) ids.addAll(c.expr.inputs);
    }
    return [
      for (final d in widget.profile.inputs)
        if (ids.contains(d.id) && d.type != InputType.constant) d,
    ];
  }

  /// Kênh hiển thị: đích của luật này và của các luật dùng chung nguồn / Input điều kiện
  List<int> get _channels {
    final ids = _controls.map((d) => d.id).toSet();
    final chs = <int>{widget.rule.destCh};
    for (final m in _rules.where((m) => m.enabled)) {
      if (ids.contains(m.source) || m.condition.inputs.any(ids.contains)) chs.add(m.destCh);
    }
    return chs.toList()..sort();
  }

  void _rebuild() {
    im = InputManager(widget.profile.inputs);
    engine = MixerEngine(im, conditions: widget.profile.conditions, rules: _rules);
    pos.forEach(im.setPosition);
    sw.forEach(im.setSwitch);
    _run();
  }

  void _run() => out = List<double>.from(engine.run());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = widget.rule;
    final pending = engine.isPending(r.id), active = engine.isActive(r.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in _controls) _control(d),
      const SizedBox(height: Gap.s),
      Row(children: [
        Icon(Icons.circle, size: 10, color: pending ? t.warn : (active ? t.accent : t.disabled)),
        const SizedBox(width: Gap.xs),
        Text(
          !r.enabled ? 'Luật đang tắt' : (pending ? 'Chờ về giữa' : (active ? 'Luật đang tác động' : 'Điều kiện chưa đúng')),
          style: AppText.label.copyWith(color: t.text),
        ),
      ]),
      const SizedBox(height: Gap.s),
      for (final ch in _channels) _bar(ch, out[ch - 1], highlight: ch == r.destCh),
    ]);
  }

  Widget _control(InputDef d) {
    final t = context.tokens;
    return Row(children: [
      SizedBox(width: 96, child: Text(d.name, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: t.text))),
      Expanded(
        child: switch (d.type) {
          InputType.axis => Slider(
              value: pos[d.id] ?? 0,
              min: -100,
              max: 100,
              label: '${im.valueOf(d.id).round()}%',
              divisions: 200,
              onChanged: (v) => setState(() {
                pos[d.id] = v;
                im.setPosition(d.id, v);
                _run();
              }),
            ),
          InputType.binary => Align(
              alignment: Alignment.centerLeft,
              child: Switch(
                value: (sw[d.id] ?? 0) == 1,
                onChanged: (v) => setState(() {
                  sw[d.id] = v ? 1 : 0;
                  im.setSwitch(d.id, sw[d.id]!);
                  _run();
                }),
              ),
            ),
          _ => SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('◀')),
                ButtonSegment(value: 1, label: Text('●')),
                ButtonSegment(value: 2, label: Text('▶')),
              ],
              selected: {sw[d.id] ?? 1},
              onSelectionChanged: (s) => setState(() {
                sw[d.id] = s.first;
                im.setSwitch(d.id, s.first);
                _run();
              }),
            ),
        },
      ),
      SizedBox(
        width: 44,
        child: Text('${im.valueOf(d.id).round()}%',
            textAlign: TextAlign.right, style: AppText.metric.copyWith(fontSize: 13, color: t.textMuted)),
      ),
    ]);
  }

  Widget _bar(int ch, double v, {bool highlight = false}) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(widget.profile.chLabel(ch),
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: highlight ? t.accent : t.text, fontWeight: highlight ? FontWeight.w700 : null)),
        ),
        Expanded(
          child: SizedBox(
            height: 14,
            child: LayoutBuilder(builder: (context, box) {
              final half = box.maxWidth / 2;
              return Stack(children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(Radii.pill)),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: v >= 0 ? half : half + half * v / 100,
                  width: half * v.abs() / 100,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: highlight ? t.accentFill : t.textMuted,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
                Positioned(left: half - 0.5, top: 0, bottom: 0, width: 1, child: ColoredBox(color: t.line)),
              ]);
            }),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text('${v.round()}%', textAlign: TextAlign.right, style: AppText.metric.copyWith(fontSize: 13, color: t.text)),
        ),
      ]),
    );
  }
}
