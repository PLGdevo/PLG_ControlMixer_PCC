// Màn Lái trên nền bố cục tuỳ chỉnh (H1) + chế độ Sửa bố cục (H2, H3, H5).
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../layout/item_widgets.dart';
import '../layout/layout_canvas.dart';
import '../layout/layout_grid.dart';
import '../layout/layout_history.dart';
import '../layout/layout_templates.dart';
import '../layout/properties_panel.dart';
import '../layout/return_motion.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/control_layout.dart';
import '../protocol/protocol.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/status_badge.dart';
import 'settings_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, required this.controller, required this.repo, required this.profileId});

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late CarProfile profile;
  late final AppLifecycleListener _lifecycle;

  // Chế độ sửa bố cục
  bool editing = false;
  ControlLayout? draft;
  String? _channelsSnapshot;
  final history = LayoutHistory();
  String? selectedId;
  bool _dragging = false, _overTrash = false;
  final _trashKey = GlobalKey();

  CarController get c => widget.controller;
  ControlLayout get layout => editing ? draft! : profile.activeLayout;
  bool get _connectedHere => c.isConnected && c.connectedKey == profile.connKey;

  @override
  void initState() {
    super.initState();
    profile = widget.repo.get(widget.profileId)!;
    c.gearCountOverride = profile.gears.gearCount;
    if (c.gear > profile.gears.gearCount) c.gear = profile.gears.gearCount;
    _enterDriveMode();
    _initValues();
    // App xuống nền → cần gạt về vị trí an toàn (H3b)
    _lifecycle = AppLifecycleListener(onHide: () {
      _resetSticks();
      c.refresh();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _resetSticks(remember: true);
    c.holdNeutral = false;
    c.gearCountOverride = null;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Khoá ngang và ẩn thanh hệ thống để có tối đa diện tích điều khiển
  void _enterDriveMode() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- Giá trị kênh ----------------
  /// Vị trí ban đầu khi vào màn (H3b) và trạng thái nút/công tắc
  void _initValues() {
    for (final it in profile.activeLayout.items) {
      final ch = it.channel;
      if (ch == null) continue;
      final cfg = profile.ch(ch);
      switch (it.kind) {
        case ItemKind.stickH || ItemKind.stickV || ItemKind.stick2D:
          c.values[ch - 1] = ReturnMotion.initial(it.returnCfg ?? ReturnConfig(), it.savedPct) / 100;
          if (it.kind == ItemKind.stick2D && it.channelY != null) {
            c.values[it.channelY! - 1] = ReturnMotion.initial(it.returnCfgY ?? ReturnConfig(), it.savedPctY) / 100;
          }
        case ItemKind.button:
          c.switchPos[ch] = 0;
          c.values[ch - 1] = cfg.offValuePct / 100;
        case ItemKind.toggle || ItemKind.switch3:
          c.values[ch - 1] = _switchPct(cfg, it.kind, c.switchPos[ch] ?? 0) / 100;
        default:
          break;
      }
    }
  }

  static double _switchPct(ChannelConfig cfg, ItemKind k, int pos) {
    if (k == ItemKind.switch3) return switch (pos) { 0 => cfg.offValuePct, 1 => 0, _ => 100 };
    return pos == 1 ? 100 : cfg.offValuePct;
  }

  /// Thoát màn / vào sửa bố cục / app xuống nền: cần gạt về `targetPct`, ga "Giữ vị trí" về Center.
  /// Nút bật/tắt giữ nguyên trạng thái. Không notify (có thể đang dispose).
  void _resetSticks({bool remember = false}) {
    var dirty = false;
    for (final it in profile.activeLayout.items) {
      void axis(int? ch, ReturnConfig? cfg, void Function(double) save) {
        if (ch == null) return;
        final r = cfg ?? ReturnConfig();
        if (remember && r.mode == ReturnMode.hold && r.rememberOnExit) {
          save(c.values[ch - 1] * 100);
          dirty = true;
        }
        c.values[ch - 1] = ReturnMotion.onExit(r, isThrottle: ch == CarProfile.throttleCh) / 100;
      }

      if (it.kind.isStick) {
        axis(it.channel, it.returnCfg, (v) => it.savedPct = v);
        if (it.kind == ItemKind.stick2D) axis(it.channelY, it.returnCfgY, (v) => it.savedPctY = v);
      } else if (it.kind == ItemKind.button && it.channel != null) {
        c.switchPos[it.channel!] = 0;
        c.values[it.channel! - 1] = profile.ch(it.channel!).offValuePct / 100;
      }
    }
    if (dirty) widget.repo.save(profile, touch: false);
  }

  // ---------------- Cấu hình / trim ----------------
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(controller: c, repo: widget.repo, profileId: profile.id),
      ),
    );
    if (!mounted) return;
    _enterDriveMode();
    setState(() {
      profile = widget.repo.get(widget.profileId)!;
      c.gearCountOverride = profile.gears.gearCount;
      if (c.gear > profile.gears.gearCount) c.gear = profile.gears.gearCount;
      _initValues();
    });
  }

  Future<void> _trim(int delta) async {
    final s = profile.steering;
    final nv = (s.trimUs + delta).clamp(-200, 200).toInt();
    if (nv == s.trimUs) return;
    setState(() => s.trimUs = nv);
    await widget.repo.save(profile);
    if (_connectedHere) {
      try {
        await c.applyConfig(profile.toCarConfig());
      } catch (e) {
        _snack('Không gửi được trim: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  // ---------------- Sửa bố cục (H2, H5) ----------------
  void _startEdit() {
    if (profile.activeLayout.locked) {
      _snack('Bố cục đang khoá. Mở khoá trong menu trước.');
      return;
    }
    // Ga phải đang ở vị trí nghỉ (vị trí về đã cài, vd −28%), không bắt buộc đúng 0%
    final rest = ReturnMotion.restPct(profile.activeLayout, CarProfile.throttleCh, isThrottle: true);
    if ((c.throttle * 100 - rest).abs() > 0.1) {
      _snack('Thả cần ga trước khi sửa bố cục');
      return;
    }
    _resetSticks();
    c.holdNeutral = true; // gửi Center cho cần gạt suốt thời gian sửa
    setState(() {
      editing = true;
      draft = profile.activeLayout.copy();
      _channelsSnapshot = jsonEncode(profile.channels.map((e) => e.toJson()).toList());
      history.clear();
      selectedId = null;
    });
  }

  void _endEdit() {
    c.holdNeutral = false;
    setState(() {
      editing = false;
      draft = null;
      selectedId = null;
      _initValues();
    });
  }

  void _cancelEdit() {
    final snap = _channelsSnapshot;
    if (snap != null) {
      profile.channels = (jsonDecode(snap) as List).map((e) => ChannelConfig.fromJson(e as Map<String, dynamic>)).toList();
    }
    _endEdit();
  }

  Future<void> _saveEdit() async {
    final d = draft!;
    final err = LayoutGrid.validate(d);
    if (err != null) {
      _snack(err);
      return;
    }
    // Cảnh báo cần ga "Giữ vị trí" hoặc về chậm > 500 ms (H3b)
    final risky = d.items.any((it) =>
        (it.channel == CarProfile.throttleCh && (it.returnCfg?.risky ?? false)) ||
        (it.channelY == CarProfile.throttleCh && (it.returnCfgY?.risky ?? false)));
    if (risky) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cần ga không tự về ngay'),
          content: const Text('Xe có thể tiếp tục chạy sau khi thả tay. Vẫn lưu bố cục?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vẫn lưu')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final i = profile.layouts.indexWhere((l) => l.id == d.id);
    profile.layouts[i] = d;
    try {
      await widget.repo.save(profile);
    } catch (e) {
      _snack('Không lưu được: $e');
      return;
    }
    _endEdit();
    _snack('Đã lưu bố cục');
  }

  void _mutate(void Function(ControlLayout l) f) {
    history.push(draft!);
    setState(() => f(draft!));
  }

  void _undo() {
    final l = history.undo(draft!);
    if (l != null) setState(() => draft = l);
  }

  void _redo() {
    final l = history.redo(draft!);
    if (l != null) setState(() => draft = l);
  }

  void _delete(String id) {
    _mutate((l) => l.items.removeWhere((i) => i.id == id));
    if (selectedId == id) setState(() => selectedId = null);
  }

  Future<void> _toggleLock() async {
    final l = profile.activeLayout;
    setState(() => l.locked = !l.locked);
    await widget.repo.save(profile, touch: false);
    _snack(l.locked ? 'Đã khoá bố cục' : 'Đã mở khoá bố cục');
  }

  Future<void> _openAddSheet() async {
    final d = draft!;
    final controls = ItemKind.controls;
    final gauges = GaugeKey.values.where((g) => !d.items.any((i) => i.gaugeKey == g.name)).toList();
    final extras = [ItemKind.gearBox, ItemKind.trim, ItemKind.statusBadge]
        .where((k) => !d.items.any((i) => i.kind == k))
        .toList();
    final t = context.tokens;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.l),
          children: [
            Text('Thêm điều khiển', style: AppText.title.copyWith(color: t.text)),
            const SizedBox(height: Gap.s),
            for (final k in controls)
              ListTile(
                leading: const AppIcon(AppIcons.addControl),
                title: Text(k.label),
                subtitle: Text(_kindHint(k)),
                onTap: () => Navigator.pop(ctx, k),
              ),
            if (gauges.isNotEmpty || extras.isNotEmpty) const Divider(),
            for (final g in gauges)
              ListTile(
                leading: const CustomIconView(CustomIcon.speedometer),
                title: Text('Ô ${g.label}'),
                onTap: () => Navigator.pop(ctx, g),
              ),
            for (final k in extras)
              ListTile(
                leading: const AppIcon(AppIcons.addControl),
                title: Text(k.label),
                onTap: () => Navigator.pop(ctx, k),
              ),
            const SizedBox(height: Gap.s),
            Text('Thêm xong, chọn phần tử để gán kênh và chỉnh cấu hình riêng của nó.',
                style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
    if (picked == null) return;
    ControlItem? added;
    history.push(d);
    setState(() {
      added = switch (picked) {
        GaugeKey g => LayoutTemplates.addWidget(d, ItemKind.gauge, gaugeKey: g.name),
        ItemKind k when k.isControl => LayoutTemplates.addControl(d, k),
        ItemKind k => LayoutTemplates.addWidget(d, k),
        _ => null,
      };
      if (added != null) selectedId = added!.id;
    });
    if (added == null) _snack('Không còn chỗ trống đủ lớn trên màn');
  }

  static String _kindHint(ItemKind k) => switch (k) {
        ItemKind.stickH || ItemKind.stickV => '−100…+100%, tự về khi thả (chỉnh được)',
        ItemKind.stick2D => 'Điều khiển 2 kênh X/Y',
        ItemKind.button => 'Bật khi giữ, thả ra là tắt',
        ItemKind.toggle => 'Mỗi lần bấm đổi trạng thái',
        ItemKind.switch3 => 'Tắt / 0% / +100%',
        ItemKind.knob => 'Giữ nguyên vị trí',
        _ => '',
      };

  // ---------------- Giao diện ----------------
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mq = MediaQuery.of(context);
    // Tránh vùng cử chỉ hệ thống và tai thỏ (H5)
    final vp = mq.viewPadding, sg = mq.systemGestureInsets;
    final insets = EdgeInsets.fromLTRB(
      max(vp.left, sg.left) + Gap.s,
      Gap.xs,
      max(vp.right, sg.right) + Gap.s,
      max(vp.bottom, sg.bottom) + Gap.s,
    );
    final selected = editing ? draft!.items.where((i) => i.id == selectedId).firstOrNull : null;
    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && editing) _cancelEdit();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        body: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: insets,
                    child: Column(
                      children: [
                        SizedBox(height: 48, child: editing ? _editBar() : _driveBar()),
                        const SizedBox(height: Gap.xs),
                        Expanded(
                          child: LayoutCanvas(
                            layout: layout,
                            editing: editing,
                            selectedId: selectedId,
                            itemBuilder: _buildItem,
                            onSelect: (id) => setState(() => selectedId = id),
                            onRectChanged: (id, r) => _mutate((l) {
                              final it = l.items.firstWhere((i) => i.id == id);
                              it
                                ..x = r.x
                                ..y = r.y
                                ..w = r.w
                                ..h = r.h;
                            }),
                            onDelete: _delete,
                            trashKey: _trashKey,
                            onDragState: (dragging, over) => setState(() {
                              _dragging = dragging;
                              _overTrash = over;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selected != null)
                  SizedBox(
                    width: min(340, mq.size.width * 0.42),
                    child: PropertiesPanel(
                      key: ValueKey(selected.id),
                      item: selected,
                      profile: profile,
                      layout: draft!,
                      beforeChange: () => history.push(draft!),
                      changed: () => setState(() {}),
                      onDelete: () => _delete(selected.id),
                      onClose: () => setState(() => selectedId = null),
                      onMessage: _snack,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _driveBar() {
    final t = context.tokens;
    final tel = c.telemetry;
    final disconnected = c.state == LinkState.disconnected;
    final alarm = disconnected || c.state == LinkState.lost || (tel?.failsafe ?? false);
    final l = profile.activeLayout;
    return Row(
      children: [
        IconButton(icon: const AppIcon(AppIcons.back), onPressed: () => Navigator.pop(context)),
        Flexible(
          child: Text(profile.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title.copyWith(color: t.text)),
        ),
        const SizedBox(width: Gap.m),
        Expanded(
          child: alarm
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.xs),
                  decoration: BoxDecoration(
                    color: t.bad.withValues(alpha: 0.18),
                    border: Border.all(color: t.bad),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon(AppIcons.warning, color: t.bad, mini: true),
                    const SizedBox(width: Gap.s),
                    Flexible(
                      child: Text(
                        disconnected ? 'Chưa kết nối xe' : 'Failsafe: xe đang ở chế độ an toàn',
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(color: t.bad, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
        PopupMenuButton<String>(
          tooltip: 'Tuỳ chọn',
          icon: const AppIcon(AppIcons.config),
          onSelected: (v) {
            switch (v) {
              case 'settings':
                _openSettings();
              case 'edit':
                _startEdit();
              case 'lock':
                _toggleLock();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'settings',
              child: ListTile(leading: AppIcon(AppIcons.settings), title: Text('Cấu hình')),
            ),
            PopupMenuItem(
              value: 'edit',
              enabled: !l.locked,
              child: ListTile(
                leading: const AppIcon(AppIcons.edit),
                title: const Text('Sửa bố cục'),
                subtitle: l.locked ? const Text('Đang khoá') : null,
              ),
            ),
            PopupMenuItem(
              value: 'lock',
              child: ListTile(
                leading: AppIcon(l.locked ? AppIcons.locked : AppIcons.unlocked),
                title: Text(l.locked ? 'Mở khoá bố cục' : 'Khoá bố cục'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _editBar() {
    final t = context.tokens;
    return Row(
      children: [
        TextButton.icon(
          onPressed: _cancelEdit,
          icon: const AppIcon(AppIcons.close, mini: true),
          label: const Text('Huỷ'),
        ),
        IconButton(
          tooltip: 'Hoàn tác',
          onPressed: history.canUndo ? _undo : null,
          icon: const AppIcon(AppIcons.undo),
        ),
        IconButton(
          tooltip: 'Làm lại',
          onPressed: history.canRedo ? _redo : null,
          icon: const AppIcon(AppIcons.redo),
        ),
        const SizedBox(width: Gap.s),
        Expanded(
          child: Center(
            child: AnimatedContainer(
              key: _trashKey,
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: Gap.l, vertical: Gap.xs),
              decoration: BoxDecoration(
                color: _overTrash ? t.bad.withValues(alpha: 0.25) : Colors.transparent,
                border: Border.all(color: _dragging ? t.bad : t.line),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(AppIcons.delete, color: _dragging ? t.bad : t.textMuted, mini: true),
                const SizedBox(width: Gap.xs),
                Text(_dragging ? 'Thả vào đây để xoá' : 'Sửa bố cục · kéo để di chuyển',
                    style: AppText.label.copyWith(color: _dragging ? t.bad : t.textMuted)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: Gap.s),
        OutlinedButton.icon(
          onPressed: _openAddSheet,
          icon: const AppIcon(AppIcons.plus, mini: true),
          label: const Text('Thêm'),
        ),
        const SizedBox(width: Gap.s),
        FilledButton.icon(
          onPressed: _saveEdit,
          icon: const AppIcon(AppIcons.save, mini: true),
          label: const Text('Lưu'),
        ),
      ],
    );
  }

  // ---------------- Phần tử ----------------
  String _label(ControlItem it) {
    if (!it.style.showLabel) return '';
    final custom = it.style.labelText;
    if (custom != null && custom.trim().isNotEmpty) return custom;
    if (it.channel != null) return profile.ch(it.channel!).name;
    return it.kind.label;
  }

  String? _valueText(ControlItem it, int ch) {
    final pct = c.values[ch - 1] * 100;
    return switch (it.style.valueDisplay) {
      ValueDisplay.pct => '${pct.round()}%',
      ValueDisplay.us => '${profile.ch(ch).pctToUs(pct)} µs',
      ValueDisplay.hidden => null,
    };
  }

  Widget _buildItem(BuildContext context, ControlItem it) {
    final t = context.tokens;
    final label = _label(it);
    final lbl = label.isEmpty ? null : label;
    final ch = it.channel;
    if (it.kind.isControl && ch == null) {
      return ItemFrame(
        label: it.kind.label,
        child: Center(child: Text('Chưa gán kênh', style: AppText.label.copyWith(color: t.textMuted))),
      );
    }
    switch (it.kind) {
      case ItemKind.stickH || ItemKind.stickV:
        return ItemFrame(
          label: lbl,
          trailing: _valueText(it, ch!),
          child: StickAxis(
            value: c.values[ch - 1] * 100,
            vertical: it.kind == ItemKind.stickV,
            returnCfg: it.returnCfg,
            deadzonePct: it.style.deadzonePct,
            haptic: it.style.haptic,
            knobSize: it.style.knobSize,
            onChanged: (v) => c.setChannel(ch, v / 100),
          ),
        );
      case ItemKind.stick2D:
        final cy = it.channelY;
        final xs = _valueText(it, ch!);
        final ys = cy == null ? null : _valueText(it, cy);
        return ItemFrame(
          label: lbl,
          trailing: xs == null ? null : 'X $xs${ys == null ? '' : ' · Y $ys'}',
          child: Stick2D(
            x: c.values[ch - 1] * 100,
            y: cy == null ? 0 : c.values[cy - 1] * 100,
            returnX: it.returnCfg,
            returnY: it.returnCfgY,
            deadzonePct: it.style.deadzonePct,
            haptic: it.style.haptic,
            knobSize: it.style.knobSize,
            onChanged: (x, y) {
              c.values[ch - 1] = x / 100;
              if (cy != null) c.values[cy - 1] = y / 100;
              c.refresh();
            },
          ),
        );
      case ItemKind.button || ItemKind.toggle:
        final cfg = profile.ch(ch!);
        return ChannelButton(
          on: (c.switchPos[ch] ?? 0) == 1,
          label: lbl,
          momentary: it.kind == ItemKind.button,
          icon: AppIcons.pickable[it.style.iconName],
          haptic: it.style.haptic,
          onChanged: (on) {
            c.switchPos[ch] = on ? 1 : 0;
            c.setChannel(ch, _switchPct(cfg, it.kind, on ? 1 : 0) / 100);
          },
        );
      case ItemKind.switch3:
        final cfg = profile.ch(ch!);
        final icon = AppIcons.pickable[it.style.iconName];
        return ItemFrame(
          label: lbl,
          child: Row(children: [
            if (icon != null) ...[AppIcon(icon, mini: true, color: t.textMuted), const SizedBox(width: Gap.xs)],
            Expanded(
              child: Switch3(
                position: c.switchPos[ch] ?? 0,
                haptic: it.style.haptic,
                onChanged: (p) {
                  c.switchPos[ch] = p;
                  c.setChannel(ch, _switchPct(cfg, ItemKind.switch3, p) / 100);
                },
              ),
            ),
          ]),
        );
      case ItemKind.knob:
        return ItemFrame(
          label: lbl,
          trailing: _valueText(it, ch!),
          child: Knob(
            value: c.values[ch - 1] * 100,
            haptic: it.style.haptic,
            onChanged: (v) => c.setChannel(ch, ReturnMotion.deadzone(v, it.style.deadzonePct) / 100),
          ),
        );
      case ItemKind.gauge:
        return _gauge(it);
      case ItemKind.gearBox:
        return _gearBox(lbl);
      case ItemKind.trim:
        return _trimBox(lbl);
      case ItemKind.statusBadge:
        return Center(child: FittedBox(child: StatusBadge(state: c.state)));
    }
  }

  Widget _gauge(ControlItem it) {
    final Telemetry? tel = c.telemetry;
    final key = GaugeKey.values.asNameMap()[it.gaugeKey] ?? GaugeKey.battery;
    final label = it.style.showLabel ? (it.style.labelText ?? key.label) : '';
    final (Widget icon, String value, String? sub) = switch (key) {
      GaugeKey.battery => (
          AppIcon(tel == null ? AppIcons.batteryEmpty : AppIcons.batteryHalf),
          tel == null ? '--' : '${tel.batteryV.toStringAsFixed(2)} V',
          null
        ),
      GaugeKey.current => (
          const AppIcon(AppIcons.current),
          tel == null ? '--' : '${tel.currentA.toStringAsFixed(1)} A',
          null
        ),
      GaugeKey.speed => (
          const CustomIconView(CustomIcon.speedometer),
          tel == null ? '--' : '${tel.speedKmh.toStringAsFixed(1)} km/h',
          null
        ),
      // Ping ngầm khi lái (F6) thuộc Sprint 4; tạm hiện RSSI ở dòng phụ
      GaugeKey.ping => (
          const AppIcon(AppIcons.signal),
          '--',
          tel == null || tel.rssi == 0 ? null : 'RSSI ${tel.rssi} dBm'
        ),
      GaugeKey.rssi => (
          AppIcon(tel == null || tel.rssi == 0 ? AppIcons.signalOff : AppIcons.signal),
          tel == null || tel.rssi == 0 ? '--' : '${tel.rssi} dBm',
          null
        ),
    };
    return GaugeTile(label: label, value: value, sub: sub, icon: icon);
  }

  Widget _gearBox(String? label) {
    final t = context.tokens;
    final g = c.gear.clamp(1, profile.gears.gearCount).toInt();
    final limit = profile.gears.maxThrottle[g - 1];
    return ItemFrame(
      label: label,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xs),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: c.gear > 1 ? c.gearDown : null,
            icon: const AppIcon(AppIcons.minus),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Số $g', style: AppText.display.copyWith(fontSize: 26, color: t.text)),
                Text('Ga tối đa $limit%', style: AppText.caption.copyWith(color: t.textMuted, letterSpacing: 0)),
              ]),
            ),
          ),
          IconButton.outlined(
            onPressed: c.gear < profile.gears.gearCount ? c.gearUp : null,
            icon: const AppIcon(AppIcons.plus),
          ),
        ],
      ),
    );
  }

  Widget _trimBox(String? label) {
    final t = context.tokens;
    return ItemFrame(
      label: label,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xs),
      child: Row(
        children: [
          OutlinedButton(onPressed: () => _trim(-5), child: const Text('◀')),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Trim ${profile.steering.trimUs} µs', style: AppText.metric.copyWith(color: t.text)),
            ),
          ),
          OutlinedButton(onPressed: () => _trim(5), child: const Text('▶')),
        ],
      ),
    );
  }
}
