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
import '../l10n/lang.dart';
import '../layout/item_widgets.dart';
import '../layout/layout_canvas.dart';
import '../layout/layout_grid.dart';
import '../layout/layout_history.dart';
import '../layout/layout_templates.dart';
import '../layout/properties_panel.dart';
import '../layout/return_motion.dart';
import '../models/car_profile.dart';
import '../models/control_layout.dart';
import '../models/mixer_rule.dart';
import '../protocol/protocol.dart';
import '../services/arm_controller.dart';
import '../services/output_pipeline.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/hold_repeat.dart';
import '../widgets/status_badge.dart';
import 'settings_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({
    super.key,
    required this.controller,
    required this.repo,
    required this.profileId,
    this.editOnly = false,
  });

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;

  /// Mở từ Cấu hình ▸ Bố cục: vào thẳng chế độ Sửa bố cục (kể cả khi bố cục đang khoá),
  /// Lưu hoặc Huỷ thì đóng màn, không vào chế độ lái
  final bool editOnly;

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

  /// Trim nhấn giữ đổi liên tục: gom lại, ghi hồ sơ / gửi xe khi ngừng bấm
  Timer? _trimCommit;

  /// Màn Lái đang bị che (mở Cấu hình) hoặc app xuống nền: không ARM, kể cả khi tắt cơ chế ARM
  bool _away = false;

  CarController get c => widget.controller;
  ControlLayout get layout => editing ? draft! : profile.activeLayout;
  bool get _connectedHere => c.isConnected && c.connectedKey == profile.connKey;

  @override
  void initState() {
    super.initState();
    profile = widget.repo.get(widget.profileId)!;
    _enterDriveMode();
    _loadProfile();
    _initValues();
    c.armCheck = _armCheck;
    // App xuống nền → DISARM, cần gạt về vị trí an toàn (H3b, R3)
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _away = true;
        c.arm.disarm(tr('App xuống nền', 'App went to background'));
        _resetSticks();
        c.refresh();
      },
      onShow: () => _away = false,
    );
    if (widget.editOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_startEdit(force: true)) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (_trimCommit?.isActive ?? false) {
      _trimCommit!.cancel();
      _commitTrim();
    }
    _resetSticks(remember: true);
    c.unloadProfile();
    // Mở từ Cấu hình thì màn Cấu hình tự đặt lại hướng dọc khi quay về
    if (!widget.editOnly) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
        paused: _away,
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
    _away = true;
    c.arm.disarm(tr('Mở Cấu hình', 'Opened settings'));
    await _flushTrim(); // Cấu hình đọc hồ sơ đã lưu
    if (!mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(controller: c, repo: widget.repo, profileId: profile.id, initialTab: tab, fromDrive: true),
      ),
    );
    if (!mounted) return;
    _away = false;
    _enterDriveMode();
    setState(() {
      profile = widget.repo.get(widget.profileId)!;
      _loadProfile();
      _initValues();
    });
    // Cấu hình ▸ Bố cục ▸ Sửa bố cục: quay về đây và vào chế độ sửa
    if (result == SettingsScreen.editLayoutResult) _startEdit(force: true);
  }

  /// Trim nhanh cho kênh Lái đã chọn trong hồ sơ
  void _trim(int delta) {
    final s = profile.steering;
    if (s == null) return;
    final nv = (s.trimUs + delta).clamp(-200, 200).toInt();
    if (nv == s.trimUs) return;
    setState(() => s.trimUs = nv);
    _trimCommit?.cancel();
    _trimCommit = Timer(const Duration(milliseconds: 250), _commitTrim);
  }

  /// Ghi trim vào hồ sơ và gửi xuống xe (nếu đang nối đúng xe)
  Future<void> _commitTrim() async {
    _trimCommit = null;
    await widget.repo.save(profile);
    // n kênh: trim đã áp trong app ở chu kỳ gửi tiếp theo, không ghi xuống xe
    if (!_connectedHere || c.multiChannel) return;
    try {
      await c.applyConfig(profile.toCarConfig());
    } catch (e) {
      _snack(tr('Không gửi được trim: ${e.toString().replaceFirst('Exception: ', '')}',
          'Could not send trim: ${e.toString().replaceFirst('Exception: ', '')}'));
    }
  }

  /// Trim còn chờ ghi thì ghi ngay (trước khi mở Cấu hình / sửa bố cục)
  Future<void> _flushTrim() async {
    if (!(_trimCommit?.isActive ?? false)) return;
    _trimCommit!.cancel();
    await _commitTrim();
  }

  // ---------------- Sửa bố cục (H2, H5) ----------------
  /// Vào chế độ sửa; `force` bỏ qua khoá bố cục (mở từ Cấu hình). Trả về false nếu chưa vào được.
  bool _startEdit({bool force = false}) {
    if (profile.activeLayout.locked && !force) {
      _snack(tr('Bố cục đang khoá. Mở khoá trong menu trước.', 'The layout is locked. Unlock it in the menu first.'));
      return false;
    }
    // Ga phải đang ở vị trí nghỉ (vị trí về đã cài, vd −28%), không bắt buộc đúng 0% (H5-1)
    if (!(c.pipeline?.throttleAtRest(profile.activeLayout) ?? true)) {
      _snack(tr('Thả cần ga trước khi sửa bố cục', 'Release the throttle before editing the layout'));
      return false;
    }
    _flushTrim(); // trim còn chờ ghi không được ghi xen vào giữa lúc sửa
    _resetSticks();
    c.arm.disarm(tr('Đang sửa bố cục', 'Editing layout')); // chưa ARM → không gửi lệnh lái suốt thời gian sửa (H5, R3)
    setState(() {
      editing = true;
      draft = profile.activeLayout.copy();
      _profileSnapshot = jsonEncode(profile.toJson());
      history.clear();
      selectedId = null;
    });
    return true;
  }

  void _endEdit() {
    if (widget.editOnly) {
      Navigator.pop(context);
      return;
    }
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
          title: Text(tr('Cần ga không tự về ngay', 'Throttle does not return right away')),
          content: Text(tr('Xe có thể tiếp tục chạy sau khi thả tay. Vẫn lưu bố cục?',
              'The car may keep moving after you let go. Save the layout anyway?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn lưu', 'Save anyway'))),
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
      _snack(tr('Không lưu được: $e', 'Could not save: $e'));
      return;
    }
    _endEdit();
    _snack(tr('Đã lưu bố cục', 'Layout saved'));
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
    _snack(l.locked ? tr('Đã khoá bố cục', 'Layout locked') : tr('Đã mở khoá bố cục', 'Layout unlocked'));
  }

  Future<void> _openAddSheet() async {
    final d = draft!;
    final controls = ItemKind.controls;
    final gauges = GaugeKey.values.where((g) => !d.items.any((i) => i.gaugeKey == g.name)).toList();
    final extras = [ItemKind.trim, ItemKind.statusBadge]
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
            Text(tr('Thêm điều khiển', 'Add control'), style: AppText.title.copyWith(color: t.text)),
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
                title: Text(tr('Ô ${g.label}', '${g.label} gauge')),
                onTap: () => Navigator.pop(ctx, g),
              ),
            for (final k in extras)
              ListTile(
                leading: const AppIcon(AppIcons.addControl),
                title: Text(k.label),
                onTap: () => Navigator.pop(ctx, k),
              ),
            const SizedBox(height: Gap.s),
            Text(tr('Thêm xong, chọn phần tử để gắn Input, chọn kênh và chỉnh cấu hình riêng của nó.', 'Once added, select the control to bind an Input, pick a channel and adjust its own settings.'),
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
    if (added == null) _snack(tr('Không còn chỗ trống đủ lớn trên màn', 'No free space large enough on screen'));
  }

  static String _kindHint(ItemKind k) => switch (k) {
        ItemKind.stickH || ItemKind.stickV => tr('−100…+100%, tự về khi thả (chỉnh được)', '−100…+100%, springs back when released (adjustable)'),
        ItemKind.stick2D => tr('Hai Input X/Y', 'Two Inputs X/Y'),
        ItemKind.button => tr('Bật khi giữ, thả ra là tắt', 'On while held, off when released'),
        ItemKind.toggle => tr('Mỗi lần bấm đổi trạng thái', 'Each press toggles the state'),
        ItemKind.switch3 => tr('Trái / giữa / phải', 'Left / center / right'),
        ItemKind.knob => tr('Giữ nguyên vị trí', 'Stays where you leave it'),
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
                        SizedBox(height: 48, child: editing ? _editBar() : (widget.editOnly ? null : _driveBar())),
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
                      onOpenMix: () => _snack(tr('Lưu bố cục, rồi mở Cấu hình ▸ Mix để sửa luật của Input này', 'Save the layout, then open Car settings ▸ Mix to edit the rules of this Input')),
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
    final width = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        IconButton(icon: const AppIcon(AppIcons.back), onPressed: () => Navigator.pop(context)),
        // Không dùng Flexible cho tên: phần chỗ Flexible được chia mà tên ngắn không dùng hết sẽ bị bỏ trống
        // ở cuối hàng, đẩy nút Sửa / ⚙ khỏi góc phải. Ô cảnh báo (Expanded) bên dưới chiếm hết phần còn lại.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.22),
          child: Text(profile.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title.copyWith(color: t.text)),
        ),
        const SizedBox(width: Gap.s),
        _ArmButton(controller: c, onMessage: _snack),
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
                            ? tr('Chưa kết nối xe', 'Car not connected')
                            : (tel?.netSetup ?? false)
                                ? tr('Xe đang ở chế độ cấu hình mạng: không lái được', 'The car is in network setup mode: driving is disabled')
                                : tr('Failsafe: xe đang ở chế độ an toàn', 'Failsafe: the car is in safe mode'),
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(color: t.bad, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: Gap.s),
        // Sửa bố cục: nút riêng ở góc phải, cạnh menu ⚙
        Tooltip(
          message: l.locked
              ? tr('Bố cục đang khoá: mở khoá trong menu ⚙', 'Layout is locked: unlock it in the ⚙ menu')
              : tr('Sửa bố cục', 'Edit layout'),
          child: width < 600
              ? IconButton(
                  onPressed: l.locked ? null : () => _startEdit(),
                  icon: AppIcon(l.locked ? AppIcons.locked : AppIcons.edit),
                )
              : TextButton.icon(
                  onPressed: l.locked ? null : () => _startEdit(),
                  icon: AppIcon(l.locked ? AppIcons.locked : AppIcons.edit, mini: true),
                  label: Text(tr('Sửa', 'Edit')),
                ),
        ),
        PopupMenuButton<String>(
          tooltip: tr('Tuỳ chọn', 'Options'),
          icon: const AppIcon(AppIcons.config),
          onSelected: (v) {
            switch (v) {
              case 'settings':
                _openSettings();
              case 'mix':
                _openSettings(tab: SettingsScreen.mixTab);
              case 'lock':
                _toggleLock();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'settings',
              child: ListTile(leading: const AppIcon(AppIcons.settings), title: Text(tr('Cấu hình', 'Car settings'))),
            ),
            PopupMenuItem(
              value: 'mix',
              child: ListTile(leading: const AppIcon(AppIcons.mix), title: Text(tr('Luật mix', 'Mix rules'))),
            ),
            PopupMenuItem(
              value: 'lock',
              child: ListTile(
                leading: AppIcon(l.locked ? AppIcons.locked : AppIcons.unlocked),
                title: Text(l.locked ? tr('Mở khoá bố cục', 'Unlock layout') : tr('Khoá bố cục', 'Lock layout')),
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
          label: Text(tr('Huỷ', 'Cancel')),
        ),
        IconButton(
          tooltip: tr('Hoàn tác', 'Undo'),
          onPressed: history.canUndo ? _undo : null,
          icon: const AppIcon(AppIcons.undo),
        ),
        IconButton(
          tooltip: tr('Làm lại', 'Redo'),
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
                // Màn hẹp / chữ tiếng Anh dài: cắt bớt thay vì tràn thanh công cụ
                Flexible(
                  child: Text(
                    _dragging
                        ? tr('Thả vào đây để xoá', 'Drop here to delete')
                        : tr('Sửa bố cục · kéo để di chuyển', 'Edit layout · drag to move'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: _dragging ? t.bad : t.textMuted),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: Gap.s),
        OutlinedButton.icon(
          onPressed: _openAddSheet,
          icon: const AppIcon(AppIcons.plus, mini: true),
          label: Text(tr('Thêm', 'Add')),
        ),
        const SizedBox(width: Gap.s),
        FilledButton.icon(
          onPressed: _saveEdit,
          icon: const AppIcon(AppIcons.save, mini: true),
          label: Text(tr('Lưu', 'Save')),
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

  /// Input có luật có điều kiện hoặc đi vào nhiều kênh → chấm `accent`; nhấn giữ xem luật (U6).
  /// Chỉ khi DISARM: đang lái mà giữ yên cần nửa giây thì bảng không được bật lên che màn Lái.
  bool _mixed(String id) {
    final rs = profile.rulesUsing(id);
    return rs.length > 1 || rs.any((r) => !r.condition.isTrue);
  }

  void _showRules(ControlItem it) {
    final ids = it.inputIds;
    if (ids.isEmpty || c.arm.armed) return;
    final inputs = profile.inputMap;
    showDialog<void>(
      context: context,
      builder: (_) => _RulesDialog(
        controller: c,
        title: ids.map((i) => inputs[i]?.name ?? i).join(' · '),
        rules: {for (final id in ids) ...profile.rulesUsing(id)}.toList(),
        describe: (r) => r.describe(inputs, chName: profile.chLabel),
      ),
    );
  }

  Widget _buildItem(BuildContext context, ControlItem it) {
    final w = _buildControl(context, it);
    if (!it.kind.isControl || editing || !it.inputIds.any(_mixed)) return w;
    final t = context.tokens;
    return GestureDetector(
      onLongPress: c.arm.armed ? null : () => _showRules(it),
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
        child: Center(child: Text(tr('Chưa gắn Input', 'No Input bound'), style: AppText.label.copyWith(color: t.textMuted))),
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

  Widget _trimBox(String? label) {
    final t = context.tokens;
    final s = profile.steering;
    final canLeft = s != null && s.trimUs > -200, canRight = s != null && s.trimUs < 200;
    return ItemFrame(
      label: label,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xs),
      child: Row(
        children: [
          HoldRepeat(
            onStep: canLeft ? (_) => _trim(-5) : null,
            child: OutlinedButton(onPressed: canLeft ? () => _trim(-5) : null, child: const Text('◀')),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: s == null
                  ? Text(tr('Chưa chọn kênh Lái', 'No steering channel'), style: AppText.label.copyWith(color: t.textMuted))
                  : Text('Trim ${s.trimUs} µs', style: AppText.metric.copyWith(color: t.text)),
            ),
          ),
          HoldRepeat(
            onStep: canRight ? (_) => _trim(5) : null,
            child: OutlinedButton(onPressed: canRight ? () => _trim(5) : null, child: const Text('▶')),
          ),
        ],
      ),
    );
  }
}

/// Các luật dùng Input của một phần tử (U6). Mixer chạy trong vòng gửi và không báo giao diện,
/// nên trạng thái được đọc lại mỗi 100 ms: thả tay khỏi cần là dòng trạng thái đổi theo.
class _RulesDialog extends StatefulWidget {
  const _RulesDialog({required this.controller, required this.title, required this.rules, required this.describe});

  final CarController controller;
  final String title;
  final List<MixRule> rules;
  final String Function(MixRule r) describe;

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Luật không điều kiện luôn tác động — không nói gì về việc cần có đang được gạt hay không
  (Color, String) _status(MixRule r, AppTokens t) {
    final mixer = widget.controller.pipeline?.mixer;
    if (!r.enabled) return (t.disabled, tr('Luật đang tắt', 'Rule is off'));
    if (r.condition.isTrue) return (t.accent, tr('Luôn áp dụng', 'Always applied'));
    if (mixer?.isPending(r.id) == true) return (t.warn, tr('Chờ về giữa', 'Waiting for center'));
    if (mixer?.isActive(r.id) == true) return (t.accent, tr('Điều kiện đúng · đang tác động', 'Condition met · active'));
    return (t.disabled, tr('Điều kiện chưa đúng', 'Condition not met'));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: widget.rules.isEmpty
            ? Text(tr('Input này chưa đi vào kênh nào.', 'This Input does not drive any channel yet.'))
            : ListView(shrinkWrap: true, children: [
                for (final r in widget.rules)
                  if (_status(r, t) case (final color, final label))
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 10, color: color),
                      title: Text(widget.describe(r)),
                      subtitle: Text(label),
                    ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng', 'Close')))],
    );
  }
}

/// Nút ARM / DISARM (R1–R3): nhấn giữ 1 s để ARM (có vòng tiến trình), bấm một lần để DISARM.
/// Hồ sơ tắt cơ chế ARM thì chỉ là ô trạng thái: "Đang lái" hoặc lý do chưa lái được.
class _ArmButton extends StatefulWidget {
  const _ArmButton({required this.controller, required this.onMessage});

  final CarController controller;
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

  ArmCheck get _check => widget.controller.currentArmCheck() ?? const ArmCheck();

  void _arm() {
    _hold.reset();
    final err = arm.arm(_check);
    if (err != null) widget.onMessage(err);
    HapticFeedback.mediumImpact();
  }

  void _down() {
    if (arm.armed) return;
    final err = arm.canArm(_check);
    if (err != null) {
      widget.onMessage(err);
      return;
    }
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.isAnimating) _hold.reset();
  }

  /// Không dùng ARM: ô trạng thái, bấm vào (khi chưa lái được) thì báo lý do
  Widget _status(BuildContext context) {
    final t = context.tokens;
    final armed = arm.armed;
    final text = armed ? tr('Đang lái', 'Live') : (arm.canArm(_check) ?? arm.state.label);
    final color = armed ? t.onAccentFill : t.textMuted;
    return GestureDetector(
      onTap: armed ? null : () => widget.onMessage(text),
      child: Container(
        height: 36,
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.3),
        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
        decoration: BoxDecoration(
          color: armed ? t.accentFill : t.surface2,
          border: Border.all(color: armed ? t.accentFill : t.line),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CustomIconView(CustomIcon.steering, size: 16, color: color),
          const SizedBox(width: Gap.xs),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: arm,
      builder: (context, _) {
        if (!arm.enabled) return _status(context);
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
                Text(armed ? 'ARMED' : (ready ? tr('Giữ để ARM', 'Hold to ARM') : arm.state.label),
                    style: AppText.label.copyWith(color: color, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
