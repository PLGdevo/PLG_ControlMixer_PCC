// Bảng thuộc tính phần tử (H3) và cài đặt tự về của cần gạt (H3b).
import 'package:flutter/material.dart';

import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../widgets/number_field.dart';
import '../models/control_layout.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'item_widgets.dart';

class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({
    super.key,
    required this.item,
    required this.profile,
    required this.layout,
    required this.beforeChange,
    required this.changed,
    required this.onDelete,
    required this.onClose,
    required this.onMessage,
  });

  final ControlItem item;
  final CarProfile profile;
  final ControlLayout layout;

  /// Gọi TRƯỚC khi sửa (để lưu lịch sử hoàn tác)
  final VoidCallback beforeChange;

  /// Gọi SAU khi sửa (vẽ lại)
  final VoidCallback changed;
  final VoidCallback onDelete, onClose;
  final ValueChanged<String> onMessage;

  void _edit(VoidCallback f) {
    beforeChange();
    f();
    changed();
  }

  String _chName(int n) {
    final c = profile.ch(n);
    return c.name == 'Kênh $n' ? 'CH$n' : 'CH$n · ${c.name}';
  }

  /// Gán / bỏ gán kênh cho phần tử (H3). Kênh đang ở phần tử khác thì chuyển sang phần tử này (H7).
  void _setChannel(int? newCh, {bool y = false}) {
    final old = y ? item.channelY : item.channel;
    if (newCh == old) return;
    if (newCh != null && item.kind == ItemKind.stick2D && newCh == (y ? item.channel : item.channelY)) {
      onMessage('Hai trục phải dùng hai kênh khác nhau');
      return;
    }
    ControlItem? moved;
    _edit(() {
      if (newCh == null) {
        layout.assignChannel(item, null, y: y);
      } else {
        moved = profile.assignChannel(item, newCh, y: y, l: layout);
      }
    });
    final m = moved;
    if (m != null && m.id != item.id) onMessage('Đã chuyển CH$newCh từ ${itemTitle(m).toLowerCase()} sang phần tử này');
  }

  /// Tên hiển thị của phần tử: nhãn tự đặt, nếu không thì loại phần tử
  static String itemTitle(ControlItem it) {
    final l = it.style.labelText;
    return l != null && l.trim().isNotEmpty ? '${it.kind.label} "$l"' : it.kind.label;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final k = item.kind;
    final isStick = k.isStick;
    final hasValue = isStick || k == ItemKind.knob;
    final isThrottle = item.channels.contains(CarProfile.throttleCh);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: Gap.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title.toUpperCase(), style: AppText.caption.copyWith(color: t.textMuted)),
            const SizedBox(height: Gap.xs),
            ...children,
          ]),
        );

    // Kênh đang ở phần tử khác thì ghi chú; chọn sẽ chuyển kênh sang phần tử này
    String chOption(int i) {
      final holder = layout.itemForChannel(i);
      return holder == null || holder.id == item.id ? _chName(i) : '${_chName(i)} (đang ở ${holder.kind.label.toLowerCase()})';
    }

    Widget chPicker(int? value, ValueChanged<int?> onPick, String label) => DropdownButtonFormField<int?>(
          key: ValueKey('$label-$value'),
          initialValue: value,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Chưa gán')),
            for (var i = 1; i <= 10; i++)
              DropdownMenuItem<int?>(value: i, child: Text(chOption(i), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onPick,
        );

    return Material(
      color: t.surface,
      shape: Border(left: BorderSide(color: t.line)),
      child: SafeArea(
        left: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.l, Gap.s, Gap.l, Gap.xl),
          children: [
            Row(children: [
              Expanded(child: Text(k.label, style: AppText.title.copyWith(color: t.text))),
              IconButton(onPressed: onClose, icon: const AppIcon(AppIcons.close)),
            ]),
            if (k.isControl)
              section('Gán kênh', [
                chPicker(item.channel, (v) => _setChannel(v), k == ItemKind.stick2D ? 'Trục X' : 'Kênh'),
                if (k == ItemKind.stick2D) ...[
                  const SizedBox(height: Gap.s),
                  chPicker(item.channelY, (v) => _setChannel(v, y: true), 'Trục Y'),
                ],
                if (item.channel != null && k.isSwitchLike) ...[
                  const SizedBox(height: Gap.s),
                  _OffValueField(ch: profile.ch(item.channel!), beforeChange: beforeChange, changed: changed),
                ],
              ]),
            if (k == ItemKind.gauge)
              section('Ô đồng hồ', [
                DropdownButtonFormField<String>(
                  key: ValueKey(item.gaugeKey),
                  initialValue: item.gaugeKey,
                  isDense: true,
                  items: [for (final g in GaugeKey.values) DropdownMenuItem(value: g.name, child: Text(g.label))],
                  onChanged: (v) => _edit(() => item.gaugeKey = v),
                ),
              ]),
            section('Nhãn', [
              TextFormField(
                key: ValueKey('label-${item.id}'),
                initialValue: item.style.labelText ?? '',
                decoration: InputDecoration(
                  hintText: item.channel != null ? profile.ch(item.channel!).name : k.label,
                  isDense: true,
                ),
                onChanged: (v) {
                  item.style.labelText = v.trim().isEmpty ? null : v;
                  changed();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Hiện nhãn'),
                value: item.style.showLabel,
                onChanged: (v) => _edit(() => item.style.showLabel = v),
              ),
            ]),
            if (k.isSwitchLike)
              section('Icon', [
                Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: [
                  ChoiceChip(
                    label: const Text('Không'),
                    selected: item.style.iconName == null,
                    onSelected: (_) => _edit(() => item.style.iconName = null),
                  ),
                  for (final e in AppIcons.pickable.entries)
                    ChoiceChip(
                      label: AppIcon(e.value, mini: true),
                      selected: item.style.iconName == e.key,
                      onSelected: (_) => _edit(() => item.style.iconName = e.key),
                    ),
                ]),
              ]),
            if (hasValue)
              section('Hiện giá trị', [
                SegmentedButton<ValueDisplay>(
                  showSelectedIcon: false,
                  segments: [for (final v in ValueDisplay.values) ButtonSegment(value: v, label: Text(v.label))],
                  selected: {item.style.valueDisplay},
                  onSelectionChanged: (s) => _edit(() => item.style.valueDisplay = s.first),
                ),
              ]),
            if (isStick)
              section('Kích thước núm cầm', [
                SegmentedButton<KnobSize>(
                  showSelectedIcon: false,
                  segments: [for (final v in KnobSize.values) ButtonSegment(value: v, label: Text(v.label))],
                  selected: {item.style.knobSize},
                  onSelectionChanged: (s) => _edit(() => item.style.knobSize = s.first),
                ),
              ]),
            if (isStick) ...[
              section(k == ItemKind.stick2D ? 'Tự về · trục X' : 'Tự về', [
                ReturnEditor(
                  cfg: item.returnCfg ??= ReturnConfig(),
                  isThrottle: item.channel == CarProfile.throttleCh,
                  vertical: k == ItemKind.stickV,
                  beforeChange: beforeChange,
                  changed: changed,
                ),
              ]),
              if (k == ItemKind.stick2D)
                section('Tự về · trục Y', [
                  ReturnEditor(
                    cfg: item.returnCfgY ??= ReturnConfig(),
                    isThrottle: item.channelY == CarProfile.throttleCh,
                    vertical: true,
                    beforeChange: beforeChange,
                    changed: changed,
                  ),
                ]),
            ],
            if (hasValue)
              section('Vùng chết: ${item.style.deadzonePct.round()}%', [
                Slider(
                  value: item.style.deadzonePct,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChangeStart: (_) => beforeChange(),
                  onChanged: (v) {
                    item.style.deadzonePct = v;
                    changed();
                  },
                ),
              ]),
            if (k.isControl)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rung khi chạm'),
                value: item.style.haptic,
                onChanged: (v) => _edit(() => item.style.haptic = v),
              ),
            section('Độ trong suốt: ${item.style.opacityPct.round()}%', [
              Slider(
                value: item.style.opacityPct,
                min: 30,
                max: 100,
                divisions: 14,
                onChangeStart: (_) => beforeChange(),
                onChanged: (v) {
                  item.style.opacityPct = v;
                  changed();
                },
              ),
            ]),
            if (isThrottle && k.isControl)
              Padding(
                padding: const EdgeInsets.only(top: Gap.s),
                child: Text('Phần tử này điều khiển kênh Ga — bố cục bắt buộc phải có.',
                    style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
              ),
            const SizedBox(height: Gap.m),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: AppIcon(AppIcons.delete, color: t.bad, mini: true),
              label: Text('Xoá khỏi màn', style: TextStyle(color: t.bad)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Giá trị khi tắt của kênh gán vào nút / công tắc (B1)
class _OffValueField extends StatelessWidget {
  const _OffValueField({required this.ch, required this.beforeChange, required this.changed});

  final ChannelConfig ch;
  final VoidCallback beforeChange, changed;

  @override
  Widget build(BuildContext context) => NumberField(
        label: 'Giá trị khi tắt',
        unit: '%',
        value: ch.offValuePct.round(),
        min: -100,
        max: 100,
        step: 5,
        onChanged: (v) {
          beforeChange();
          ch.offValuePct = v.toDouble();
          changed();
        },
      );
}

/// Cài đặt tự về cho một trục (H3b), có thanh xem trước
class ReturnEditor extends StatefulWidget {
  const ReturnEditor({
    super.key,
    required this.cfg,
    required this.isThrottle,
    required this.vertical,
    required this.beforeChange,
    required this.changed,
  });

  final ReturnConfig cfg;
  final bool isThrottle, vertical;
  final VoidCallback beforeChange, changed;

  @override
  State<ReturnEditor> createState() => _ReturnEditorState();
}

class _ReturnEditorState extends State<ReturnEditor> {
  double _preview = 0;

  ReturnConfig get c => widget.cfg;

  void _edit(VoidCallback f) {
    widget.beforeChange();
    f();
    widget.changed();
    setState(() {});
  }

  void _slide(VoidCallback f) {
    f();
    widget.changed();
    setState(() {});
  }

  void _preset(ReturnConfig p) => _edit(() {
        c
          ..mode = p.mode
          ..targetPct = p.targetPct
          ..delayMs = p.delayMs
          ..durationMs = p.durationMs
          ..curve = p.curve
          ..positiveOnly = false
          ..negativeOnly = false
          ..rememberOnExit = false;
        _preview = c.targetPct;
      });

  Future<void> _setRemember(bool v) async {
    if (v && widget.isThrottle) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nhớ vị trí cần ga?'),
          content: const Text('Mở lại màn Lái thì ga sẽ ở vị trí cũ. Xe có thể chạy ngay khi vào màn.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vẫn bật')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _edit(() => c.rememberOnExit = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hold = c.mode == ReturnMode.hold;
    final err = c.validate();
    Widget label(String s) =>
        Padding(padding: const EdgeInsets.only(top: Gap.s), child: Text(s, style: AppText.label.copyWith(color: t.text)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: [
          ActionChip(label: const Text('Về 0% ngay'), onPressed: () => _preset(ReturnConfig.instant())),
          ActionChip(label: const Text('Về 0% êm'), onPressed: () => _preset(ReturnConfig.smooth())),
          ActionChip(label: const Text('Giữ vị trí'), onPressed: () => _preset(ReturnConfig.holdPosition())),
        ]),
        const SizedBox(height: Gap.s),
        SegmentedButton<ReturnMode>(
          showSelectedIcon: false,
          segments: [for (final m in ReturnMode.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {c.mode},
          onSelectionChanged: (s) => _edit(() => c.mode = s.first),
        ),
        if (!hold) ...[
          label('Vị trí về: ${c.targetPct.round()}%'),
          Slider(
            value: c.targetPct,
            min: -100,
            max: 100,
            divisions: 200,
            onChangeStart: (_) => widget.beforeChange(),
            onChanged: (v) => _slide(() => c.targetPct = v.roundToDouble()),
          ),
          label('Trễ trước khi về: ${c.delayMs} ms'),
          Slider(
            value: c.delayMs.toDouble(),
            min: 0,
            max: 1000,
            divisions: 20,
            onChangeStart: (_) => widget.beforeChange(),
            onChanged: (v) => _slide(() => c.delayMs = v.round()),
          ),
          label('Thời gian về: ${c.durationMs == 0 ? 'ngay lập tức' : '${c.durationMs} ms'}'),
          Slider(
            value: c.durationMs.toDouble(),
            min: 0,
            max: 2000,
            divisions: 40,
            onChangeStart: (_) => widget.beforeChange(),
            onChanged: (v) => _slide(() => c.durationMs = v.round()),
          ),
          if (c.durationMs > 0)
            SegmentedButton<ReturnCurve>(
              showSelectedIcon: false,
              segments: [for (final m in ReturnCurve.values) ButtonSegment(value: m, label: Text(m.label))],
              selected: {c.curve},
              onSelectionChanged: (s) => _edit(() => c.curve = s.first),
            ),
        ],
        if (c.mode == ReturnMode.halfSpring) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Chỉ tự về ở nửa dương'),
            value: c.positiveOnly,
            onChanged: (v) => _edit(() => c.positiveOnly = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Chỉ tự về ở nửa âm'),
            value: c.negativeOnly,
            onChanged: (v) => _edit(() => c.negativeOnly = v),
          ),
        ],
        if (hold)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Nhớ vị trí khi thoát'),
            value: c.rememberOnExit,
            onChanged: _setRemember,
          ),
        if (err != null)
          Text(err, style: AppText.label.copyWith(color: t.bad, fontSize: 12))
        else if (widget.isThrottle && c.risky)
          Row(children: [
            AppIcon(AppIcons.warning, color: t.warn, mini: true),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text('Xe có thể tiếp tục chạy sau khi thả tay',
                  style: AppText.label.copyWith(color: t.warn, fontSize: 12)),
            ),
          ]),
        label('Xem trước: kéo rồi thả — ${_preview.round()}%'),
        const SizedBox(height: Gap.xs),
        SizedBox(
          height: 44,
          child: StickAxis(
            value: _preview,
            vertical: false,
            returnCfg: c,
            haptic: false,
            onChanged: (v) => setState(() => _preview = v),
          ),
        ),
      ],
    );
  }
}
