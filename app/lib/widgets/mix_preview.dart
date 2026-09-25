// Xem trước mix (G6): kéo thử kênh nguồn, xem giá trị kênh đích.
import 'package:flutter/material.dart';

import '../models/channel_config.dart';
import '../models/mix_rule.dart';
import '../services/mix_engine.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'status_badge.dart';

class MixPreview extends StatefulWidget {
  const MixPreview({super.key, required this.rule, required this.channels});

  final MixRule rule;
  final List<ChannelConfig> channels;

  @override
  State<MixPreview> createState() => _MixPreviewState();
}

class _MixPreviewState extends State<MixPreview> {
  late final MixEngine _engine = MixEngine([widget.rule]);
  double _src = 0;
  bool _gate = true, _select = false;
  List<double> _out = List.filled(10, 0);
  MixType? _lastType;

  MixRule get r => widget.rule;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(MixPreview old) {
    super.didUpdateWidget(old);
    _run();
  }

  void _run() {
    if (_lastType != r.type) {
      _engine.reset();
      _lastType = r.type;
    }
    _engine.rules = [r];
    if (r.validate() != null) return;
    final input = List<double>.filled(10, 0);
    input[r.sourceCh - 1] = _src;
    if (r.type == MixType.select) {
      input[r.selectCh - 1] = _select ? 100 : -100;
    } else if (r.gateCh != null) {
      input[r.gateCh! - 1] = _gate ? 100 : -100;
    }
    _out = _engine.run(input);
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _run();
      });

  String _name(int ch) {
    final c = widget.channels[ch - 1];
    return c.name == 'Kênh $ch' ? 'CH$ch' : 'CH$ch ${c.name}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = r.validate();
    if (err != null) {
      return Text('Chưa xem trước được: $err', style: AppText.label.copyWith(color: t.bad));
    }
    final isThreshold = r.type == MixType.threshold;
    final isSelect = r.type == MixType.select;
    final sel = isSelect ? _engine.selectState(r.id) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Nguồn ${_name(r.sourceCh)}: ${_src.round()}%',
                  style: AppText.label.copyWith(color: t.text)),
            ),
            if (isThreshold)
              _engine.isOn(r.id) ? Pill(color: t.ok, label: 'BẬT') : Pill(color: t.idle, label: 'TẮT'),
            if (isSelect && sel != null && sel.pending) Pill(color: t.warn, label: 'Chờ về giữa'),
          ],
        ),
        const SizedBox(height: Gap.s),
        if (isThreshold) _Band(from: r.offBelowPct, to: r.onAtPct, value: _src),
        Slider(
          value: _src,
          min: -100,
          max: 100,
          divisions: 200,
          label: '${_src.round()}%',
          onChanged: (v) => _set(() => _src = v),
        ),
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            OutlinedButton(onPressed: () => _set(() => _src = 0), child: const Text('Về 0%')),
            if (isSelect)
              FilterChip(
                label: Text('Nút chọn ${_name(r.selectCh)}: ${_select ? 'BẬT' : 'TẮT'}'),
                selected: _select,
                onSelected: (v) => _set(() => _select = v),
              ),
            if (!isSelect && r.gateCh != null)
              FilterChip(
                label: Text('Điều kiện ${_name(r.gateCh!)}: ${_gate ? 'BẬT' : 'TẮT'}'),
                selected: _gate,
                onSelected: (v) => _set(() => _gate = v),
              ),
          ],
        ),
        const SizedBox(height: Gap.m),
        SizedBox(
          height: 140,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSelect) ...[
                _Column(label: _name(r.targetOnCh), value: _out[r.targetOnCh - 1], active: sel?.activeCh == r.targetOnCh),
                const SizedBox(width: Gap.xl),
                _Column(
                    label: _name(r.targetOffCh), value: _out[r.targetOffCh - 1], active: sel?.activeCh == r.targetOffCh),
              ] else
                _Column(label: _name(r.targetCh), value: _out[r.targetCh - 1], active: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dải −100…+100 với vùng giữ trạng thái tô nhạt (luật ngưỡng)
class _Band extends StatelessWidget {
  const _Band({required this.from, required this.to, required this.value});

  final double from, to, value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final band = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(builder: (context, c) {
        double x(double p) => (p + 100) / 200 * c.maxWidth;
        return SizedBox(
          height: 28,
          child: Stack(
            children: [
              Positioned.fill(
                top: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(Radii.pill)),
                ),
              ),
              Positioned(
                left: x(from),
                width: (x(to) - x(from)).clamp(2.0, c.maxWidth),
                top: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.warn.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Positioned(
                left: x(value) - 1,
                width: 2,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: t.accent),
              ),
            ],
          ),
        );
      }),
    );
    return Column(children: [
      band,
      Text('Vùng giữ trạng thái ${from.round()}–${to.round()}%',
          style: AppText.caption.copyWith(color: t.textMuted, letterSpacing: 0)),
    ]);
  }
}

/// Cột hiển thị giá trị kênh đích
class _Column extends StatelessWidget {
  const _Column({required this.label, required this.value, required this.active});

  final String label;
  final double value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Text('${value.round()}%', style: AppText.metric.copyWith(color: active ? t.text : t.textMuted)),
          const SizedBox(height: Gap.xs),
          Expanded(
            child: Container(
              width: 36,
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(Radii.field),
                border: Border.all(color: active ? t.accent : t.line),
              ),
              child: LayoutBuilder(builder: (context, c) {
                final half = c.maxHeight / 2;
                final h = (value.abs() / 100 * half).clamp(0.0, half);
                return Stack(children: [
                  Positioned(
                    left: 4,
                    right: 4,
                    top: value >= 0 ? half - h : half,
                    height: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: t.accentFill, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Positioned(left: 0, right: 0, top: half - 0.5, height: 1, child: ColoredBox(color: t.line)),
                ]);
              }),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: active ? t.accent : t.textMuted, letterSpacing: 0)),
        ],
      ),
    );
  }
}
