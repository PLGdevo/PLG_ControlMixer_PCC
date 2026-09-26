// Màn Cấu hình: làm việc trên hồ sơ xe, luôn mở được kể cả khi chưa nối xe (E4).
// Tab: Ga · Lái · Input · Mix · Kênh · Chung (Sprint 4 — U1). Kênh Ga / Lái do người dùng chọn, có thể không có.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/condition.dart';
import '../models/input_def.dart';
import '../models/mixer_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/channel_tile.dart';
import '../widgets/condition_builder.dart';
import '../widgets/mix_rule_card.dart';
import '../widgets/number_field.dart';
import 'channel_detail_screen.dart';
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
  });

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;
  final int initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  static const mixTab = 3;
  late final _tabs = TabController(length: 6, vsync: this, initialIndex: widget.initialTab);
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
          _snack('Đã lưu vào máy');
          return;
        }
        // Cấu hình nằm trong app và có tác dụng ngay; chỉ phần xe cần giữ khi mất sóng mới ghi xuống xe
        try {
          final wrote = await c.syncProfile(draft);
          _snack(wrote ? 'Đã lưu và đồng bộ failsafe với xe' : 'Đã lưu, có tác dụng ngay');
        } catch (e) {
          _snack('Đã lưu vào máy, nhưng không đồng bộ được failsafe: ${e.toString().replaceFirst('Exception: ', '')}');
        }
      });

  /// Gửi lại failsafe xuống xe (dùng khi muốn chắc chắn, E4)
  Future<void> _syncFailsafe() => _run(() async {
        await c.syncProfile(widget.repo.get(widget.profileId)!, force: true);
        _snack('Đã đồng bộ failsafe với xe');
      });

  Future<void> _reset() async {
    final ok = await _confirm('Khôi phục mặc định?',
        'Kênh, luật mix, hộp số, failsafe và ARM về mặc định (chỉ giữ luật vào kênh Ga/Lái đã chọn). '
            'Tên, kết nối, Input, bố cục và việc chọn kênh Ga/Lái được giữ lại. Chỉ ghi vào máy khi bấm Lưu.',
        'Khôi phục');
    if (ok) setState(() => draft.resetConfig());
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final leave = await _confirm('Bỏ thay đổi?', 'Các thay đổi chưa lưu sẽ bị mất.', 'Bỏ');
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
            _tabs.animateTo(mixTab);
          },
        ),
      ),
    );
    setState(() {});
  }

  void _toggleChannel(ChannelConfig ch, bool on) {
    if (!on && ch.alwaysOn) {
      _snack('CH1/CH2 luôn bật: firmware xe hiện tại luôn xuất hai kênh này');
      return;
    }
    setState(() => ch.enabled = on);
    if (on && draft.rulesTo(ch.index).isEmpty) {
      _snack('${ch.label} chưa có luật mix nào. Gắn một Input vào kênh ở Sửa bố cục hoặc thêm luật ở tab Mix.');
    }
  }

  /// Tóm tắt nguồn của kênh cho tab Kênh
  String? _channelSource(int ch) {
    final rules = draft.rulesTo(ch);
    if (rules.isEmpty) return null;
    final names = {for (final r in rules) draft.input(r.source)?.name ?? r.source};
    return rules.length == 1 ? names.first : '${names.take(2).join(', ')} · ${rules.length} luật';
  }

  // ---------------- Input ----------------
  Future<void> _editInput(InputDef? d) async {
    final isNew = d == null;
    if (isNew && draft.inputs.length >= InputDef.maxInputs) {
      _snack('Tối đa ${InputDef.maxInputs} Input');
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
      'Xoá Input "${d.name}"?',
      rules.isEmpty
          ? 'Input được gỡ khỏi mọi phần tử trên màn Lái.'
          : 'Input được gỡ khỏi mọi phần tử trên màn Lái. ${rules.length} luật mix dùng Input này sẽ bị tắt:\n'
              '${rules.map((r) => '• ${r.describe(draft.inputMap, chName: draft.chLabel)}').join('\n')}',
      'Xoá',
    );
    if (ok) setState(() => draft.deleteInput(d.id));
  }

  // ---------------- Mix ----------------
  Future<void> _editMix(MixRule? rule, {int? destCh}) async {
    final isNew = rule == null;
    if (isNew && draft.mixer.length >= MixRule.maxRules) {
      _snack('Tối đa ${MixRule.maxRules} luật mix');
      return;
    }
    final src = draft.inputs.where((i) => i.type != InputType.constant).firstOrNull ?? draft.inputs.firstOrNull;
    if (isNew && src == null) {
      _snack('Chưa có Input nào. Thêm Input ở tab Input trước.');
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
    final ok = await _confirm('Xoá luật mix?', rule.describe(draft.inputMap, chName: draft.chLabel), 'Xoá');
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
                title: Text(draft.name.trim().isEmpty ? 'Cấu hình' : draft.name),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'Ga'),
                        Tab(text: 'Lái'),
                        Tab(text: 'Input'),
                        Tab(text: 'Mix'),
                        Tab(text: 'Kênh'),
                        Tab(text: 'Chung'),
                      ],
                    ),
                  ),
                ),
              ),
              body: TabBarView(
                controller: _tabs,
                children: [
                  _roleTab(throttle: true),
                  _roleTab(throttle: false),
                  _inputsTab(),
                  _mixTab(),
                  _channelsTab(),
                  _generalTab(),
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
                child: Text('Chưa kết nối xe: Lưu vào máy, failsafe sẽ tự đồng bộ khi nối xe.',
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
                  label: const Text('Lưu'),
                ),
                Tooltip(
                  message: connected ? 'Gửi lại failsafe đã lưu xuống xe' : 'Cần kết nối xe',
                  child: OutlinedButton.icon(
                    onPressed: connected && !busy ? _syncFailsafe : null,
                    icon: const AppIcon(AppIcons.syncFailsafe, mini: true),
                    label: const Text('Đồng bộ failsafe'),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : _reset,
                  icon: const AppIcon(AppIcons.reset, mini: true),
                  label: const Text('Mặc định'),
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

  /// Tab Ga / Lái: chọn kênh làm Ga / Lái (hoặc không có), rồi chỉnh servo của kênh đó
  Widget _roleTab({required bool throttle}) {
    final t = context.tokens;
    final label = throttle ? 'Ga' : 'Lái';
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
          if (c.name == 'Kênh $n') c.name = label;
        });
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _hint(throttle
            ? 'Kênh Ga chịu giới hạn của hộp số; muốn ARM hay sửa bố cục phải thả cần ga về vị trí nghỉ. '
                'Chọn "Không có" nếu xe không có kênh ga.'
            : 'Kênh Lái là kênh ô Trim trên màn Lái chỉnh. Chọn "Không có" nếu không cần trim nhanh.'),
        // 0 = không có (DropdownButton coi giá trị null là chưa chọn)
        DropdownButtonFormField<int>(
          initialValue: current ?? 0,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Kênh $label'),
          items: [
            const DropdownMenuItem(value: 0, child: Text('Không có')),
            for (var n = 1; n <= 10; n++)
              DropdownMenuItem(
                value: n,
                enabled: n != other,
                child: Text(
                  n == other ? '${draft.chLabel(n)} (đang là kênh ${throttle ? 'Lái' : 'Ga'})' : draft.chLabel(n),
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
        const SizedBox(height: Gap.m),
        if (current != null)
          ..._servoFields(
            draft.ch(current),
            throttle
                ? 'Center là điểm trung tính của ESC (xe đứng yên). Failsafe thường đặt bằng Center, '
                    'hoặc thấp hơn một chút nếu muốn xe phanh khi mất sóng.'
                : 'Offset bù độ lệch cơ khí khi lắp servo (chỉnh một lần). Trim tinh chỉnh để xe chạy thẳng. '
                    'Min/Max giới hạn góc lái để servo không bị kẹt.',
          ),
      ],
    );
  }

  List<Widget> _servoFields(ChannelConfig ch, String hint) {
    final err = ch.validate();
    void upd(VoidCallback f) => setState(f);
    return [
      _hint(hint),
      NumberField(label: 'Min', unit: ' µs', value: ch.minUs, min: 500, max: 2500, step: 10,
          error: err['min'], onChanged: (v) => upd(() => ch.minUs = v)),
      NumberField(label: 'Center', unit: ' µs', value: ch.centerUs, min: 500, max: 2500, step: 5,
          error: err['center'], onChanged: (v) => upd(() => ch.centerUs = v)),
      NumberField(label: 'Max', unit: ' µs', value: ch.maxUs, min: 500, max: 2500, step: 10,
          error: err['max'], onChanged: (v) => upd(() => ch.maxUs = v)),
      const Divider(),
      NumberField(label: 'Trim', unit: ' µs', value: ch.trimUs, min: -200, max: 200,
          error: err['trim'], onChanged: (v) => upd(() => ch.trimUs = v)),
      NumberField(label: 'Offset', unit: ' µs', value: ch.offsetUs, min: -300, max: 300,
          error: err['offset'], onChanged: (v) => upd(() => ch.offsetUs = v)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Đảo chiều (Reverse)'),
        value: ch.reverse,
        onChanged: (v) => upd(() => ch.reverse = v),
      ),
      const Divider(),
      NumberField(label: 'Failsafe', unit: ' µs', value: ch.failsafeUs, min: 500, max: 2500, step: 10,
          error: err['failsafe'], onChanged: (v) => upd(() => ch.failsafeUs = v)),
      const SizedBox(height: Gap.m),
      _hint('Tâm thực tế = Center + Trim + Offset = ${ch.effectiveCenter} µs\n'
          'Giữ lâu nút −/+ để đổi nhanh gấp 10 lần.'),
    ];
  }

  Widget _channelsTab() {
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _hint('Kênh đầu ra CH1–CH10 nhận giá trị từ luật mix. Bấm vào kênh để chỉnh Min/Center/Max, trim, '
            'đảo chiều và failsafe. Kênh tắt luôn ra failsafe. '
            'Lưu ý: firmware xe hiện tại mới nhận CH1 (chân lái) và CH2 (chân ga); 10 kênh cần firmware giao thức v2.'),
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
            _hint('Input là nguồn điều khiển: cần gạt, nút, công tắc, núm trên màn Lái, hoặc hằng số. '
                'Gắn phần tử vào Input ở Sửa bố cục; luật mix quyết định Input đi vào kênh nào.'),
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
                          null => 'chưa có trên màn Lái',
                          final it => it.kind.label.toLowerCase(),
                        },
                      '${draft.rulesUsing(d.id).length} luật',
                    ].join(' · '),
                    style: AppText.label.copyWith(color: t.textMuted, fontSize: 13),
                  ),
                  trailing: IconButton(
                    tooltip: 'Xoá',
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
            label: const Text('Thêm Input'),
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
                      Text('Chưa có luật mix', style: AppText.title.copyWith(color: t.text)),
                      const SizedBox(height: Gap.xs),
                      Text('Ví dụ: Nút A bật thì Slider X → CH1, tắt thì Slider X → CH8.',
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
                            TextButton(onPressed: () => _editMix(null, destCh: ch), child: const Text('+ Luật')),
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
                  '${draft.mixer.length}/${MixRule.maxRules} luật · '
                  '${draft.mixer.where((m) => m.enabled).length} đang bật · priority cao chạy sau',
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
            ),
            FilledButton.icon(
              onPressed: draft.mixer.length < MixRule.maxRules ? () => _editMix(null) : null,
              icon: const AppIcon(AppIcons.plus, mini: true),
              label: const Text('Thêm luật'),
            ),
          ]),
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
          decoration: InputDecoration(labelText: 'Tên xe', errorText: g['name']),
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
              labelText: 'Địa chỉ IP',
              errorText: g['ip'] ?? g['carId'],
              helperText: draft.wifi!.carId == null ? null : 'IP đổi thì app tự tìm xe ${draft.wifi!.carId} trong mạng',
            ),
            onChanged: (v) => setState(() => draft.wifi!.ip = v.trim()),
          ),
          const SizedBox(height: Gap.m),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Port UDP', errorText: g['port']),
            onChanged: (v) => setState(() => draft.wifi!.port = int.tryParse(v.trim()) ?? 0),
          ),
          const SizedBox(height: Gap.m),
          TextField(
            controller: _ssid,
            decoration: const InputDecoration(labelText: 'SSID (tuỳ chọn)'),
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
            decoration: const InputDecoration(labelText: 'Tên thiết bị BLE'),
            onChanged: (v) => setState(() => draft.ble!.deviceName = v.trim()),
          ),
        ],
        const SizedBox(height: Gap.m),
        Card(
          child: ListTile(
            leading: const AppIcon(AppIcons.wifi),
            title: const Text('Mạng của xe'),
            subtitle: Text(_connectedHere
                ? 'WiFi riêng / vào router, tên WiFi, mật khẩu, IP tĩnh/động, port'
                : 'Cần kết nối xe: cấu hình mạng lưu trên xe'),
            trailing: const AppIcon(AppIcons.chevronRight, mini: true),
            onTap: _openNetwork,
          ),
        ),
        const Divider(height: 32),
        NumberField(
          label: 'Thời gian chờ failsafe',
          unit: ' ms',
          value: draft.failsafeTimeoutMs,
          min: 100,
          max: 3000,
          step: 50,
          error: g['failsafeTimeout'],
          onChanged: (v) => setState(() => draft.failsafeTimeoutMs = v),
        ),
        _hint('Xe chuyển sang failsafe nếu không nhận lệnh trong khoảng thời gian này.'),
        const Divider(height: 32),
        NumberField(
          label: 'Số lượng số',
          value: draft.gears.gearCount,
          min: 1,
          max: 5,
          error: g['gearCount'],
          onChanged: (v) => setState(() => draft.gears.gearCount = v),
        ),
        for (var i = 0; i < draft.gears.gearCount; i++)
          NumberField(
            label: 'Ga tối đa số ${i + 1}',
            unit: '%',
            value: draft.gears.maxThrottle[i],
            min: 1,
            max: 100,
            step: 5,
            error: g['gear$i'],
            onChanged: (v) => setState(() => draft.gears.maxThrottle[i] = v),
          ),
        _hint(draft.throttleCh == null
            ? 'Chưa chọn kênh Ga (tab Ga) nên hộp số chưa có tác dụng.'
            : 'Hộp số giới hạn kênh Ga (${draft.chLabel(draft.throttleCh!)}).'),
        const Divider(height: 32),
        Text('ARM', style: AppText.title.copyWith(color: context.tokens.text)),
        _hint('Vừa kết nối xe chưa nhận lệnh lái. Nhấn giữ nút ARM 1 giây trên màn Lái (có kênh Ga thì cần ga phải ở vị trí nghỉ).'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tự ARM sau khi kết nối'),
          subtitle: const Text('Tự ARM một lần khi đủ điều kiện; DISARM rồi thì phải bấm lại'),
          value: draft.arm.autoArm,
          onChanged: (v) => setState(() => draft.arm.autoArm = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Điều kiện ARM riêng'),
          subtitle: const Text('Chỉ ARM được khi điều kiện đúng; điều kiện sai thì tự DISARM'),
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
