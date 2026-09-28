// Bảng thuộc tính phần tử (H3), gắn Input + gắn nhanh tới kênh (Sprint 4 — U5)
// và cài đặt tự về của cần gạt (H3b).
import 'package:flutter/material.dart';

import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../models/control_layout.dart';
import '../models/data_source.dart';
import '../models/input_def.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/number_field.dart';
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
    required this.onOpenMix,
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

  /// Mở tab Mix (Input có cấu hình mix phức tạp — U5)
  final VoidCallback onOpenMix;

  void _edit(VoidCallback f) {
    beforeChange();
    f();
    changed();
  }

  static const _newInput = '\u0000new';

  /// Gắn / bỏ gắn Input cho phần tử (I3). Input đang ở phần tử khác thì chuyển sang phần tử này.
  void _setInput(String? id, {bool y = false}) {
    final old = y ? item.inputIdY : item.inputId;
    if (id == old) return;
    if (id != null && id != _newInput && item.kind == ItemKind.stick2D && id == (y ? item.inputId : item.inputIdY)) {
      onMessage(tr('Hai trục phải dùng hai Input khác nhau', 'The two axes need two different Inputs'));
      return;
    }
    ControlItem? moved;
    _edit(() {
      var target = id;
      if (id == _newInput) target = profile.createInput(item.kind).id;
      moved = layout.bindInput(item, target, y: y);
    });
    final m = moved;
    if (m != null && m.id != item.id) onMessage(tr('Đã chuyển Input từ ${itemTitle(m).toLowerCase()} sang phần tử này', 'Moved the Input from ${itemTitle(m).toLowerCase()} to this control'));
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
    final isThrottle = item.inputIds.any(profile.isThrottleInput);
    final info = DataSource.info(item.source, profile);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: Gap.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title.toUpperCase(), style: AppText.caption.copyWith(color: t.textMuted)),
            const SizedBox(height: Gap.xs),
            ...children,
          ]),
        );

    // Input đang ở phần tử khác thì ghi chú; chọn sẽ chuyển Input sang phần tử này
    String inputOption(InputDef d) {
      final holder = layout.itemForInput(d.id);
      return holder == null || holder.id == item.id
          ? d.name
          : tr('${d.name} (đang ở ${holder.kind.label.toLowerCase()})', '${d.name} (on ${holder.kind.label.toLowerCase()})');
    }

    Widget inputSlot(String? value, {bool y = false}) {
      final options = profile.inputs.where((d) => d.accepts(k)).toList();
      final d = profile.input(value);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String?>(
          key: ValueKey('in-$y-$value-${profile.inputs.length}'),
          initialValue: d == null ? null : value,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(labelText: k == ItemKind.stick2D ? tr('Input trục ${y ? 'Y' : 'X'}', 'Input axis ${y ? 'Y' : 'X'}') : 'Input'),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(tr('Chưa gắn', 'Not bound'))),
            for (final o in options)
              DropdownMenuItem<String?>(value: o.id, child: Text(inputOption(o), overflow: TextOverflow.ellipsis)),
            DropdownMenuItem<String?>(value: _newInput, child: Text(tr('+ Tạo Input mới', '+ New Input'))),
          ],
          onChanged: (v) => _setInput(v, y: y),
        ),
        if (d != null) ...[
          const SizedBox(height: Gap.s),
          _InputEditor(key: ValueKey('ed-${d.id}'), input: d, profile: profile, edit: _edit, onOpenMix: onOpenMix),
        ],
      ]);
    }

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
              section('Input', [
                inputSlot(item.inputId),
                if (k == ItemKind.stick2D) ...[
                  const SizedBox(height: Gap.m),
                  inputSlot(item.inputIdY, y: true),
                ],
              ]),
            if (k.isDisplay)
              section(tr('Giá trị hiển thị', 'Displayed value'), [
                _SourcePicker(
                  key: ValueKey('src-${item.id}-${item.source}'),
                  profile: profile,
                  kind: k,
                  value: item.source,
                  label: k == ItemKind.vector ? tr('Trục X', 'X axis') : tr('Nguồn', 'Source'),
                  onChanged: (v) => _edit(() => item.source = v),
                ),
                if (k == ItemKind.vector) ...[
                  const SizedBox(height: Gap.s),
                  _SourcePicker(
                    key: ValueKey('srcy-${item.id}-${item.sourceY}'),
                    profile: profile,
                    kind: k,
                    value: item.sourceY,
                    label: tr('Trục Y', 'Y axis'),
                    onChanged: (v) => _edit(() => item.sourceY = v),
                  ),
                ],
              ]),
            if (k == ItemKind.led && info != null && !info.flag)
              section(tr('Ngưỡng sáng đèn', 'Light-up threshold'), [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('Sáng khi trên', 'On when above'))),
                    ButtonSegment(value: true, label: Text(tr('Sáng khi dưới', 'On when below'))),
                  ],
                  selected: {item.display.below ?? info.alarmBelow},
                  onSelectionChanged: (v) => _edit(() => item.display.below = v.first),
                ),
                const SizedBox(height: Gap.s),
                _DecimalField(
                  key: ValueKey('th-${item.id}-${item.source}'),
                  label: tr('Ngưỡng', 'Threshold'),
                  unit: info.unit,
                  value: item.display.threshold,
                  hint: info.alarm,
                  onChanged: (v) {
                    item.display.threshold = v;
                    changed();
                  },
                ),
              ]),
            if (k == ItemKind.led)
              section(tr('Khi sáng', 'When on'), [
                SegmentedButton<LedBlink>(
                  showSelectedIcon: false,
                  segments: [for (final b in LedBlink.values) ButtonSegment(value: b, label: Text(b.label))],
                  selected: {item.display.blink},
                  onSelectionChanged: (v) => _edit(() => item.display.blink = v.first),
                ),
              ]),
            if (k == ItemKind.bar && info != null)
              section(tr('Khoảng thanh', 'Bar range'), [
                Row(children: [
                  Expanded(
                    child: _DecimalField(
                      key: ValueKey('min-${item.id}-${item.source}'),
                      label: 'Min',
                      unit: info.unit,
                      value: item.display.min,
                      hint: info.min,
                      onChanged: (v) {
                        item.display.min = v;
                        changed();
                      },
                    ),
                  ),
                  const SizedBox(width: Gap.s),
                  Expanded(
                    child: _DecimalField(
                      key: ValueKey('max-${item.id}-${item.source}'),
                      label: 'Max',
                      unit: info.unit,
                      value: item.display.max,
                      hint: info.max,
                      onChanged: (v) {
                        item.display.max = v;
                        changed();
                      },
                    ),
                  ),
                ]),
                if ((item.display.min ?? info.min) >= (item.display.max ?? info.max))
                  Text(tr('Min phải nhỏ hơn Max', 'Min must be less than Max'),
                      style: AppText.label.copyWith(color: t.bad, fontSize: 12)),
              ]),
            if (k == ItemKind.bar || k == ItemKind.vector)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr('Hiện số', 'Show number')),
                value: item.style.valueDisplay != ValueDisplay.hidden,
                onChanged: (v) => _edit(() => item.style.valueDisplay = v ? ValueDisplay.pct : ValueDisplay.hidden),
              ),
            if ((k == ItemKind.gauge || k == ItemKind.bar || k == ItemKind.vector) &&
                item.style.valueDisplay != ValueDisplay.hidden &&
                (DataSource.chOf(item.source) != null || DataSource.chOf(item.sourceY) != null))
              section(tr('Kênh hiện theo', 'Show channel as'), [
                SegmentedButton<ValueDisplay>(
                  showSelectedIcon: false,
                  segments: [for (final v in [ValueDisplay.pct, ValueDisplay.us]) ButtonSegment(value: v, label: Text(v.label))],
                  selected: {item.style.valueDisplay == ValueDisplay.us ? ValueDisplay.us : ValueDisplay.pct},
                  onSelectionChanged: (s) => _edit(() => item.style.valueDisplay = s.first),
                ),
              ]),
            if (k == ItemKind.vector)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr('Vệt chuyển động', 'Motion trail')),
                value: item.display.trail,
                onChanged: (v) => _edit(() => item.display.trail = v),
              ),
            section(tr('Nhãn', 'Label'), [
              TextFormField(
                key: ValueKey('label-${item.id}'),
                initialValue: item.style.labelText ?? '',
                decoration: InputDecoration(
                  hintText: k.isDisplay ? DataSource.labelOf(item, profile) : profile.input(item.inputId)?.name ?? k.label,
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
                title: Text(tr('Hiện nhãn', 'Show label')),
                value: item.style.showLabel,
                onChanged: (v) => _edit(() => item.style.showLabel = v),
              ),
            ]),
            if (k.isSwitchLike)
              section('Icon', [
                Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: [
                  ChoiceChip(
                    label: Text(tr('Không', 'None')),
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
            if (k != ItemKind.statusBadge)
              section(tr('Màu', 'Color'), [
                _ColorPicker(value: item.style.color, onChanged: (a) => _edit(() => item.style.color = a)),
              ]),
            if (hasValue)
              section(tr('Hiện giá trị', 'Show value'), [
                SegmentedButton<ValueDisplay>(
                  showSelectedIcon: false,
                  segments: [for (final v in ValueDisplay.values) ButtonSegment(value: v, label: Text(v.label))],
                  selected: {item.style.valueDisplay},
                  onSelectionChanged: (s) => _edit(() => item.style.valueDisplay = s.first),
                ),
              ]),
            if (isStick)
              section(tr('Kích thước núm cầm', 'Knob size'), [
                SegmentedButton<KnobSize>(
                  showSelectedIcon: false,
                  segments: [for (final v in KnobSize.values) ButtonSegment(value: v, label: Text(v.label))],
                  selected: {item.style.knobSize},
                  onSelectionChanged: (s) => _edit(() => item.style.knobSize = s.first),
                ),
              ]),
            if (isStick) ...[
              section(k == ItemKind.stick2D ? tr('Tự về · trục X', 'Return · X axis') : tr('Tự về', 'Return'), [
                ReturnEditor(
                  cfg: item.returnCfg ??= ReturnConfig(),
                  isThrottle: profile.isThrottleInput(item.inputId),
                  vertical: k == ItemKind.stickV,
                  beforeChange: beforeChange,
                  changed: changed,
                ),
              ]),
              if (k == ItemKind.stick2D)
                section(tr('Tự về · trục Y', 'Return · Y axis'), [
                  ReturnEditor(
                    cfg: item.returnCfgY ??= ReturnConfig(),
                    isThrottle: profile.isThrottleInput(item.inputIdY),
                    vertical: true,
                    beforeChange: beforeChange,
                    changed: changed,
                  ),
                ]),
            ],
            if (hasValue)
              section(tr('Vùng chết: ${item.style.deadzonePct.round()}%', 'Deadzone: ${item.style.deadzonePct.round()}%'), [
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
                title: Text(tr('Rung khi chạm', 'Vibrate on touch')),
                value: item.style.haptic,
                onChanged: (v) => _edit(() => item.style.haptic = v),
              ),
            section(tr('Độ trong suốt: ${item.style.opacityPct.round()}%', 'Opacity: ${item.style.opacityPct.round()}%'), [
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
                child: Text(tr('Phần tử này điều khiển kênh Ga — bố cục bắt buộc phải có.', 'This control drives the throttle channel — the layout must keep it.'),
                    style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
              ),
            const SizedBox(height: Gap.m),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: AppIcon(AppIcons.delete, color: t.bad, mini: true),
              label: Text(tr('Xoá khỏi màn', 'Remove from screen'), style: TextStyle(color: t.bad)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chọn nguồn giá trị cho phần tử hiển thị, theo nhóm (đo từ xe, trạng thái, kênh, Input)
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    super.key,
    required this.profile,
    required this.kind,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final CarProfile profile;
  final ItemKind kind;
  final String? value;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = <DropdownMenuItem<String>>[];
    SourceGroup? group;
    for (final key in DataSource.options(profile, kind)) {
      final info = DataSource.info(key, profile)!;
      if (info.group != group) {
        group = info.group;
        items.add(DropdownMenuItem(
          value: '\u0000${group.name}',
          enabled: false,
          child: Text(group.label.toUpperCase(), style: AppText.caption.copyWith(color: t.textMuted)),
        ));
      }
      items.add(DropdownMenuItem(
        value: key,
        child: Padding(
          padding: const EdgeInsets.only(left: Gap.s),
          child: Text(info.unit.isEmpty || info.unit == '%' ? info.label : '${info.label} (${info.unit})',
              overflow: TextOverflow.ellipsis),
        ),
      ));
    }
    final valid = items.any((e) => e.value == value && e.enabled);
    return DropdownButtonFormField<String>(
      initialValue: valid ? value : null,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, errorText: valid ? null : tr('Chọn giá trị để hiển thị', 'Pick a value to show')),
      items: items,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Ô nhập số thập phân; để trống = dùng giá trị gợi ý (mặc định của nguồn)
class _DecimalField extends StatelessWidget {
  const _DecimalField({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.unit = '',
  });

  final String label, unit;
  final double? value;
  final double hint;
  final ValueChanged<double?> onChanged;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value == null ? '' : _fmt(value!),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: tr('Mặc định ${_fmt(hint)}', 'Default ${_fmt(hint)}'),
        suffixText: unit,
        isDense: true,
      ),
      onChanged: (v) {
        final text = v.trim().replaceAll(',', '.');
        if (text.isEmpty) {
          onChanged(null);
          return;
        }
        final d = double.tryParse(text);
        if (d != null) onChanged(d);
      },
    );
  }
}

/// Màu riêng của phần tử: theo màu chủ đạo của app ("A") hoặc một màu nhấn, kể cả đỏ / vàng
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged});

  final AccentColor? value;
  final ValueChanged<AccentColor?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget dot(AccentColor? a) {
      final on = value == a;
      final label = a?.label ?? tr('Theo màu app', 'App color');
      final onFill = a == null ? t.onAccentFill : AppTokens.of(a, Brightness.dark).onAccentFill;
      return Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: InkResponse(
            onTap: () => onChanged(a),
            radius: 22,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: a?.fill ?? t.accentFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? t.text : t.line, width: on ? 3 : 1),
                  ),
                  child: on
                      ? AppIcon(AppIcons.check, mini: true, color: onFill)
                      : a == null
                          ? Text('A', style: AppText.label.copyWith(color: onFill, fontWeight: FontWeight.w700))
                          : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(children: [dot(null), for (final a in AccentColor.values) dot(a)]),
      Text(value?.label ?? tr('Theo màu chủ đạo của app', 'Follows the app accent color'),
          style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
    ]);
  }
}

/// Sửa nhanh Input đang gắn: tên, dải (axis), mức tắt (nút/công tắc), gửi tới kênh (U5)
class _InputEditor extends StatelessWidget {
  const _InputEditor({super.key, required this.input, required this.profile, required this.edit, required this.onOpenMix});

  final InputDef input;
  final CarProfile profile;
  final void Function(VoidCallback) edit;
  final VoidCallback onOpenMix;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = input;
    final quick = profile.canQuickRoute(d.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        initialValue: d.name,
        maxLength: 24,
        decoration: InputDecoration(labelText: tr('Tên Input', 'Input name'), isDense: true, counterText: ''),
        onChanged: (v) {
          if (v.trim().isNotEmpty) edit(() => d.name = v.trim());
        },
      ),
      if (d.isAxis) ...[
        const SizedBox(height: Gap.s),
        SegmentedButton<AxisRange>(
          showSelectedIcon: false,
          segments: [for (final r in AxisRange.values) ButtonSegment(value: r, label: Text(r.label))],
          selected: {d.range},
          onSelectionChanged: (s) => edit(() => d.range = s.first),
        ),
      ],
      if (d.type == InputType.binary || d.type == InputType.ternary)
        NumberField(
          label: tr('Giá trị khi tắt', 'Value when off'),
          unit: '%',
          value: d.levels.offPct.round(),
          min: -100,
          max: 100,
          step: 5,
          onChanged: (v) => edit(() => d.levels.offPct = v.toDouble()),
        ),
      const SizedBox(height: Gap.s),
      if (quick)
        DropdownButtonFormField<int?>(
          key: ValueKey('route-${d.id}-${profile.quickRoute(d.id)}'),
          initialValue: profile.quickRoute(d.id),
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Gửi tới kênh', 'Send to channel')),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(tr('Không gửi (chỉ dùng trong luật mix)', 'Do not send (use in mix rules only)'))),
            for (var i = 1; i <= 10; i++) DropdownMenuItem<int?>(value: i, child: Text(profile.chLabel(i))),
          ],
          onChanged: (v) => edit(() => profile.setQuickRoute(d.id, v)),
        )
      else
        Row(children: [
          Expanded(
            child: Text(tr('Input này có luật mix riêng (${profile.rulesUsing(d.id).length} luật).', 'This Input has its own mix rules (${profile.rulesUsing(d.id).length}).'),
                style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
          ),
          TextButton(onPressed: onOpenMix, child: Text(tr('Dùng tab Mix', 'Use the Mix tab'))),
        ]),
    ]);
  }
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
          title: Text(tr('Nhớ vị trí cần ga?', 'Remember throttle position?')),
          content: Text(tr('Mở lại màn Lái thì ga sẽ ở vị trí cũ. Xe có thể chạy ngay khi vào màn.',
              'When you reopen the drive screen the throttle stays where it was. The car may move right away.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn bật', 'Turn on anyway'))),
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
          ActionChip(label: Text(tr('Về 0% ngay', 'To 0% instantly')), onPressed: () => _preset(ReturnConfig.instant())),
          ActionChip(label: Text(tr('Về 0% êm', 'To 0% smoothly')), onPressed: () => _preset(ReturnConfig.smooth())),
          ActionChip(label: Text(tr('Giữ vị trí', 'Hold position')), onPressed: () => _preset(ReturnConfig.holdPosition())),
        ]),
        const SizedBox(height: Gap.s),
        SegmentedButton<ReturnMode>(
          showSelectedIcon: false,
          segments: [for (final m in ReturnMode.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {c.mode},
          onSelectionChanged: (s) => _edit(() => c.mode = s.first),
        ),
        if (!hold) ...[
          label(tr('Vị trí về: ${c.targetPct.round()}%', 'Return to: ${c.targetPct.round()}%')),
          Slider(
            value: c.targetPct,
            min: -100,
            max: 100,
            divisions: 200,
            onChangeStart: (_) => widget.beforeChange(),
            onChanged: (v) => _slide(() => c.targetPct = v.roundToDouble()),
          ),
          label(tr('Trễ trước khi về: ${c.delayMs} ms', 'Delay before return: ${c.delayMs} ms')),
          Slider(
            value: c.delayMs.toDouble(),
            min: 0,
            max: 1000,
            divisions: 20,
            onChangeStart: (_) => widget.beforeChange(),
            onChanged: (v) => _slide(() => c.delayMs = v.round()),
          ),
          label(tr('Thời gian về: ${c.durationMs == 0 ? 'ngay lập tức' : '${c.durationMs} ms'}', 'Return time: ${c.durationMs == 0 ? 'instant' : '${c.durationMs} ms'}')),
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
            title: Text(tr('Chỉ tự về ở nửa dương', 'Return on positive half only')),
            value: c.positiveOnly,
            onChanged: (v) => _edit(() => c.positiveOnly = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('Chỉ tự về ở nửa âm', 'Return on negative half only')),
            value: c.negativeOnly,
            onChanged: (v) => _edit(() => c.negativeOnly = v),
          ),
        ],
        if (hold)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('Nhớ vị trí khi thoát', 'Remember position on exit')),
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
              child: Text(tr('Xe có thể tiếp tục chạy sau khi thả tay', 'The car may keep moving after you let go'),
                  style: AppText.label.copyWith(color: t.warn, fontSize: 12)),
            ),
          ]),
        label(tr('Xem trước: kéo rồi thả — ${_preview.round()}%', 'Preview: drag and release — ${_preview.round()}%')),
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
