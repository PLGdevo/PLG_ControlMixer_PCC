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
import '../models/channel_config.dart';
import '../models/control_layout.dart';
import '../models/data_source.dart';
import '../models/mixer_rule.dart';
import '../services/arm_controller.dart';
import '../services/car_connector.dart';
import '../services/output_pipeline.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/hold_repeat.dart';
import '../widgets/status_badge.dart';
import '../widgets/status_strip.dart';
import 'settings_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({
    super.key,
    required this.controller,
    required this.repo,
    required this.profileId,
    this.editOnly = false,
    this.connectOnOpen = false,
  });

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;

  /// Mở từ Cấu hình ▸ Bố cục: vào thẳng chế độ Sửa bố cục (kể cả khi bố cục đang khoá),
  /// Lưu hoặc Huỷ thì đóng màn, không vào chế độ lái
  final bool editOnly;

  /// Mở từ thẻ xe: chưa nối xe này thì tự kết nối (nối không được vẫn ở lại màn Lái, có nút Kết nối)
  final bool connectOnOpen;

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

  /// Phần tử đang mở bảng thuộc tính (chạm hai lần); chạm một lần chỉ chọn để kéo / đổi cỡ
  String? _panelId;
  bool _dragging = false, _overTrash = false;
  final _trashKey = GlobalKey();

  /// Trim nhấn giữ đổi liên tục: gom lại, ghi hồ sơ / gửi xe khi ngừng bấm
  Timer? _trimCommit;

  /// Bảng trim từng kênh đang mở (bấm giữa ô Trim). Không chặn màn Lái: cần gạt vẫn dùng được
  bool _trimOpen = false;

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
    } else if (widget.connectOnOpen && !_connectedHere && c.connectingKey == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect();
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

  // ---------------- Kết nối ----------------
  /// Nối xe của hồ sơ này; lỗi / cảnh báo hiện ở thanh dưới, vẫn ở lại màn Lái
  Future<void> _connect() async {
    final msgs = await CarConnector.connect(c, widget.repo, profile.id);
    if (!mounted) return;
    // Dò xe (Router) có thể đã đổi IP trong hồ sơ đã lưu: lấy lại để khớp khoá kết nối
    final fresh = widget.repo.get(profile.id);
    if (fresh != null) {
      setState(() {
        profile
          ..wifi = fresh.wifi
          ..lastConnectedAt = fresh.lastConnectedAt;
      });
    }
    if (msgs.isNotEmpty) _snack(msgs.join(' · '));
  }

  /// Chọn giá trị hiện trên tai thỏ. Không mở khi đang ARM (không che màn Lái).
  Future<void> _editStatusItems() async {
    if (c.arm.armed) return;
    final r = await pickStatusItems(context, profile);
    if (r == null || !mounted) return;
    setState(() => profile.statusItems = r);
    await widget.repo.save(profile, touch: false);
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
      final y = it.inputIdY;
      if (it.kind == ItemKind.stick2D && y != null) {
        c.setPosition(y, ReturnMotion.initial(it.returnCfgY ?? ReturnConfig(), it.savedPctY), notify: false);
      }
      final id = it.inputId;
      if (id == null) continue;
      switch (it.kind) {
        case ItemKind.stickH || ItemKind.stickV || ItemKind.stick2D:
          c.setPosition(id, ReturnMotion.initial(it.returnCfg ?? ReturnConfig(), it.savedPct), notify: false);
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
    _trimOpen = false;
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
    final ch = profile.steeringCh;
    if (ch != null) _trimCh(ch, delta);
  }

  /// Trim kênh `ch` thêm `delta` µs; `set` = đặt thẳng giá trị (vd về 0)
  void _trimCh(int ch, int delta, {bool set = false}) {
    final s = profile.ch(ch);
    final nv = ((set ? 0 : s.trimUs) + delta).clamp(-200, 200).toInt();
    if (nv == s.trimUs) return;
    // Vòng gửi phải đọc đúng bản hồ sơ đang trim (sau nối lại / mở Cấu hình có thể đang giữ bản khác)
    final pl = c.pipeline;
    if (pl != null && !identical(pl.profile, profile)) c.loadProfile(profile);
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
      _trimOpen = false;
      draft = profile.activeLayout.copy();
      _profileSnapshot = jsonEncode(profile.toJson());
      history.clear();
      selectedId = null;
      _panelId = null;
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
      _panelId = null;
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
    setState(() {
      if (selectedId == id) selectedId = null;
      if (_panelId == id) _panelId = null;
    });
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
    const displays = [ItemKind.gauge, ItemKind.led, ItemKind.bar, ItemKind.vector, ItemKind.channels];
    // Thanh trim thêm được nhiều (mỗi thanh một kênh); Trim lái và Trạng thái chỉ một
    final extras = [
      ItemKind.trimBar,
      ...[ItemKind.trim, ItemKind.statusBadge].where((k) => !d.items.any((i) => i.kind == k)),
    ];
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
            const Divider(),
            Text(tr('Hiển thị', 'Display'), style: AppText.title.copyWith(color: t.text)),
            for (final k in displays)
              ListTile(
                leading: k == ItemKind.gauge ? const CustomIconView(CustomIcon.speedometer) : AppIcon(_displayIcon(k)),
                title: Text(k.label),
                subtitle: Text(_kindHint(k)),
                onTap: () => Navigator.pop(ctx, k),
              ),
            if (extras.isNotEmpty) const Divider(),
            for (final k in extras)
              ListTile(
                leading: const AppIcon(AppIcons.addControl),
                title: Text(k.label),
                subtitle: _kindHint(k).isEmpty ? null : Text(_kindHint(k)),
                onTap: () => Navigator.pop(ctx, k),
              ),
            const SizedBox(height: Gap.s),
            Text(
                tr('Thêm xong, nhấn đúp vào phần tử để gắn Input, chọn kênh và chỉnh cấu hình riêng của nó.',
                    'Once added, double-tap the control to bind an Input, pick a channel and adjust its own settings.'),
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
        ItemKind k when k.isControl => LayoutTemplates.addControl(d, k),
        ItemKind k when k.isDisplay => LayoutTemplates.addWidget(d, k,
            source: _defaultSource(d, k), sourceY: k == ItemKind.vector ? _defaultSource(d, k, y: true) : null),
        ItemKind k => LayoutTemplates.addWidget(d, k),
        _ => null,
      };
      final a = added;
      if (a != null && a.kind == ItemKind.trimBar) a.trimCh = _nextTrimCh(d);
      if (added != null) selectedId = _panelId = added!.id; // phần tử mới mở luôn bảng để gắn Input
    });
    if (added == null) _snack(tr('Không còn chỗ trống đủ lớn trên màn', 'No free space large enough on screen'));
  }

  /// Kênh cho thanh trim mới: kênh Lái nếu chưa có thanh nào, rồi tới kênh đang bật chưa có thanh trim
  int? _nextTrimCh(ControlLayout d) {
    final used = d.items.where((i) => i.kind == ItemKind.trimBar && i.trimCh != null).map((i) => i.trimCh!).toSet();
    final steer = profile.steeringCh;
    if (steer != null && !used.contains(steer)) return steer;
    for (final ch in profile.channels) {
      if (ch.enabled && !used.contains(ch.index)) return ch.index;
    }
    return steer ?? 1;
  }

  static HeroIcons _displayIcon(ItemKind k) => switch (k) {
        ItemKind.led => AppIcons.light,
        ItemKind.bar => AppIcons.diagnostics,
        _ => AppIcons.vector,
      };

  /// Nguồn giá trị mặc định khi thêm phần tử hiển thị: ô đồng hồ lấy số đo xe chưa có trên màn,
  /// thanh lấy kênh Ga, vector lấy Lái (X) / Ga (Y), LED lấy trạng thái ARM
  String _defaultSource(ControlLayout d, ItemKind k, {bool y = false}) {
    final thr = profile.throttleCh, steer = profile.steeringCh;
    return switch (k) {
      ItemKind.gauge => DataSource.carKeys.firstWhere(
          (key) => !d.items.any((i) => i.kind == ItemKind.gauge && i.source == key),
          orElse: () => DataSource.battery),
      ItemKind.bar => thr == null ? DataSource.battery : DataSource.ch(thr),
      ItemKind.vector => y ? DataSource.ch(thr ?? 2) : DataSource.ch(steer ?? 1),
      _ => DataSource.arm,
    };
  }

  static String _kindHint(ItemKind k) => switch (k) {
        ItemKind.stickH ||
        ItemKind.stickV =>
          tr('−100…+100%, tự về khi thả (chỉnh được)', '−100…+100%, springs back when released (adjustable)'),
        ItemKind.stick2D => tr('Như cần tay RC: dùng 1 trục (1 kênh) hoặc 2 trục (2 kênh)',
            'Like a transmitter stick: 1 axis (1 channel) or 2 axes (2 channels)'),
        ItemKind.button => tr('Bật khi giữ, thả ra là tắt', 'On while held, off when released'),
        ItemKind.toggle => tr('Mỗi lần bấm đổi trạng thái', 'Each press toggles the state'),
        ItemKind.switch3 => tr('Trái / giữa / phải', 'Left / center / right'),
        ItemKind.knob => tr('Giữ nguyên vị trí', 'Stays where you leave it'),
        ItemKind.gauge => tr('Hiện số: pin, tốc độ, kênh, Input…', 'Shows a number: battery, speed, channel, Input…'),
        ItemKind.led => tr('Sáng theo trạng thái hoặc khi vượt ngưỡng', 'Lights up on a state or past a threshold'),
        ItemKind.bar => tr('Thanh ngang/dọc theo một giá trị', 'Horizontal/vertical bar for one value'),
        ItemKind.vector =>
          tr('Chấm X/Y từ hai giá trị, vd Lái / Ga', 'X/Y dot from two values, e.g. steering / throttle'),
        ItemKind.channels => tr('Thanh giá trị của các kênh bạn chọn, gọn trong một ô',
            'Value bars for the channels you pick, in one compact box'),
        ItemKind.trimBar => tr('Trim một kênh bạn chọn, thêm được nhiều thanh',
            'Trims one channel of your choice; add as many as you like'),
        ItemKind.trim => tr('Ô trim kênh Lái (kiểu cũ)', 'Steering trim box (classic)'),
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
    final selected = editing ? draft!.items.where((i) => i.id == _panelId).firstOrNull : null;
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
            final row = Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: insets,
                    child: Column(
                      children: [
                        SizedBox(height: 48, child: editing ? _editBar() : (widget.editOnly ? null : _driveBar())),
                        const SizedBox(height: Gap.xs),
                        Expanded(
                          child: Stack(clipBehavior: Clip.none, children: [
                            Positioned.fill(
                              child: LayoutCanvas(
                                layout: layout,
                                editing: editing,
                                selectedId: selectedId,
                                itemBuilder: _buildItem,
                                onSelect: (id) => setState(() {
                                  selectedId = id;
                                  if (_panelId != id) _panelId = null; // chọn phần tử khác: bảng cũ đóng
                                }),
                                onOpen: (id) => setState(() => selectedId = _panelId = id),
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
                            // Nhấn giữ kéo phần tử: thùng rác hiện ở giữa đáy lưới, thả vào là xoá ngay
                            if (editing && _dragging)
                              Positioned(left: 0, right: 0, bottom: Gap.m, child: Center(child: _trashBin())),
                          ]),
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
                      onClose: () => setState(() => _panelId = null),
                      onMessage: _snack,
                      onOpenMix: () => _snack(tr('Lưu bố cục, rồi mở Cấu hình ▸ Mix để sửa luật của Input này',
                          'Save the layout, then open Car settings ▸ Mix to edit the rules of this Input')),
                    ),
                  ),
              ],
            );
            if (!_trimOpen || editing) return row;
            // Bảng trim nổi ở góc phải dưới thanh trên, không chặn cần gạt bên dưới
            final top = insets.top + 48 + Gap.s;
            return Stack(children: [
              row,
              Positioned(
                top: top,
                right: insets.right,
                width: min(320, mq.size.width * 0.5),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: max(120, mq.size.height - top - insets.bottom)),
                  child: _TrimPanel(
                    profile: profile,
                    onTrim: _trimCh,
                    onClose: () => setState(() => _trimOpen = false),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _driveBar() {
    final t = context.tokens;
    final tel = _connectedHere ? c.telemetry : null;
    final here = _connectedHere;
    final String? alarm = !here
        ? tr('Chưa kết nối xe', 'Car not connected')
        : c.state == LinkState.lost
            ? tr('Mất tín hiệu', 'Signal lost')
            : (tel?.netSetup ?? false)
                ? tr('Xe ở chế độ cấu hình mạng', 'Car in network setup mode')
                : (tel?.failsafe ?? false)
                    ? tr('Failsafe', 'Failsafe')
                    : c.weakLink
                        ? tr('Tín hiệu yếu', 'Weak signal')
                        : null;
    final l = profile.activeLayout;
    final width = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        IconButton(icon: const AppIcon(AppIcons.back), onPressed: () => Navigator.pop(context)),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.18),
          child: Text(profile.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title.copyWith(color: t.text)),
        ),
        const SizedBox(width: Gap.s),
        _ArmButton(controller: c, onMessage: _snack),
        // Tai thỏ: giá trị người dùng chọn + cảnh báo kết nối; bấm để chọn giá trị (khi chưa ARM)
        Expanded(
          child: Center(
            child: StatusNotch(
              controller: c,
              profile: profile,
              alarm: alarm,
              onTap: c.arm.armed ? null : _editStatusItems,
            ),
          ),
        ),
        const SizedBox(width: Gap.s),
        LinkButton(controller: c, connKey: profile.connKey, onConnect: _connect, compact: width < 760),
        const SizedBox(width: Gap.s),
        // Sửa bố cục: chỉ hiện khi đã mở khoá (mở khoá trong menu ⚙)
        if (!l.locked)
          Tooltip(
            message: tr('Sửa bố cục', 'Edit layout'),
            child: width < 600
                ? IconButton(onPressed: () => _startEdit(), icon: const AppIcon(AppIcons.edit))
                : TextButton.icon(
                    onPressed: () => _startEdit(),
                    icon: const AppIcon(AppIcons.edit, mini: true),
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

  /// Thùng rác nổi khi đang kéo phần tử; phóng to và tô đỏ khi phần tử ở trên
  Widget _trashBin() {
    final t = context.tokens;
    return IgnorePointer(
      child: AnimatedScale(
        scale: _overTrash ? 1.25 : 1,
        duration: const Duration(milliseconds: 120),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            key: _trashKey,
            duration: const Duration(milliseconds: 120),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _overTrash ? t.bad : t.surface.withValues(alpha: 0.92),
              border: Border.all(color: t.bad, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Center(
              child: AppIcon(AppIcons.delete, size: 30, color: _overTrash ? Colors.white : t.bad, solid: _overTrash),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            _overTrash ? tr('Thả để xoá', 'Release to delete') : tr('Xoá', 'Delete'),
            style: AppText.label.copyWith(color: t.bad, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Gap.l, vertical: Gap.xs),
              decoration: BoxDecoration(
                border: Border.all(color: _dragging ? t.bad : t.line),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              // Màn hẹp / chữ tiếng Anh dài: cắt bớt thay vì tràn thanh công cụ
              child: Text(
                _dragging
                    ? tr('Kéo vào thùng rác để xoá', 'Drag onto the bin to delete')
                    : tr('Sửa bố cục · kéo để di chuyển · nhấn đúp để cấu hình',
                        'Edit layout · drag to move · double-tap to configure'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: _dragging ? t.bad : t.textMuted),
              ),
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
    if (it.kind.isDisplay) return DataSource.labelOf(it, profile);
    if (it.kind == ItemKind.trimBar) {
      final ch = it.trimCh;
      return ch == null ? it.kind.label : profile.chLabel(ch);
    }
    return profile.input(it.inputId ?? it.inputIdY)?.name ?? it.kind.label;
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
    // Cần 2 trục: chỉ cần trục đang dùng có Input
    final unbound = it.kind == ItemKind.stick2D
        ? ![if (it.axes.hasX) it.inputId, if (it.axes.hasY) it.inputIdY].any((i) => profile.input(i) != null)
        : it.kind.isControl && (id == null || profile.input(id) == null);
    if (unbound) {
      return ItemFrame(
        label: it.kind.label,
        child: Center(
            child: Text(tr('Chưa gắn Input', 'No Input bound'), style: AppText.label.copyWith(color: t.textMuted))),
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
        final ix = it.axes.hasX && profile.input(it.inputId) != null ? it.inputId : null;
        final iy = it.axes.hasY && profile.input(it.inputIdY) != null ? it.inputIdY : null;
        final xs = ix == null ? null : _valueText(it, ix);
        final ys = iy == null ? null : _valueText(it, iy);
        final both = ix != null && iy != null;
        return ItemFrame(
          label: lbl,
          trailing: xs == null && ys == null ? null : (both ? '↔ $xs · ↕ $ys' : (xs ?? ys)),
          child: Stick2D(
            x: ix == null ? 0 : c.position(ix),
            y: iy == null ? 0 : c.position(iy),
            returnX: it.returnCfg,
            returnY: it.returnCfgY,
            deadzonePct: it.style.deadzonePct,
            haptic: it.style.haptic,
            knobSize: it.style.knobSize,
            axes: it.axes,
            gimbal: it.style.gimbal,
            onChanged: (x, y) {
              if (ix != null) c.setPosition(ix, x, notify: false);
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
        return _gauge(it, lbl);
      case ItemKind.led:
        return LedLamp(on: _ledOn(it), label: lbl, blink: it.display.blink);
      case ItemKind.bar:
        final info = DataSource.info(it.source, profile);
        final v = _read(it.source);
        final lo = it.display.min ?? info?.min ?? -100, hi = it.display.max ?? info?.max ?? 100;
        return ItemFrame(
          label: lbl,
          trailing: it.style.valueDisplay == ValueDisplay.hidden ? null : _fmt(it, it.source, v),
          padding: const EdgeInsets.fromLTRB(Gap.s, Gap.xs, Gap.s, Gap.xs),
          child: ValueBar(value: v, min: lo, max: hi > lo ? hi : lo + 1),
        );
      case ItemKind.vector:
        final vx = _read(it.source), vy = _read(it.sourceY);
        final show = it.style.valueDisplay != ValueDisplay.hidden;
        return ItemFrame(
          label: lbl,
          trailing: show ? '${_fmt(it, it.source, vx)} · ${_fmt(it, it.sourceY, vy)}' : null,
          padding: const EdgeInsets.all(Gap.xs),
          child: VectorPad(x: _norm(it.source, vx), y: _norm(it.sourceY, vy), trail: it.display.trail),
        );
      case ItemKind.trim:
        return _trimBox(lbl);
      case ItemKind.trimBar:
        final ch = it.trimCh;
        final s = ch == null || ch > profile.channels.length ? null : profile.ch(ch);
        final small = it.style.valueDisplay == ValueDisplay.hidden;
        return ItemFrame(
          label: lbl,
          trailing: s == null || small ? null : '${s.trimUs > 0 ? '+' : ''}${s.trimUs} µs',
          padding: const EdgeInsets.all(Gap.xs),
          child: TrimBar(
            value: s?.trimUs ?? 0,
            onStep: s == null ? null : (dv) => _trimCh(ch!, dv),
            onTapTrack: () => setState(() => _trimOpen = !_trimOpen),
          ),
        );
      case ItemKind.channels:
        return ItemFrame(
          label: lbl,
          padding: const EdgeInsets.fromLTRB(Gap.s, Gap.xs, Gap.s, Gap.xs),
          child: ChannelMonitor(rows: _channelRows(it)),
        );
      case ItemKind.statusBadge:
        return Center(child: FittedBox(child: StatusBadge(state: c.state)));
    }
  }

  double? _read(String? key) => readSource(c, profile, key);

  /// Dòng của bảng kênh: kênh đã chọn (mặc định mọi kênh đang bật), % sau mixer và số µs / %
  List<ChannelRow> _channelRows(ControlItem it) {
    final out = c.channelPct;
    final n = profile.channels.length;
    final list = (it.chList ??
            [
              for (final ch in profile.channels)
                if (ch.enabled) ch.index
            ])
        .where((i) => i >= 1 && i <= n);
    return [
      for (final i in list)
        () {
          final ch = profile.ch(i);
          final pct = out == null || i > out.length ? 0.0 : out[i - 1];
          final name = ch.hasDefaultName ? 'CH$i' : '$i ${ch.name}';
          return ChannelRow(
            name: name,
            pct: pct,
            on: ch.enabled,
            value: switch (it.style.valueDisplay) {
              ValueDisplay.hidden => null,
              ValueDisplay.us => '${OutputPipeline.toUs(ch, pct)}',
              ValueDisplay.pct => '${pct.round()}%',
            },
          );
        }(),
    ];
  }

  /// Chữ hiện giá trị của nguồn; kênh ra hiện µs nếu phần tử chọn µs
  String _fmt(ControlItem it, String? key, double? v) {
    final info = DataSource.info(key, profile);
    if (info == null || v == null) return '--';
    final n = DataSource.chOf(key);
    if (n != null && it.style.valueDisplay == ValueDisplay.us) return '${OutputPipeline.toUs(profile.ch(n), v)} µs';
    return info.format(v);
  }

  /// Giá trị về −1…+1 theo khoảng mặc định của nguồn (trục vector)
  double? _norm(String? key, double? v) {
    final info = DataSource.info(key, profile);
    if (info == null || v == null || info.max <= info.min) return null;
    return (v - info.min) / (info.max - info.min) * 2 - 1;
  }

  /// Trạng thái đèn LED lần trước, để có trễ quanh ngưỡng (pin sụt áp khi tăng ga không làm đèn nháy loạn)
  final Map<String, bool> _ledLast = {};

  bool? _ledOn(ControlItem it) {
    final info = DataSource.info(it.source, profile);
    final v = _read(it.source);
    if (info == null || v == null) return null;
    if (info.flag) return v >= 0.5;
    final th = it.display.threshold ?? info.alarm;
    final below = it.display.below ?? info.alarmBelow;
    final hyst = (info.max - info.min).abs() * 0.02;
    final was = _ledLast[it.id] ?? false;
    final on = below ? v < (was ? th + hyst : th) : v > (was ? th - hyst : th);
    _ledLast[it.id] = on;
    return on;
  }

  Widget _gauge(ControlItem it, String? label) {
    if (it.source == DataSource.channels) return _channelMonitor(label ?? '');
    final key = it.source;
    final tel = c.telemetry;
    final Widget? icon = switch (key) {
      DataSource.battery => AppIcon(tel == null ? AppIcons.batteryEmpty : AppIcons.batteryHalf),
      DataSource.current => const AppIcon(AppIcons.current),
      DataSource.speed => const CustomIconView(CustomIcon.speedometer),
      DataSource.ping ||
      DataSource.lq ||
      DataSource.rssi =>
        AppIcon(_read(key) == null ? AppIcons.signalOff : AppIcons.signal),
      _ => null,
    };
    // Ô Ping: dòng phụ hiện LQ như màn hình tay RC
    final lq = _read(DataSource.lq);
    final sub = key == DataSource.ping && lq != null ? 'LQ ${lq.round()}%' : null;
    return GaugeTile(label: label ?? '', value: _fmt(it, key, _read(key)), sub: sub, icon: icon);
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
                        height: (half * v.abs()).clamp(min(1.0, half), max(half, 0.0)),
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
          // Bấm giữa: bảng trim từng kênh đang bật
          Expanded(
            child: Tooltip(
              message: tr('Bấm để trim từng kênh', 'Tap to trim each channel'),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.card),
                onTap: () => setState(() => _trimOpen = !_trimOpen),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: s == null
                        ? Text(tr('Chưa chọn kênh Lái', 'No steering channel'),
                            style: AppText.label.copyWith(color: t.textMuted))
                        : Text('Trim ${s.trimUs} µs', style: AppText.metric.copyWith(color: t.text)),
                  ),
                ),
              ),
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

/// Bảng trim từng kênh đang bật (mở bằng cách bấm giữa ô Trim): ◀ ▶ đổi 5 µs, giữ để đổi liên tục,
/// bấm số µs để về 0. Nổi trên màn Lái, không chặn cần gạt (chỉ mở khi người dùng chủ động bấm).
class _TrimPanel extends StatelessWidget {
  const _TrimPanel({required this.profile, required this.onTrim, required this.onClose});

  final CarProfile profile;
  final void Function(int ch, int delta, {bool set}) onTrim;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chs = profile.channels.where((c) => c.enabled).toList();
    return Material(
      color: t.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.xs, Gap.s),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(tr('Trim từng kênh', 'Trim per channel'), style: AppText.title.copyWith(color: t.text))),
            IconButton(
              tooltip: tr('Đóng', 'Close'),
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const AppIcon(AppIcons.close, mini: true),
            ),
          ]),
          if (chs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Gap.s),
              child: Text(tr('Chưa có kênh nào được bật', 'No channel is enabled'),
                  style: AppText.label.copyWith(color: t.textMuted)),
            )
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in chs) _row(t, c),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _row(AppTokens t, ChannelConfig c) {
    final canLeft = c.trimUs > -200, canRight = c.trimUs < 200;
    return Padding(
      key: ValueKey('trim-ch${c.index}'),
      padding: const EdgeInsets.only(right: Gap.s),
      child: Row(children: [
        Expanded(
          child: Text(profile.chLabel(c.index),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: t.text)),
        ),
        HoldRepeat(
          onStep: canLeft ? (_) => onTrim(c.index, -5) : null,
          child: OutlinedButton(
            onPressed: canLeft ? () => onTrim(c.index, -5) : null,
            style: OutlinedButton.styleFrom(minimumSize: const Size(40, 36), padding: EdgeInsets.zero),
            child: const Text('◀'),
          ),
        ),
        SizedBox(
          width: 76,
          child: Tooltip(
            message: tr('Bấm để về 0', 'Tap to reset to 0'),
            child: InkWell(
              onTap: c.trimUs == 0 ? null : () => onTrim(c.index, 0, set: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Text('${c.trimUs > 0 ? '+' : ''}${c.trimUs} µs',
                    textAlign: TextAlign.center,
                    style: AppText.metric.copyWith(color: c.trimUs == 0 ? t.textMuted : t.text, fontSize: 14)),
              ),
            ),
          ),
        ),
        HoldRepeat(
          onStep: canRight ? (_) => onTrim(c.index, 5) : null,
          child: OutlinedButton(
            onPressed: canRight ? () => onTrim(c.index, 5) : null,
            style: OutlinedButton.styleFrom(minimumSize: const Size(40, 36), padding: EdgeInsets.zero),
            child: const Text('▶'),
          ),
        ),
      ]),
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
    if (mixer?.isActive(r.id) == true)
      return (t.accent, tr('Điều kiện đúng · đang tác động', 'Condition met · active'));
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: arm,
      builder: (context, _) {
        // Không dùng ARM: không hiện ô trạng thái lái
        if (!arm.enabled) return const SizedBox.shrink();
        final armed = arm.armed;
        final ready = arm.state == ArmState.ready;
        final color = armed ? t.onAccentFill : (ready ? t.text : t.disabled);
        final button = GestureDetector(
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
        return Padding(padding: const EdgeInsets.only(right: Gap.s), child: button);
      },
    );
  }
}
