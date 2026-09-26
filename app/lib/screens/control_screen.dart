// Màn Lái trên nền bố cục tuỳ chỉnh (H1) + chế độ Sửa bố cục (H2, H3, H5).
// Phần tử ghi vào Input; mixer quyết định kênh (Sprint 4). Có ARM / DISARM (R1–R3).
import 'dart:async';
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
import '../models/control_layout.dart';
import '../protocol/protocol.dart';
import '../services/arm_controller.dart';
import '../services/output_pipeline.dart';
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
  String? _profileSnapshot;
  List<String> _errors = const [];
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
    _loadProfile();
    _initValues();
    c.armCheck = _armCheck;
    // App xuống nền → DISARM, cần gạt về vị trí an toàn (H3b, R3)
    _lifecycle = AppLifecycleListener(onHide: () {
      c.arm.disarm('App xuống nền');
      _resetSticks();
      c.refresh();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _resetSticks(remember: true);
    c.unloadProfile();
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

  // ---------------- Giá trị Input ----------------
  /// Nạp hồ sơ vào vòng gửi (sau khi mở màn / sửa cấu hình / sửa bố cục)
  void _loadProfile() {
    c.loadProfile(profile);
    _errors = profile.validateAll();
  }

  /// Điều kiện ARM (R2), controller gọi mỗi chu kỳ
  ArmCheck _armCheck() => ArmCheck(
        profileValid: _errors.isEmpty,
        throttleAtRest: c.pipeline?.throttleAtRest(profile.activeLayout) ?? true,
        editing: editing,
      );

  /// Vị trí ban đầu khi vào màn (H3b); nút nhấn giữ về tắt, nút bật/tắt và công tắc giữ trạng thái
  void _initValues() {
    for (final it in profile.activeLayout.items) {
      final id = it.inputId;
      if (id == null) continue;
      switch (it.kind) {
        case ItemKind.stickH || ItemKind.stickV || ItemKind.stick2D:
          c.setPosition(id, ReturnMotion.initial(it.returnCfg ?? ReturnConfig(), it.savedPct), notify: false);
          final y = it.inputIdY;
          if (it.kind == ItemKind.stick2D && y != null) {
            c.setPosition(y, ReturnMotion.initial(it.returnCfgY ?? ReturnConfig(), it.savedPctY), notify: false);
          }
        case ItemKind.button:
          c.setSwitch(id, 0, notify: false);
        default:
          break;
      }
    }
  }

  /// Thoát màn / vào sửa bố cục / app xuống nền: cần gạt về `targetPct`, ga "Giữ vị trí" về Center.
  /// Nút bật/tắt giữ nguyên trạng thái. Không notify (có thể đang dispose).
  void _resetSticks({bool remember = false}) {
    var dirty = false;
    for (final it in profile.activeLayout.items) {
      void axis(String? id, ReturnConfig? cfg, void Function(double) save) {
        if (id == null) return;
        final r = cfg ?? ReturnConfig();
        if (remember && r.mode == ReturnMode.hold && r.rememberOnExit) {
          save(c.position(id));
          dirty = true;
        }
        c.setPosition(id, ReturnMotion.onExit(r, isThrottle: profile.isThrottleInput(id)), notify: false);
      }

      if (it.kind.isStick) {
        axis(it.inputId, it.returnCfg, (v) => it.savedPct = v);
        if (it.kind == ItemKind.stick2D) axis(it.inputIdY, it.returnCfgY, (v) => it.savedPctY = v);
      } else if (it.kind == ItemKind.button && it.inputId != null) {
        c.setSwitch(it.inputId!, 0, notify: false);
      }
    }
    if (dirty) widget.repo.save(profile, touch: false);
  }

  // ---------------- Cấu hình / trim ----------------
  Future<void> _openSettings({int tab = 0}) async {
    c.arm.disarm('Mở Cấu hình');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(controller: c, repo: widget.repo, profileId: profile.id, initialTab: tab),
      ),
    );
    if (!mounted) return;
    _enterDriveMode();
    setState(() {
      profile = widget.repo.get(widget.profileId)!;
      c.gearCountOverride = profile.gears.gearCount;
      if (c.gear > profile.gears.gearCount) c.gear = profile.gears.gearCount;
      _loadProfile();
      _initValues();
    });
  }

  /// Trim nhanh cho kênh Lái đã chọn trong hồ sơ
  Future<void> _trim(int delta) async {
    final s = profile.steering;
    if (s == null) return;
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
    // Ga phải đang ở vị trí nghỉ (vị trí về đã cài, vd −28%), không bắt buộc đúng 0% (H5-1)
    if (!(c.pipeline?.throttleAtRest(profile.activeLayout) ?? true)) {
      _snack('Thả cần ga trước khi sửa bố cục');
      return;
    }
    _resetSticks();
    c.arm.disarm('Đang sửa bố cục'); // chưa ARM → không gửi lệnh lái suốt thời gian sửa (H5, R3)
    setState(() {
      editing = true;
      draft = profile.activeLayout.copy();
      _profileSnapshot = jsonEncode(profile.toJson());
      history.clear();
      selectedId = null;
    });
  }

  void _endEdit() {
    setState(() {
      editing = false;
      draft = null;
      selectedId = null;
      _loadProfile();
      _initValues();
    });
  }

  /// Huỷ: bỏ mọi thay đổi từ lúc vào chế độ sửa, kể cả Input / luật tạo từ bảng thuộc tính
  void _cancelEdit() {
    final snap = _profileSnapshot;
    if (snap != null) profile = CarProfile.fromJson(jsonDecode(snap) as Map<String, dynamic>);
    _endEdit();
  }

  Future<void> _saveEdit() async {
    final d = draft!;
    final err = LayoutGrid.validate(
      d,
      throttleInputs: profile.throttleInputs,
      steerInputs: profile.steeringInputs,
    );
    if (err != null) {
      _snack(err);
      return;
    }
    // Cảnh báo cần ga "Giữ vị trí" hoặc về chậm > 500 ms (H3b)
    final risky = d.items.any((it) =>
        (profile.isThrottleInput(it.inputId) && (it.returnCfg?.risky ?? false)) ||
        (profile.isThrottleInput(it.inputIdY) && (it.returnCfgY?.risky ?? false)));
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
            Text('Thêm xong, chọn phần tử để gắn Input, chọn kênh và chỉnh cấu hình riêng của nó.',
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
        ItemKind.stick2D => 'Hai Input X/Y',
        ItemKind.button => 'Bật khi giữ, thả ra là tắt',
        ItemKind.toggle => 'Mỗi lần bấm đổi trạng thái',
        ItemKind.switch3 => 'Trái / giữa / phải',
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
                      onOpenMix: () => _snack('Lưu bố cục, rồi mở Cấu hình ▸ Mix để sửa luật của Input này'),
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
        const SizedBox(width: Gap.s),
        _ArmButton(controller: c, check: _armCheck, onMessage: _snack),
        const SizedBox(width: Gap.s),
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
                        disconnected
                            ? 'Chưa kết nối xe'
                            : (tel?.netSetup ?? false)
                                ? 'Xe đang ở chế độ cấu hình mạng: không lái được'
                                : 'Failsafe: xe đang ở chế độ an toàn',
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
              case 'mix':
                _openSettings(tab: 3);
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
            const PopupMenuItem(
              value: 'mix',
              child: ListTile(leading: AppIcon(AppIcons.mix), title: Text('Luật mix')),
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
    return profile.input(it.inputId)?.name ?? it.kind.label;
  }

  /// Giá trị hiện trên phần tử: % của Input, hoặc µs của kênh nếu Input được gắn nhanh tới một kênh
  String? _valueText(ControlItem it, String id) {
    final pct = c.pipeline?.inputs.valueOf(id) ?? c.position(id);
    switch (it.style.valueDisplay) {
      case ValueDisplay.hidden:
        return null;
      case ValueDisplay.pct:
        return '${pct.round()}%';
      case ValueDisplay.us:
        final ch = profile.canQuickRoute(id) ? profile.quickRoute(id) : null;
        final out = c.channelPct;
        if (ch == null || out == null) return '${pct.round()}%';
        return '${OutputPipeline.toUs(profile.ch(ch), out[ch - 1])} µs';
    }
  }

  /// Input có luật có điều kiện hoặc đi vào nhiều kênh → chấm `accent`; nhấn giữ xem luật (U6)
  bool _mixed(String id) {
    final rs = profile.rulesUsing(id);
    return rs.length > 1 || rs.any((r) => !r.condition.isTrue);
  }

  void _showRules(ControlItem it) {
    final ids = it.inputIds;
    if (ids.isEmpty) return;
    final mixer = c.pipeline?.mixer;
    final inputs = profile.inputMap;
    final rules = {for (final id in ids) ...profile.rulesUsing(id)}.toList();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          title: Text(ids.map((i) => inputs[i]?.name ?? i).join(' · ')),
          content: SizedBox(
            width: 420,
            child: rules.isEmpty
                ? const Text('Input này chưa đi vào kênh nào.')
                : ListView(shrinkWrap: true, children: [
                    for (final r in rules)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.circle,
                            size: 10,
                            color: mixer?.isPending(r.id) == true
                                ? t.warn
                                : (mixer?.isActive(r.id) == true ? t.accent : t.disabled)),
                        title: Text(r.describe(inputs, chName: profile.chLabel)),
                        subtitle: Text(mixer?.isPending(r.id) == true
                            ? 'Chờ về giữa'
                            : (mixer?.isActive(r.id) == true ? 'Đang tác động' : 'Không tác động')),
                      ),
                  ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, ControlItem it) {
    final w = _buildControl(context, it);
    if (!it.kind.isControl || editing || !it.inputIds.any(_mixed)) return w;
    final t = context.tokens;
    return GestureDetector(
      onLongPress: () => _showRules(it),
      child: Stack(children: [
        Positioned.fill(child: w),
        Positioned(
          top: 4,
          right: 4,
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
        ),
      ]),
    );
  }

  Widget _buildControl(BuildContext context, ControlItem it) {
    final t = context.tokens;
    final label = _label(it);
    final lbl = label.isEmpty ? null : label;
    final id = it.inputId;
    if (it.kind.isControl && (id == null || profile.input(id) == null)) {
      return ItemFrame(
        label: it.kind.label,
        child: Center(child: Text('Chưa gắn Input', style: AppText.label.copyWith(color: t.textMuted))),
      );
    }
    switch (it.kind) {
      case ItemKind.stickH || ItemKind.stickV:
        return ItemFrame(
          label: lbl,
          trailing: _valueText(it, id!),
          child: StickAxis(
            value: c.position(id),
            vertical: it.kind == ItemKind.stickV,
            returnCfg: it.returnCfg,
            deadzonePct: it.style.deadzonePct,
            haptic: it.style.haptic,
            knobSize: it.style.knobSize,
            onChanged: (v) => c.setPosition(id, v),
          ),
        );
      case ItemKind.stick2D:
        final iy = it.inputIdY;
        final xs = _valueText(it, id!);
        final ys = iy == null ? null : _valueText(it, iy);
        return ItemFrame(
          label: lbl,
          trailing: xs == null ? null : 'X $xs${ys == null ? '' : ' · Y $ys'}',
          child: Stick2D(
            x: c.position(id),
            y: iy == null ? 0 : c.position(iy),
            returnX: it.returnCfg,
            returnY: it.returnCfgY,
            deadzonePct: it.style.deadzonePct,
            haptic: it.style.haptic,
            knobSize: it.style.knobSize,
            onChanged: (x, y) {
              c.setPosition(id, x, notify: false);
              if (iy != null) c.setPosition(iy, y, notify: false);
              c.refresh();
            },
          ),
        );
      case ItemKind.button || ItemKind.toggle:
        return ChannelButton(
          on: c.switchOf(id!) == 1,
          label: lbl,
          momentary: it.kind == ItemKind.button,
          icon: AppIcons.pickable[it.style.iconName],
          haptic: it.style.haptic,
          onChanged: (on) => c.setSwitch(id, on ? 1 : 0),
        );
      case ItemKind.switch3:
        final icon = AppIcons.pickable[it.style.iconName];
        return ItemFrame(
          label: lbl,
          child: Row(children: [
            if (icon != null) ...[AppIcon(icon, mini: true, color: t.textMuted), const SizedBox(width: Gap.xs)],
            Expanded(
              child: Switch3(
                position: c.switchPos[id!] ?? 1, // chưa đụng tới: nấc giữa (trạng thái nghỉ — I3)
                haptic: it.style.haptic,
                onChanged: (p) => c.setSwitch(id, p),
              ),
            ),
          ]),
        );
      case ItemKind.knob:
        return ItemFrame(
          label: lbl,
          trailing: _valueText(it, id!),
          child: Knob(
            value: c.position(id),
            haptic: it.style.haptic,
            onChanged: (v) => c.setPosition(id, ReturnMotion.deadzone(v, it.style.deadzonePct)),
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
    if (key == GaugeKey.channels) return _channelMonitor(label);
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
      GaugeKey.channels => (const SizedBox.shrink(), '', null),
    };
    return GaugeTile(label: label, value: value, sub: sub, icon: icon);
  }

  /// Ô "Kênh đầu ra": 10 thanh nhỏ hiện % của CH1–CH10 sau mixer (U6)
  Widget _channelMonitor(String label) {
    final t = context.tokens;
    final pct = c.channelPct;
    return ItemFrame(
      label: label.isEmpty ? null : label,
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 10; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(children: [
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    final v = pct == null ? 0.0 : pct[i] / 100;
                    final on = profile.channels[i].enabled;
                    final half = box.maxHeight / 2;
                    return Stack(children: [
                      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: t.surface2))),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: v >= 0 ? half - half * v : half,
                        height: (half * v.abs()).clamp(1.0, half),
                        child: ColoredBox(color: on ? t.accentFill : t.disabled),
                      ),
                    ]);
                  }),
                ),
                Text('${i + 1}', style: AppText.caption.copyWith(color: t.textMuted, fontSize: 9, letterSpacing: 0)),
              ]),
            ),
          ),
      ]),
    );
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
    final s = profile.steering;
    return ItemFrame(
      label: label,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xs),
      child: Row(
        children: [
          OutlinedButton(onPressed: s == null ? null : () => _trim(-5), child: const Text('◀')),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: s == null
                  ? Text('Chưa chọn kênh Lái', style: AppText.label.copyWith(color: t.textMuted))
                  : Text('Trim ${s.trimUs} µs', style: AppText.metric.copyWith(color: t.text)),
            ),
          ),
          OutlinedButton(onPressed: s == null ? null : () => _trim(5), child: const Text('▶')),
        ],
      ),
    );
  }
}

/// Nút ARM / DISARM (R1–R3): nhấn giữ 1 s để ARM (có vòng tiến trình), bấm một lần để DISARM
class _ArmButton extends StatefulWidget {
  const _ArmButton({required this.controller, required this.check, required this.onMessage});

  final CarController controller;
  final ArmCheck Function() check;
  final ValueChanged<String> onMessage;

  @override
  State<_ArmButton> createState() => _ArmButtonState();
}

class _ArmButtonState extends State<_ArmButton> with SingleTickerProviderStateMixin {
  static const holdTime = Duration(seconds: 1);
  late final _hold = AnimationController(vsync: this, duration: holdTime)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _arm();
    });

  ArmController get arm => widget.controller.arm;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _arm() {
    _hold.reset();
    final c = widget.controller;
    final chk = widget.check();
    final err = arm.arm(ArmCheck(
      profileValid: chk.profileValid,
      throttleAtRest: chk.throttleAtRest,
      editing: chk.editing,
      armConditionOk: c.armConditionOk,
    ));
    if (err != null) widget.onMessage(err);
    HapticFeedback.mediumImpact();
  }

  void _down() {
    if (arm.armed) return;
    final err = arm.canArm(widget.check());
    if (err != null) {
      widget.onMessage(err);
      return;
    }
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.isAnimating) _hold.reset();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: arm,
      builder: (context, _) {
        final armed = arm.armed;
        final ready = arm.state == ArmState.ready;
        final color = armed ? t.onAccentFill : (ready ? t.text : t.disabled);
        return GestureDetector(
          onTapDown: (_) => _down(),
          onTapUp: (_) => _up(),
          onTapCancel: _up,
          onTap: armed ? () => arm.disarm() : null,
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              decoration: BoxDecoration(
                color: armed ? t.accentFill : t.surface2,
                border: Border.all(color: armed ? t.accentFill : (ready ? t.accent : t.line)),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_hold.isAnimating)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(value: _hold.value, strokeWidth: 2.5, color: t.accent),
                  )
                else
                  AppIcon(armed ? AppIcons.unlocked : AppIcons.locked, mini: true, color: color),
                const SizedBox(width: Gap.xs),
                Text(armed ? 'ARMED' : (ready ? 'Giữ để ARM' : arm.state.label),
                    style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
