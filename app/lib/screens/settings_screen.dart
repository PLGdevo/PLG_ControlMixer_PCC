// Màn Cấu hình: làm việc trên hồ sơ xe, luôn mở được kể cả khi chưa nối xe (E4).
// Tab: Ga · Lái · Kênh · Mix · Chung.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../models/car_profile.dart';
import '../models/channel_config.dart';
import '../models/mix_rule.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/channel_tile.dart';
import '../widgets/mix_rule_card.dart';
import '../widgets/number_field.dart';
import 'channel_detail_screen.dart';
import 'mix_rule_screen.dart';

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

class _SettingsScreenState extends State<SettingsScreen> {
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
        'Kênh, mix, hộp số và failsafe của hồ sơ về mặc định. Tên, kết nối và bố cục được giữ lại. '
            'Chỉ ghi vào máy khi bấm Lưu.',
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

  // ---------------- Kênh ----------------
  Future<void> _openChannel(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChannelDetailScreen(profile: draft, index: index)),
    );
    setState(draft.syncLayouts);
  }

  void _toggleChannel(ChannelConfig ch, bool on) {
    if (!on && (ch.index == CarProfile.steeringCh || ch.index == CarProfile.throttleCh)) {
      _snack('Kênh Ga/Lái luôn bật');
      return;
    }
    setState(() {
      ch.enabled = on;
      draft.syncLayouts();
    });
    if (on && draft.controlOf(ch.index) == null) {
      _snack('${ch.label} chưa gán vào phần tử nào. Bấm vào kênh để chọn cần gạt / nút điều khiển.');
    }
  }

  // ---------------- Mix ----------------
  Future<void> _editMix(int? index) async {
    final isNew = index == null;
    if (isNew && draft.mixes.length >= MixRule.maxRules) {
      _snack('Tối đa ${MixRule.maxRules} luật mix');
      return;
    }
    final rule = isNew ? MixRule(id: MixRule.newId()) : draft.mixes[index].copy();
    final others = [...draft.mixes]..removeWhere((m) => m.id == rule.id);
    final res = await Navigator.push<MixRule>(
      context,
      MaterialPageRoute(builder: (_) => MixRuleScreen(rule: rule, others: others, channels: draft.channels)),
    );
    if (res == null) return;
    setState(() {
      if (isNew) {
        draft.mixes.add(res);
      } else {
        draft.mixes[index] = res;
      }
    });
  }

  Future<void> _deleteMix(int index) async {
    final ok = await _confirm('Xoá luật mix?', draft.mixes[index].describe(draft.channels), 'Xoá');
    if (ok) setState(() => draft.mixes.removeAt(index));
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
          child: DefaultTabController(
            length: 5,
            initialIndex: widget.initialTab,
            child: Scaffold(
              appBar: AppBar(
                title: Text(draft.name.trim().isEmpty ? 'Cấu hình' : draft.name),
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(52),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: 'Ga'),
                        Tab(text: 'Lái'),
                        Tab(text: 'Kênh'),
                        Tab(text: 'Mix'),
                        Tab(text: 'Chung'),
                      ],
                    ),
                  ),
                ),
              ),
              body: TabBarView(
                children: [
                  _servoTab(
                    draft.throttle,
                    'Center là điểm trung tính của ESC (xe đứng yên). Failsafe thường đặt bằng Center, '
                        'hoặc thấp hơn một chút nếu muốn xe phanh khi mất sóng. Hộp số áp lên kênh này.',
                  ),
                  _servoTab(
                    draft.steering,
                    'Offset bù độ lệch cơ khí khi lắp servo (chỉnh một lần). Trim tinh chỉnh để xe chạy thẳng. '
                        'Min/Max giới hạn góc lái để servo không bị kẹt.',
                  ),
                  _channelsTab(),
                  _mixTab(),
                  _generalTab(),
                ],
              ),
              bottomNavigationBar: _bottomBar(errors),
            ),
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

  // Tab Ga / Lái: giữ giao diện cũ, đọc/ghi channels[1] / channels[0] (B5)
  Widget _servoTab(ChannelConfig ch, String hint) {
    final err = ch.validate();
    void upd(VoidCallback f) => setState(f);
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
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
      ],
    );
  }

  Widget _channelsTab() {
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _hint('Tối đa 10 kênh. Bấm vào kênh để chỉnh chi tiết và gán vào một phần tử trên màn Lái '
            '(cần gạt, nút, công tắc, núm). Phần tử được thêm và cấu hình riêng ở Sửa bố cục. '
            'Lưu ý: firmware xe hiện tại mới nhận CH1 (Lái) và CH2 (Ga); 10 kênh cần firmware giao thức v2.'),
        for (final ch in draft.channels)
          ChannelTile(
            channel: ch,
            controlLabel: switch (draft.controlOf(ch.index)) {
              null => null,
              final it => controlSlotName(it, y: it.channelY == ch.index),
            },
            onTap: () => _openChannel(ch.index),
            onEnabled: (v) => _toggleChannel(ch, v),
          ),
      ],
    );
  }

  Widget _mixTab() {
    final t = context.tokens;
    return Column(
      children: [
        Expanded(
          child: draft.mixes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xl),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon(AppIcons.mix, size: 40, color: t.textMuted),
                      const SizedBox(height: Gap.m),
                      Text('Chưa có luật mix', style: AppText.title.copyWith(color: t.text)),
                      const SizedBox(height: Gap.xs),
                      Text('Ví dụ: CH1 ≥ 80% thì CH3 = 100%, CH1 < 70% thì CH3 = 0%.',
                          textAlign: TextAlign.center, style: AppText.label.copyWith(color: t.textMuted)),
                    ]),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(Gap.l),
                  buildDefaultDragHandles: false,
                  itemCount: draft.mixes.length,
                  onReorderItem: (from, to) => setState(() {
                    draft.mixes.insert(to, draft.mixes.removeAt(from));
                  }),
                  itemBuilder: (context, i) {
                    final m = draft.mixes[i];
                    return MixRuleCard(
                      key: ValueKey(m.id),
                      index: i,
                      rule: m,
                      channels: draft.channels,
                      onEdit: () => _editMix(i),
                      onDelete: () => _deleteMix(i),
                      onEnabled: (v) => setState(() => m.enabled = v),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.m),
          child: Row(children: [
            Expanded(
              child: Text(
                  '${draft.mixes.length}/${MixRule.maxRules} luật · '
                  '${draft.mixes.where((m) => m.enabled).length} đang bật · chạy từ trên xuống',
                  style: AppText.label.copyWith(color: t.textMuted, fontSize: 12)),
            ),
            FilledButton.icon(
              onPressed: draft.mixes.length < MixRule.maxRules ? () => _editMix(null) : null,
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
            decoration: InputDecoration(labelText: 'Địa chỉ IP', errorText: g['ip']),
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
      ],
    );
  }
}
