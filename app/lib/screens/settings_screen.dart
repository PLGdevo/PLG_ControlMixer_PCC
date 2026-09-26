// Màn Cấu hình: làm việc trên hồ sơ xe, luôn mở được kể cả khi chưa nối xe (E4).
// Tab: Input · Mix · Kênh · Chung (Sprint 4 — U1) · Bố cục. Kênh Ga / Lái do người dùng chọn ở tab Chung, có thể không có.
// Tab Bố cục xem trước màn Lái và mở thẳng chế độ Sửa bố cục.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/condition.dart';
import '../models/control_layout.dart';
import '../models/input_def.dart';
import '../models/mixer_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/channel_tile.dart';
import '../widgets/condition_builder.dart';
import '../widgets/layout_preview.dart';
import '../widgets/mix_rule_card.dart';
import '../widgets/number_field.dart';
import 'channel_detail_screen.dart';
import 'control_screen.dart';
import 'input_screen.dart';
import 'mix_rule_screen.dart';
import 'network_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.repo,
    required this.profileId,
    this.initialTab = 0,
    this.fromDrive = false,
  });

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;
  final int initialTab;

  /// Mở từ màn Lái: Sửa bố cục đóng màn này, trả về [editLayoutResult] để màn Lái vào chế độ sửa
  final bool fromDrive;

  static const mixTab = 1;
  static const generalTab = 3;
  static const layoutTab = 4;
  static const editLayoutResult = 'editLayout';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 5, vsync: this, initialIndex: widget.initialTab);
  late CarProfile draft;
  late String _savedJson;
  late String _savedKey;
  bool busy = false;

  late final _name = TextEditingController(text: draft.name);
  late final _ip = TextEditingController(text: draft.wifi?.ip ?? '192.168.4.1');
  late final _port = TextEditingController(text: '${draft.wifi?.port ?? 4210}');
  late final _ssid = TextEditingController(text: draft.wifi?.ssid ?? '');
  late final _mac = TextEditingController(text: draft.ble?.mac ?? '');
  late final _devName = TextEditingController(text: draft.ble?.deviceName ?? '');

  CarController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    draft = widget.repo.get(widget.profileId)!;
    draft.wifi ??= WifiConn();
    draft.ble ??= BleConn();
    _markSaved();
    // Màn cấu hình luôn đứng dọc, kể cả khi mở từ màn Lái (đang khoá ngang)
    _portrait();
  }

  // Không khôi phục hướng trong dispose: màn nào mở màn này thì tự đặt lại sau khi push trả về.

  @override
  void dispose() {
    for (final t in [_name, _ip, _port, _ssid, _mac, _devName]) {
      t.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  /// Hướng màn hình của màn này (đặt lại sau khi màn khác đổi hướng)
  static void _portrait() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _markSaved() {
    _savedJson = jsonEncode(draft.toJson()..remove('updatedAt'));
    _savedKey = widget.repo.get(widget.profileId)?.connKey ?? draft.connKey;
  }

  bool get _dirty => jsonEncode(draft.toJson()..remove('updatedAt')) != _savedJson;

  /// Đang nối đúng xe của hồ sơ này
  bool get _connectedHere => c.isConnected && c.connectedKey == _savedKey;

  List<String> get _errors => draft.validateAll(otherNames: widget.repo.namesExcept(draft.id));

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------------- Nút dưới (E4) ----------------
  Future<void> _save() => _run(() async {
        await widget.repo.save(draft);
        _markSaved();
        // Xét sau khi lưu: đổi IP/port thì hồ sơ không còn khớp xe đang nối, không ghi nhầm xe
        if (!_connectedHere) {
          _snack(tr('Đã lưu vào máy', 'Saved to this phone'));
          return;
        }
        // Cấu hình nằm trong app và có tác dụng ngay; chỉ phần xe cần giữ khi mất sóng mới ghi xuống xe
        try {
          final wrote = await c.syncProfile(draft);
          _snack(wrote ? tr('Đã lưu và đồng bộ failsafe với xe', 'Saved and synced failsafe with the car') : tr('Đã lưu, có tác dụng ngay', 'Saved, takes effect now'));
        } catch (e) {
          _snack(tr('Đã lưu vào máy, nhưng không đồng bộ được failsafe: ${e.toString().replaceFirst('Exception: ', '')}', 'Saved to this phone, but could not sync failsafe: ${e.toString().replaceFirst('Exception: ', '')}'));
        }
      });

  /// Gửi lại failsafe xuống xe (dùng khi muốn chắc chắn, E4)
  Future<void> _syncFailsafe() => _run(() async {
        await c.syncProfile(widget.repo.get(widget.profileId)!, force: true);
        _snack(tr('Đã đồng bộ failsafe với xe', 'Failsafe synced with the car'));
      });

  Future<void> _reset() async {
    final ok = await _confirm(
        tr('Khôi phục mặc định?', 'Restore defaults?'),
        tr(
            'Kênh, luật mix, hộp số, failsafe và ARM về mặc định (chỉ giữ luật vào kênh Ga/Lái đã chọn). '
                'Tên, kết nối, Input, bố cục và việc chọn kênh Ga/Lái được giữ lại. Chỉ ghi vào máy khi bấm Lưu.',
            'Channels, mix rules, gears, failsafe and ARM go back to defaults (only rules into the chosen '
                'throttle/steering channels are kept). Name, connection, Inputs, layout and the throttle/steering '
                'choice are kept. Nothing is written until you tap Save.'),
        tr('Khôi phục', 'Restore'));
    if (ok) setState(() => draft.resetConfig());
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final leave = await _confirm(tr('Bỏ thay đổi?', 'Discard changes?'), tr('Các thay đổi chưa lưu sẽ bị mất.', 'Unsaved changes will be lost.'), tr('Bỏ', 'Discard'));
    if (leave && mounted) Navigator.pop(context);
  }

  // ---------------- Mạng của xe ----------------
  /// Màn Mạng của xe sửa thẳng phần kết nối của hồ sơ đã lưu (IP, port, mã xe) → nạp lại vào bản nháp
  Future<void> _openNetwork() async {
    String wifiJson() => jsonEncode(widget.repo.get(widget.profileId)?.wifi?.toJson());
    final before = wifiJson();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NetworkScreen(controller: c, repo: widget.repo, profileId: widget.profileId)),
    );
    final fresh = widget.repo.get(widget.profileId);
    if (!mounted || fresh == null || wifiJson() == before) return;
    final wasDirty = _dirty;
    setState(() {
      final w = draft.wifi = fresh.wifi ?? WifiConn();
      _ip.text = w.ip;
      _port.text = '${w.port}';
      _ssid.text = w.ssid ?? '';
      if (fresh.ble != null) draft.ble!.deviceName = _devName.text = fresh.ble!.deviceName;
      if (!wasDirty) _markSaved();
    });
  }

  // ---------------- Bố cục ----------------
  /// Mở chế độ Sửa bố cục của màn Lái. Màn đó ghi thẳng vào hồ sơ đã lưu (kể cả Input / luật tạo
  /// từ bảng thuộc tính) nên bản nháp phải được lưu trước, rồi nạp lại sau khi sửa xong.
  Future<void> _editLayout() async {
    if (_dirty) {
      final errors = _errors;
      if (errors.isNotEmpty) {
        _snack(tr('Sửa lỗi trước khi sửa bố cục: ${errors.first}', 'Fix this before editing the layout: ${errors.first}'));
        return;
      }
      final ok = await _confirm(
        tr('Lưu thay đổi?', 'Save changes?'),
        tr('Cấu hình đang sửa cần được lưu trước khi mở Sửa bố cục.',
            'Your changes need to be saved before opening the layout editor.'),
        tr('Lưu', 'Save'),
      );
      if (!ok) return;
      await _save();
      if (!mounted || _dirty) return;
    }
    if (widget.fromDrive) {
      Navigator.pop(context, SettingsScreen.editLayoutResult);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ControlScreen(controller: c, repo: widget.repo, profileId: widget.profileId, editOnly: true),
      ),
    );
    if (!mounted) return;
    _portrait();
    final fresh = widget.repo.get(widget.profileId);
    if (fresh == null) return;
    setState(() {
      fresh.wifi ??= WifiConn();
      fresh.ble ??= BleConn();
      draft = fresh;
      _markSaved();
    });
  }

  /// Nhãn phần tử trên bản xem trước: nhãn riêng, tên Input hoặc tên loại phần tử
  String _itemLabel(ControlItem it) {
    final custom = it.style.labelText;
    if (it.style.showLabel && custom != null && custom.trim().isNotEmpty) return custom;
    if (it.kind == ItemKind.gauge) return (GaugeKey.values.asNameMap()[it.gaugeKey] ?? GaugeKey.battery).label;
    return draft.input(it.inputId)?.name ?? it.kind.label;
  }

  // ---------------- Kênh ----------------
  Future<void> _openChannel(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ChannelDetailScreen(
          profile: draft,
          index: index,
          onOpenMix: () {
            Navigator.pop(ctx);
            _tabs.animateTo(SettingsScreen.mixTab);
          },
        ),
      ),
    );
    setState(() {});
  }

  void _toggleChannel(ChannelConfig ch, bool on) {
    if (!on && ch.alwaysOn) {
      _snack(tr('CH1/CH2 luôn bật: firmware xe hiện tại luôn xuất hai kênh này', 'CH1/CH2 are always on: the current car firmware always outputs these two channels'));
      return;
    }
    setState(() => ch.enabled = on);
    if (on && draft.rulesTo(ch.index).isEmpty) {
      _snack(tr('${ch.label} chưa có luật mix nào. Gắn một Input vào kênh ở Sửa bố cục hoặc thêm luật ở tab Mix.', '${ch.label} has no mix rule. Bind an Input to it in Edit layout or add a rule in the Mix tab.'));
    }
  }

  /// Tóm tắt nguồn của kênh cho tab Kênh
  String? _channelSource(int ch) {
    final rules = draft.rulesTo(ch);
    if (rules.isEmpty) return null;
    final names = {for (final r in rules) draft.input(r.source)?.name ?? r.source};
    return rules.length == 1 ? names.first : tr('${names.take(2).join(', ')} · ${rules.length} luật', '${names.take(2).join(', ')} · ${rules.length} rules');
  }

  // ---------------- Input ----------------
  Future<void> _editInput(InputDef? d) async {
    final isNew = d == null;
    if (isNew && draft.inputs.length >= InputDef.maxInputs) {
      _snack(tr('Tối đa ${InputDef.maxInputs} Input', 'At most ${InputDef.maxInputs} Inputs'));
      return;
    }
    final src = d ?? InputDef(id: InputDef.uniqueId('input', draft.inputs.map((i) => i.id)), name: 'Input ${draft.inputs.length + 1}');
    final used = isNew ? 0 : draft.rulesUsing(src.id).length;
    final res = await Navigator.push<InputDef>(
      context,
      MaterialPageRoute(
        builder: (_) => InputScreen(
          input: src,
          takenIds: {for (final i in draft.inputs) if (i.id != src.id) i.id},
          idLocked: used > 0,
          usedBy: used,
        ),
      ),
    );
    if (res == null) return;
    setState(() {
      if (isNew) {
        draft.inputs.add(res);
        return;
      }
      if (res.id != src.id) draft.renameInput(src.id, res.id);
      final i = draft.inputs.indexWhere((x) => x.id == res.id);
      draft.inputs[i] = res;
      // Kiểu mới không còn hợp với phần tử đang gắn → gỡ khỏi phần tử
      for (final l in draft.layouts) {
        for (final it in l.items) {
          if (it.inputIds.contains(res.id) && !res.accepts(it.kind)) l.unbindInput(res.id);
        }
      }
    });
  }

  Future<void> _deleteInput(InputDef d) async {
    final rules = draft.rulesUsing(d.id);
    final ok = await _confirm(
      tr('Xoá Input "${d.name}"?', 'Delete Input "${d.name}"?'),
      rules.isEmpty
          ? tr('Input được gỡ khỏi mọi phần tử trên màn Lái.', 'The Input is removed from every control on the drive screen.')
          : tr(
                  'Input được gỡ khỏi mọi phần tử trên màn Lái. ${rules.length} luật mix dùng Input này sẽ bị tắt:\n',
                  'The Input is removed from every control on the drive screen. ${rules.length} mix rule(s) using it will be turned off:\n') +
              rules.map((r) => '• ${r.describe(draft.inputMap, chName: draft.chLabel)}').join('\n'),
      tr('Xoá', 'Delete'),
    );
    if (ok) setState(() => draft.deleteInput(d.id));
  }

  // ---------------- Mix ----------------
  Future<void> _editMix(MixRule? rule, {int? destCh}) async {
    final isNew = rule == null;
    if (isNew && draft.mixer.length >= MixRule.maxRules) {
      _snack(tr('Tối đa ${MixRule.maxRules} luật mix', 'At most ${MixRule.maxRules} mix rules'));
      return;
    }
    final src = draft.inputs.where((i) => i.type != InputType.constant).firstOrNull ?? draft.inputs.firstOrNull;
    if (isNew && src == null) {
      _snack(tr('Chưa có Input nào. Thêm Input ở tab Input trước.', 'No Inputs yet. Add one in the Input tab first.'));
      return;
    }
    final work = isNew
        ? MixRule(id: InputDef.uniqueId(MixRule.newId(), draft.mixer.map((m) => m.id)), source: src!.id, destCh: destCh ?? 3)
        : rule.copy();
    final res = await Navigator.push<MixRule>(
      context,
      MaterialPageRoute(builder: (_) => MixRuleScreen(rule: work, profile: draft)),
    );
    setState(() {
      if (res == null) return;
      if (isNew) {
        draft.mixer.add(res);
      } else {
        draft.mixer[draft.mixer.indexWhere((m) => m.id == res.id)] = res;
      }
    });
  }

  Future<void> _deleteMix(MixRule rule) async {
    final ok = await _confirm(tr('Xoá luật mix?', 'Delete mix rule?'), rule.describe(draft.inputMap, chName: draft.chLabel), tr('Xoá', 'Delete'));
    if (ok) setState(() => draft.mixer.removeWhere((m) => m.id == rule.id));
  }

  /// Kéo đổi thứ tự trong nhóm kênh: hoán vị các vị trí của nhóm trong danh sách chung.
  /// `to` đã tính sau khi bỏ phần tử ở `from` (onReorderItem).
  void _reorderInGroup(List<MixRule> group, int from, int to) {
    final slots = [for (final r in group) draft.mixer.indexOf(r)]..sort();
    final moved = [...group];
    moved.insert(to, moved.removeAt(from));
    setState(() {
      for (var i = 0; i < slots.length; i++) {
        draft.mixer[slots[i]] = moved[i];
      }
    });
  }

  // ---------------- Giao diện ----------------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final errors = _errors;
        return PopScope(
          canPop: !_dirty,
          onPopInvokedWithResult: _onPop,
          child: Scaffold(
              appBar: AppBar(
                title: Text(draft.name.trim().isEmpty ? tr('Cấu hình', 'Car settings') : draft.name),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        const Tab(text: 'Input'),
                        const Tab(text: 'Mix'),
                        Tab(text: tr('Kênh', 'Channels')),
                        Tab(text: tr('Chung', 'General')),
                        Tab(text: tr('Bố cục', 'Layout')),
                      ],
                    ),
                  ),
                ),
              ),
              body: TabBarView(
                controller: _tabs,
                children: [
                  _inputsTab(),
                  _mixTab(),
                  _channelsTab(),
                  _generalTab(),
                  _layoutTab(),
                ],
              ),
              bottomNavigationBar: _bottomBar(errors),
            ),
        );
      },
    );
  }

  Widget _bottomBar(List<String> errors) {
    final t = context.tokens;
    final connected = _connectedHere;
    final valid = errors.isEmpty;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!valid)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: Row(children: [
                  AppIcon(AppIcons.warning, color: t.bad, mini: true),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(errors.first, style: AppText.label.copyWith(color: t.bad))),
                ]),
              )
            else if (!connected)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: Text(tr('Chưa kết nối xe: Lưu vào máy, failsafe sẽ tự đồng bộ khi nối xe.', 'Car not connected: saved to this phone, failsafe syncs automatically when you connect.'),
                    style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
              ),
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: valid && !busy ? _save : null,
                  icon: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const AppIcon(AppIcons.save, mini: true),
                  label: Text(tr('Lưu', 'Save')),
                ),
                Tooltip(
                  message: connected ? tr('Gửi lại failsafe đã lưu xuống xe', 'Resend the saved failsafe to the car') : tr('Cần kết nối xe', 'Connect the car first'),
                  child: OutlinedButton.icon(
                    onPressed: connected && !busy ? _syncFailsafe : null,
                    icon: const AppIcon(AppIcons.syncFailsafe, mini: true),
                    label: Text(tr('Đồng bộ failsafe', 'Sync failsafe')),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : _reset,
                  icon: const AppIcon(AppIcons.reset, mini: true),
                  label: Text(tr('Mặc định', 'Defaults')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Text(s, style: AppText.label.copyWith(color: context.tokens.textMuted, fontSize: 13)),
      );

  /// Chọn kênh làm Ga / Lái (hoặc không có), kèm cảnh báo nếu kênh đã chọn chưa có luật / phần tử
  Widget _rolePicker({required bool throttle}) {
    final t = context.tokens;
    final label = throttle ? tr('Ga', 'Throttle') : tr('Lái', 'Steering');
    final current = throttle ? draft.throttleCh : draft.steeringCh;
    final other = throttle ? draft.steeringCh : draft.throttleCh;
    final warn = draft.roleWarning(throttle: throttle);
    void pick(int? n) => setState(() {
          if (throttle) {
            draft.throttleCh = n;
          } else {
            draft.steeringCh = n;
          }
          if (n == null) return;
          final c = draft.ch(n)..enabled = true;
          if (c.hasDefaultName) c.name = label;
        });
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 0 = không có (DropdownButton coi giá trị null là chưa chọn)
        DropdownButtonFormField<int>(
          initialValue: current ?? 0,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Kênh $label', '$label channel')),
          items: [
            DropdownMenuItem(value: 0, child: Text(tr('Không có', 'None'))),
            for (var n = 1; n <= 10; n++)
              DropdownMenuItem(
                value: n,
                enabled: n != other,
                child: Text(
                  n == other
                      ? tr('${draft.chLabel(n)} (đang là kênh ${throttle ? 'Lái' : 'Ga'})',
                          '${draft.chLabel(n)} (is the ${throttle ? 'steering' : 'throttle'} channel)')
                      : draft.chLabel(n),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => pick(v == null || v == 0 ? null : v),
        ),
        if (warn != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.s),
            child: Row(children: [
              AppIcon(AppIcons.warning, color: t.warn, mini: true),
              const SizedBox(width: Gap.s),
              Expanded(child: Text(warn, style: AppText.label.copyWith(color: t.warn))),
            ]),
          ),
      ]),
    );
  }

  Widget _channelsTab() {
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _hint(tr(
            'Kênh đầu ra CH1–CH10 nhận giá trị từ luật mix. Bấm vào kênh để chỉnh Min/Center/Max, trim, '
                'đảo chiều và failsafe. Kênh tắt luôn ra failsafe. '
                'Lưu ý: firmware xe hiện tại mới nhận CH1 (chân lái) và CH2 (chân ga); 10 kênh cần firmware giao thức v2.',
            'Output channels CH1–CH10 get their values from mix rules. Tap a channel to set Min/Center/Max, trim, '
                'reverse and failsafe. A disabled channel always outputs failsafe. '
                'Note: the current car firmware only takes CH1 (steering pin) and CH2 (throttle pin); '
                '10 channels need protocol v2 firmware.')),
        for (final ch in draft.channels)
          ChannelTile(
            channel: ch,
            controlLabel: _channelSource(ch.index),
            onTap: () => _openChannel(ch.index),
            onEnabled: (v) => _toggleChannel(ch, v),
          ),
      ],
    );
  }

  Widget _inputsTab() {
    final t = context.tokens;
    final layout = draft.activeLayout;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(Gap.l),
          children: [
            _hint(tr(
                'Input là nguồn điều khiển: cần gạt, nút, công tắc, núm trên màn Lái, hoặc hằng số. '
                    'Gắn phần tử vào Input ở Sửa bố cục; luật mix quyết định Input đi vào kênh nào.',
                'An Input is a control source: a stick, button, switch or knob on the drive screen, or a constant. '
                    'Bind controls to Inputs in Edit layout; mix rules decide which channel each Input drives.')),
            for (final d in draft.inputs)
              Card(
                child: ListTile(
                  onTap: () => _editInput(d),
                  title: Text(d.name, style: AppText.title.copyWith(fontSize: 16, color: t.text)),
                  subtitle: Text(
                    [
                      d.id,
                      d.type == InputType.axis ? '${d.type.label} ${d.range.label}' : d.type.label,
                      if (d.type != InputType.constant)
                        switch (layout.itemForInput(d.id)) {
                          null => tr('chưa có trên màn Lái', 'not on the drive screen'),
                          final it => it.kind.label.toLowerCase(),
                        },
                      tr('${draft.rulesUsing(d.id).length} luật', '${draft.rulesUsing(d.id).length} rules'),
                    ].join(' · '),
                    style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
                  ),
                  trailing: IconButton(
                    tooltip: tr('Xoá', 'Delete'),
                    onPressed: () => _deleteInput(d),
                    icon: AppIcon(AppIcons.delete, color: t.textMuted),
                  ),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
        child: Row(children: [
          Expanded(
            child: Text('${draft.inputs.length}/${InputDef.maxInputs} Input',
                style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
          ),
          FilledButton.icon(
            onPressed: draft.inputs.length < InputDef.maxInputs ? () => _editInput(null) : null,
            icon: const AppIcon(AppIcons.plus, mini: true),
            label: Text(tr('Thêm Input', 'Add Input')),
          ),
        ]),
      ),
    ]);
  }

  Widget _mixTab() {
    final t = context.tokens;
    final errs = <String, String>{};
    final ids = draft.inputMap, condIds = {for (final c in draft.conditions) c.id};
    for (final r in draft.mixer) {
      final e = r.validate(ids, condIds);
      if (e != null) errs[r.id] = e;
    }
    // Nhóm theo kênh đích, trong nhóm xếp theo priority rồi thứ tự danh sách (U3)
    List<MixRule> group(int ch) {
      final g = draft.mixer.where((r) => r.destCh == ch).toList();
      final order = {for (var i = 0; i < draft.mixer.length; i++) draft.mixer[i].id: i};
      g.sort((a, b) => a.priority != b.priority ? a.priority.compareTo(b.priority) : order[a.id]!.compareTo(order[b.id]!));
      return g;
    }

    return Column(
      children: [
        Expanded(
          child: draft.mixer.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xl),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(AppIcons.mix, size: 40, color: t.textMuted),
                      const SizedBox(height: Gap.m),
                      Text(tr('Chưa có luật mix', 'No mix rules yet'), style: AppText.title.copyWith(color: t.text)),
                      const SizedBox(height: Gap.xs),
                      Text(tr('Ví dụ: Nút A bật thì Slider X → CH1, tắt thì Slider X → CH8.', 'Example: with Button A on, Slider X → CH1; with it off, Slider X → CH8.'),
                          textAlign: TextAlign.center, style: AppText.label.copyWith(color: t.textMuted)),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Gap.l),
                  children: [
                    for (var ch = 1; ch <= 10; ch++)
                      if (group(ch).isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: Gap.s, bottom: Gap.xs),
                          child: Row(children: [
                            Expanded(
                              child: Text(draft.chLabel(ch).toUpperCase(),
                                  style: AppText.caption.copyWith(color: draft.ch(ch).enabled ? t.textMuted : t.disabled)),
                            ),
                            TextButton(onPressed: () => _editMix(null, destCh: ch), child: Text(tr('+ Luật', '+ Rule'))),
                          ]),
                        ),
                        Builder(builder: (context) {
                          final g = group(ch);
                          return ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            onReorderItem: (from, to) => _reorderInGroup(g, from, to),
                            children: [
                              for (var i = 0; i < g.length; i++)
                                MixRuleCard(
                                  key: ValueKey(g[i].id),
                                  index: i,
                                  rule: g[i],
                                  profile: draft,
                                  error: errs[g[i].id],
                                  onEdit: () => _editMix(g[i]),
                                  onDelete: () => _deleteMix(g[i]),
                                  onEnabled: (v) => setState(() => g[i].enabled = v),
                                ),
                            ],
                          );
                        }),
                      ],
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
          child: Row(children: [
            Expanded(
              child: Text(
                  tr(
                      '${draft.mixer.length}/${MixRule.maxRules} luật · '
                          '${draft.mixer.where((m) => m.enabled).length} đang bật · priority cao chạy sau',
                      '${draft.mixer.length}/${MixRule.maxRules} rules · '
                          '${draft.mixer.where((m) => m.enabled).length} on · higher priority runs later'),
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
            ),
            FilledButton.icon(
              onPressed: draft.mixer.length < MixRule.maxRules ? () => _editMix(null) : null,
              icon: const AppIcon(AppIcons.plus, mini: true),
              label: Text(tr('Thêm luật', 'Add rule')),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _layoutTab() {
    final t = context.tokens;
    final l = draft.activeLayout;
    final controls = l.items.where((i) => i.kind.isControl).length;
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _hint(tr(
            'Bố cục là cách cần gạt, nút, công tắc và đồng hồ được xếp trên màn Lái (màn ngang). '
                'Sửa bố cục để kéo thả, đổi cỡ, thêm phần tử, gắn Input và chỉnh kiểu hiển thị của từng phần tử.',
            'The layout is how sticks, buttons, switches and gauges are arranged on the drive screen (landscape). '
                'Edit it to drag, resize, add controls, bind Inputs and style each control.')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : _editLayout,
            child: Padding(
              padding: const EdgeInsets.all(Gap.m),
              // Máy bảng / màn ngang: không để bản xem trước chiếm hết màn
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: LayoutPreview(layout: l, labelOf: _itemLabel),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          tr('${l.name} · ${l.items.length} phần tử, $controls điều khiển',
              '${l.name} · ${l.items.length} items, $controls controls'),
          style: AppText.label.copyWith(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: Gap.m),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : _editLayout,
            icon: const AppIcon(AppIcons.edit, mini: true),
            label: Text(tr('Sửa bố cục', 'Edit layout')),
          ),
        ),
        const Divider(height: 32),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: AppIcon(l.locked ? AppIcons.locked : AppIcons.unlocked),
          title: Text(tr('Khoá bố cục', 'Lock layout')),
          subtitle: Text(tr('Tắt mục Sửa bố cục trên màn Lái để không sửa nhầm khi đang lái. Ở đây vẫn sửa được.',
              'Disables Edit layout on the drive screen so it is not changed by accident. You can still edit it here.')),
          value: l.locked,
          onChanged: (v) => setState(() => l.locked = v),
        ),
      ],
    );
  }

  Widget _generalTab() {
    final g = draft.validateGeneral(otherNames: widget.repo.namesExcept(draft.id));
    final isWifi = draft.connType == ConnType.wifi;
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        TextField(
          controller: _name,
          maxLength: 32,
          decoration: InputDecoration(labelText: tr('Tên xe', 'Car name'), errorText: g['name']),
          onChanged: (v) => setState(() => draft.name = v),
        ),
        const SizedBox(height: Gap.s),
        SegmentedButton<ConnType>(
          segments: const [
            ButtonSegment(value: ConnType.wifi, label: Text('WiFi'), icon: AppIcon(AppIcons.wifi, mini: true)),
            ButtonSegment(
                value: ConnType.ble, label: Text('Bluetooth'), icon: CustomIconView(CustomIcon.bluetooth, size: 20)),
          ],
          selected: {draft.connType},
          onSelectionChanged: (s) => setState(() => draft.connType = s.first),
        ),
        const SizedBox(height: Gap.m),
        if (isWifi) ...[
          TextField(
            controller: _ip,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('Địa chỉ IP', 'IP address'),
              errorText: g['ip'] ?? g['carId'],
              helperText: draft.wifi!.carId == null ? null : tr('IP đổi thì app tự tìm xe ${draft.wifi!.carId} trong mạng', 'If the IP changes, the app finds car ${draft.wifi!.carId} on the network'),
            ),
            onChanged: (v) => setState(() => draft.wifi!.ip = v.trim()),
          ),
          const SizedBox(height: Gap.m),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Port UDP', 'UDP port'), errorText: g['port']),
            onChanged: (v) => setState(() => draft.wifi!.port = int.tryParse(v.trim()) ?? 0),
          ),
          const SizedBox(height: Gap.m),
          TextField(
            controller: _ssid,
            decoration: InputDecoration(labelText: tr('SSID (tuỳ chọn)', 'SSID (optional)')),
            onChanged: (v) => setState(() => draft.wifi!.ssid = v.trim().isEmpty ? null : v.trim()),
          ),
        ] else ...[
          TextField(
            controller: _mac,
            decoration: InputDecoration(labelText: 'MAC', hintText: 'AA:BB:CC:DD:EE:FF', errorText: g['ble']),
            onChanged: (v) => setState(() => draft.ble!.mac = v.trim().toUpperCase()),
          ),
          const SizedBox(height: Gap.m),
          TextField(
            controller: _devName,
            decoration: InputDecoration(labelText: tr('Tên thiết bị BLE', 'BLE device name')),
            onChanged: (v) => setState(() => draft.ble!.deviceName = v.trim()),
          ),
        ],
        const SizedBox(height: Gap.m),
        Card(
          child: ListTile(
            leading: const AppIcon(AppIcons.wifi),
            title: Text(tr('Mạng của xe', 'Car network')),
            subtitle: Text(_connectedHere
                ? tr('WiFi riêng / vào router, tên WiFi, mật khẩu, IP tĩnh/động, port', 'Own WiFi / router, WiFi name, password, static/dynamic IP, port')
                : tr('Cần kết nối xe: cấu hình mạng lưu trên xe', 'Connect the car first: network settings live on the car')),
            trailing: const AppIcon(AppIcons.chevronRight, mini: true),
            onTap: _openNetwork,
          ),
        ),
        const Divider(height: 32),
        NumberField(
          label: tr('Thời gian chờ failsafe', 'Failsafe timeout'),
          unit: ' ms',
          value: draft.failsafeTimeoutMs,
          min: 100,
          max: 3000,
          step: 50,
          error: g['failsafeTimeout'],
          onChanged: (v) => setState(() => draft.failsafeTimeoutMs = v),
        ),
        _hint(tr('Xe chuyển sang failsafe nếu không nhận lệnh trong khoảng thời gian này.', 'The car switches to failsafe if it gets no command within this time.')),
        const Divider(height: 32),
        Text(tr('Kênh Ga / Lái', 'Throttle / steering channels'), style: AppText.title.copyWith(color: context.tokens.text)),
        _hint(tr(
            'Kênh Ga chịu giới hạn của hộp số; muốn ARM hay sửa bố cục phải thả cần ga về vị trí nghỉ. '
                'Kênh Lái là kênh ô Trim trên màn Lái chỉnh. Chọn "Không có" nếu xe không cần. '
                'Min/Center/Max, trim và failsafe của kênh chỉnh ở tab Kênh.',
            'The throttle channel is limited by the gears; to ARM or edit the layout the throttle must be at rest. '
                'The steering channel is the one the Trim box on the drive screen adjusts. Choose "None" if the car '
                'does not need it. Min/Center/Max, trim and failsafe are set in the Channels tab.')),
        _rolePicker(throttle: true),
        _rolePicker(throttle: false),
        const Divider(height: 32),
        NumberField(
          label: tr('Số lượng số', 'Number of gears'),
          value: draft.gears.gearCount,
          min: 1,
          max: 5,
          error: g['gearCount'],
          onChanged: (v) => setState(() => draft.gears.gearCount = v),
        ),
        for (var i = 0; i < draft.gears.gearCount; i++)
          NumberField(
            label: tr('Ga tối đa số ${i + 1}', 'Max throttle in gear ${i + 1}'),
            unit: '%',
            value: draft.gears.maxThrottle[i],
            min: 1,
            max: 100,
            step: 5,
            error: g['gear$i'],
            onChanged: (v) => setState(() => draft.gears.maxThrottle[i] = v),
          ),
        _hint(draft.throttleCh == null
            ? tr('Chưa chọn kênh Ga (ở trên) nên hộp số chưa có tác dụng.', 'No throttle channel chosen (above), so the gears have no effect.')
            : tr('Hộp số giới hạn kênh Ga (${draft.chLabel(draft.throttleCh!)}).', 'The gears limit the throttle channel (${draft.chLabel(draft.throttleCh!)}).')),
        const Divider(height: 32),
        Text('ARM', style: AppText.title.copyWith(color: context.tokens.text)),
        _hint(tr('Vừa kết nối xe chưa nhận lệnh lái. Nhấn giữ nút ARM 1 giây trên màn Lái (có kênh Ga thì cần ga phải ở vị trí nghỉ).', 'Right after connecting, the car ignores drive commands. Hold the ARM button for 1 second on the drive screen (with a throttle channel, the throttle must be at rest).')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Tự ARM sau khi kết nối', 'Auto-ARM after connecting')),
          subtitle: Text(tr('Tự ARM một lần khi đủ điều kiện; DISARM rồi thì phải bấm lại',
              'ARMs once when conditions are met; after a DISARM you must ARM again')),
          value: draft.arm.autoArm,
          onChanged: (v) => setState(() => draft.arm.autoArm = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Điều kiện ARM riêng', 'Custom ARM condition')),
          subtitle: Text(tr('Chỉ ARM được khi điều kiện đúng; điều kiện sai thì tự DISARM',
              'ARM only while the condition is true; DISARMs when it turns false')),
          value: draft.arm.armCondition != null,
          onChanged: (v) => setState(() => draft.arm.armCondition = v ? const ExprTrue() : null),
        ),
        if (draft.arm.armCondition != null)
          ConditionBuilder(
            value: draft.arm.armCondition!,
            inputs: draft.inputs,
            named: draft.conditions,
            onChanged: (e) => setState(() => draft.arm.armCondition = e),
          ),
      ],
    );
  }
}
