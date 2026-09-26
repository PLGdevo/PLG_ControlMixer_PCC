// Màn "Mạng của xe": đọc và đổi cấu hình mạng lưu trên xe — chế độ khi bật nguồn (AP / Router),
// WiFi riêng của xe, WiFi router (IP động/tĩnh), port UDP, tên thiết bị; vào chế độ cấu hình (WiFi tạm).
// Cấu hình mạng nằm trên xe vì xe cần nó lúc khởi động, nên chỉ đọc/sửa được khi đang nối xe.
// Đặc tả: dac_ta_wifi_3_che_do.md
import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller/car_controller.dart';
import '../data/profile_repository.dart';
import '../l10n/lang.dart';
import '../models/car_profile.dart';
import '../protocol/net_protocol.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/status_badge.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, required this.controller, required this.repo, required this.profileId});

  final CarController controller;
  final ProfileRepository repo;
  final String profileId;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  NetStatus? status;
  NetConfig? saved; // như đọc từ xe
  NetConfig? cfg; // bản đang sửa
  String? loadError;
  bool busy = false;
  bool showApPass = false, showStaPass = false;
  late final String _key;

  final _name = TextEditingController();
  final _port = TextEditingController();
  final _apSsid = TextEditingController();
  final _apPass = TextEditingController();
  final _apIp = TextEditingController();
  final _staSsid = TextEditingController();
  final _staPass = TextEditingController();
  final _staIp = TextEditingController();
  final _staGateway = TextEditingController();
  final _staSubnet = TextEditingController();
  final _staDns = TextEditingController();

  List<TextEditingController> get _fields =>
      [_name, _port, _apSsid, _apPass, _apIp, _staSsid, _staPass, _staIp, _staGateway, _staSubnet, _staDns];

  CarController get c => widget.controller;

  /// Đang nối đúng xe của hồ sơ này
  bool get _connected => c.isConnected && c.connectedKey == _key;

  bool get _dirty => cfg != null && saved != null && cfg!.signature != saved!.signature;

  @override
  void initState() {
    super.initState();
    _key = widget.repo.get(widget.profileId)?.connKey ?? '';
    if (_connected) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final t in _fields) {
      t.dispose();
    }
    super.dispose();
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- Đọc ----------------
  Future<void> _load() async {
    setState(() {
      busy = true;
      loadError = null;
    });
    NetStatus? st;
    try {
      st = await c.readNetStatus();
      final cf = await c.readNetConfig();
      if (!mounted) return;
      setState(() {
        status = st;
        saved = cf;
        cfg = cf.copy();
        showApPass = showStaPass = false;
        _fill(cf);
      });
    } catch (e) {
      if (mounted) setState(() => loadError = _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    final id = st?.id;
    if (id != null) await _patchProfile((w, p) => w.carId = id); // để app tự dò xe khi IP đổi
  }

  void _fill(NetConfig cf) {
    _name.text = cf.name;
    _port.text = '${cf.udpPort}';
    _apSsid.text = cf.apSsid;
    _apPass.clear();
    _apIp.text = cf.apIp;
    _staSsid.text = cf.staSsid;
    _staPass.clear();
    _staIp.text = cf.staIp;
    _staGateway.text = cf.staGateway;
    _staSubnet.text = cf.staSubnet;
    _staDns.text = cf.staDns;
  }

  /// Sửa phần kết nối WiFi của hồ sơ đã lưu (màn Cấu hình tự nạp lại khi quay về)
  Future<void> _patchProfile(void Function(WifiConn w, CarProfile p) edit) async {
    final fresh = widget.repo.get(widget.profileId);
    if (fresh == null) return;
    final before = jsonEncode(fresh.toJson());
    edit(fresh.wifi ??= WifiConn(), fresh);
    if (jsonEncode(fresh.toJson()) != before) await widget.repo.save(fresh, touch: false);
  }

  // ---------------- Lệnh ----------------
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

  Future<void> _info(String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đã hiểu', 'Got it')))],
        ),
      );

  /// Hướng dẫn nối lại sau khi xe khởi động lại với cấu hình `cf`
  String _nextSteps(NetConfig cf) {
    if (cf.bootMode == NetMode.ap) {
      return tr(
          'Xe phát WiFi "${cf.apSsid}". Nối điện thoại vào WiFi này rồi bấm Kết nối '
              '(IP ${cf.apIp}, port ${cf.udpPort}).',
          'The car broadcasts WiFi "${cf.apSsid}". Join this WiFi on the phone, then tap Connect '
              '(IP ${cf.apIp}, port ${cf.udpPort}).');
    }
    return tr(
        'Xe vào router "${cf.staSsid}". Nối điện thoại vào cùng router (băng 2.4 hay 5 GHz đều được) '
            'rồi bấm Kết nối, app tự tìm xe trong mạng${cf.staDhcp ? '' : ' (IP ${cf.staIp})'}.\n\n'
            'Nếu 15 giây không vào được router, xe tự phát lại WiFi "${cf.apSsid}" để bạn sửa.',
        'The car joins router "${cf.staSsid}". Connect the phone to the same router (2.4 or 5 GHz both work) '
            'and tap Connect; the app finds the car on the network${cf.staDhcp ? '' : ' (IP ${cf.staIp})'}.\n\n'
            'If it cannot join the router within 15 seconds, the car brings back WiFi "${cf.apSsid}" so you can fix it.');
  }

  Future<bool> _guard() async {
    if (c.arm.armed) {
      _snack(tr('DISARM trước khi đổi mạng của xe', 'DISARM before changing the car network'));
      return false;
    }
    return true;
  }

  Future<void> _apply() async {
    final cf = cfg!, old = saved!, st = status!;
    final errors = cf.validate();
    if (errors.isNotEmpty) {
      _snack(errors.values.first);
      return;
    }
    if (!await _guard()) return;
    final ok = await _confirm(
      tr('Lưu vào xe và khởi động lại?', 'Save to the car and restart?'),
      tr('Xe khởi động lại (khoảng 3 giây) và ngắt kết nối với app.\n\n${_nextSteps(cf)}', 'The car restarts (about 3 seconds) and disconnects from the app.\n\n${_nextSteps(cf)}'),
      tr('Lưu & khởi động lại', 'Save & restart'),
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await c.applyNetConfig(cf);
    } catch (e) {
      _snack(_msg(e));
      if (mounted) setState(() => busy = false);
      return;
    }
    await _patchProfile((w, p) {
      w
        ..carId = st.id
        ..port = cf.udpPort;
      if (cf.bootMode == NetMode.ap) {
        w
          ..ip = cf.apIp
          ..ssid = cf.apSsid;
      } else {
        if (!cf.staDhcp) w.ip = cf.staIp; // IP động: app dò theo mã xe khi kết nối
        w.ssid = cf.staSsid;
      }
      final b = p.ble;
      if (b != null && b.deviceName == old.name) b.deviceName = cf.name;
    });
    if (!mounted) return;
    await _info(tr('Đã lưu cấu hình mạng', 'Network settings saved'), _nextSteps(cf));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _enterSetup() async {
    final cf = saved!, st = status!;
    if (!await _guard()) return;
    final ok = await _confirm(
      tr('Vào chế độ cấu hình?', 'Enter setup mode?'),
      tr(
          'Xe khởi động lại và phát WiFi tạm "${st.setupSsid}" (mật khẩu giống WiFi riêng của xe), '
              'IP ${cf.apIp}. Ở chế độ này xe không nhận lệnh lái.\n\n'
              'Tự thoát sau 5 phút không có điện thoại nối. Cũng vào được bằng cách giữ nút BOOT trên xe 3 giây.',
          'The car restarts and broadcasts a temporary WiFi "${st.setupSsid}" (same password as the car WiFi), '
              'IP ${cf.apIp}. In this mode the car ignores drive commands.\n\n'
              'It exits after 5 minutes with no phone connected. You can also enter it by holding the BOOT button on the car for 3 seconds.'),
      tr('Khởi động lại', 'Restart'),
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await c.enterNetSetup();
    } catch (e) {
      _snack(_msg(e));
      if (mounted) setState(() => busy = false);
      return;
    }
    await _patchProfile((w, p) => w
      ..carId = st.id
      ..ip = cf.apIp
      ..port = cf.udpPort);
    if (!mounted) return;
    await _info(tr('Xe đang vào chế độ cấu hình', 'The car is entering setup mode'),
        tr('Nối điện thoại vào WiFi "${st.setupSsid}", rồi ở màn chính bấm Kết nối và mở lại Mạng của xe.', 'Join WiFi "${st.setupSsid}" on the phone, then tap Connect on the main screen and open Car network again.'));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    final st = status!;
    if (!await _guard()) return;
    final ok = await _confirm(
      tr('Khôi phục mạng mặc định?', 'Reset network to defaults?'),
      tr(
          'Xe quên WiFi router và về mặc định: phát WiFi "RC-CAR", mật khẩu 12345678, IP 192.168.4.1, port 4210. '
              'Xe khởi động lại và ngắt kết nối.',
          'The car forgets the router WiFi and goes back to defaults: WiFi "RC-CAR", password 12345678, '
              'IP 192.168.4.1, port 4210. The car restarts and disconnects.'),
      tr('Khôi phục', 'Reset'),
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await c.resetNetConfig();
    } catch (e) {
      _snack(_msg(e));
      if (mounted) setState(() => busy = false);
      return;
    }
    final d = NetConfig();
    await _patchProfile((w, p) => w
      ..carId = st.id
      ..ip = d.apIp
      ..port = d.udpPort
      ..ssid = d.apSsid);
    if (!mounted) return;
    await _info(tr('Đã khôi phục mạng mặc định', 'Network reset to defaults'), _nextSteps(d));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final leave = await _confirm(tr('Bỏ thay đổi?', 'Discard changes?'), tr('Các thay đổi chưa lưu vào xe sẽ bị mất.', 'Changes not yet saved to the car will be lost.'), tr('Bỏ', 'Discard'));
    if (leave && mounted) Navigator.pop(context);
  }

  // ---------------- Giao diện ----------------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final ready = _connected && cfg != null;
        return PopScope(
          canPop: !_dirty || !_connected,
          onPopInvokedWithResult: _onPop,
          child: Scaffold(
            appBar: AppBar(
              title: Text(tr('Mạng của xe', 'Car network')),
              actions: [
                if (_connected)
                  IconButton(
                    tooltip: tr('Đọc lại từ xe', 'Reload from the car'),
                    onPressed: busy ? null : _load,
                    icon: const AppIcon(AppIcons.refresh),
                  ),
                if (ready)
                  PopupMenuButton<String>(
                    icon: const AppIcon(AppIcons.more),
                    enabled: !busy,
                    onSelected: (v) => v == 'setup' ? _enterSetup() : _reset(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'setup',
                          child: ListTile(
                              leading: const AppIcon(AppIcons.wifi),
                              title: Text(tr('Chế độ cấu hình (WiFi tạm)', 'Setup mode (temporary WiFi)')))),
                      PopupMenuItem(
                          value: 'reset',
                          child: ListTile(
                              leading: const AppIcon(AppIcons.reset),
                              title: Text(tr('Khôi phục mạng mặc định', 'Reset network to defaults')))),
                    ],
                  ),
              ],
            ),
            body: !_connected
                ? _notConnected()
                : cfg == null
                    ? _loading()
                    : _form(),
            bottomNavigationBar: ready ? _bottomBar() : null,
          ),
        );
      },
    );
  }

  Widget _notConnected() {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(AppIcons.wifi, size: 48, color: t.textMuted),
          const SizedBox(height: Gap.l),
          Text(tr('Chưa kết nối xe', 'Car not connected'), style: AppText.headline.copyWith(color: t.text)),
          const SizedBox(height: Gap.s),
          Text(
            tr(
                'Cấu hình mạng lưu trên xe, không nằm trong hồ sơ. '
                    'Kết nối xe (WiFi hoặc Bluetooth) ở màn chính rồi mở lại màn này.',
                'Network settings are stored on the car, not in the profile. '
                    'Connect the car (WiFi or Bluetooth) on the main screen, then open this screen again.'),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: t.textBody),
          ),
        ]),
      ),
    );
  }

  Widget _loading() {
    final t = context.tokens;
    final err = loadError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: err == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(AppIcons.warning, size: 40, color: t.warn),
                const SizedBox(height: Gap.m),
                Text(tr('Không đọc được cấu hình mạng', 'Could not read the network settings'), style: AppText.title.copyWith(color: t.text)),
                const SizedBox(height: Gap.xs),
                Text(tr('$err\nFirmware trên xe cần bản có "Mạng của xe".', '$err\nThe car firmware needs a version with "Car network".'),
                    textAlign: TextAlign.center, style: AppText.label.copyWith(color: t.textMuted)),
                const SizedBox(height: Gap.l),
                FilledButton.icon(
                  onPressed: busy ? null : _load,
                  icon: const AppIcon(AppIcons.refresh, mini: true),
                  label: Text(tr('Thử lại', 'Retry')),
                ),
              ]),
      ),
    );
  }

  Widget _bottomBar() {
    final t = context.tokens;
    final errors = cfg!.validate();
    final setupMode = status?.mode == NetMode.setup;
    final canSave = errors.isEmpty && !busy && (_dirty || setupMode);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.line))),
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: Row(children: [
                  AppIcon(AppIcons.warning, color: t.bad, mini: true),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(errors.values.first, style: AppText.label.copyWith(color: t.bad))),
                ]),
              ),
            FilledButton.icon(
              onPressed: canSave ? _apply : null,
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const AppIcon(AppIcons.save, mini: true),
              label: Text(setupMode && !_dirty ? tr('Thoát chế độ cấu hình', 'Exit setup mode') : tr('Lưu vào xe & khởi động lại', 'Save to car & restart')),
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

  Widget _heading(String s) => Padding(
        padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
        child: Text(s, style: AppText.title.copyWith(color: context.tokens.text)),
      );

  Widget _field(
    TextEditingController ctrl,
    String label,
    String? error,
    ValueChanged<String> onChanged, {
    String? hint,
    String? helper,
    TextInputType? keyboard,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: TextField(
          controller: ctrl,
          enabled: enabled && !busy,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: !obscure,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            errorText: error,
            suffixIcon: suffix,
          ),
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      );

  Widget _eye(bool shown, VoidCallback toggle) => IconButton(
        tooltip: shown ? tr('Ẩn', 'Hide') : tr('Hiện', 'Show'),
        onPressed: toggle,
        icon: AppIcon(shown ? AppIcons.hideSecret : AppIcons.showSecret, mini: true),
      );

  static const _ipKeyboard = TextInputType.numberWithOptions(decimal: true);

  Widget _form() {
    final cf = cfg!;
    final e = cf.validate();
    final sta = cf.bootMode == NetMode.sta;
    final staOpen = cf.staPass == '';
    return ListView(
      padding: const EdgeInsets.all(Gap.l),
      children: [
        _statusCard(),
        _heading(tr('Khi bật nguồn', 'At power-on')),
        SegmentedButton<NetMode>(
          segments: [
            ButtonSegment(value: NetMode.ap, label: Text(tr('WiFi riêng (AP)', 'Own WiFi (AP)'))),
            ButtonSegment(value: NetMode.sta, label: Text(tr('Vào router nhà', 'Join home router'))),
          ],
          selected: {cf.bootMode},
          onSelectionChanged: busy ? null : (s) => setState(() => cf.bootMode = s.first),
        ),
        const SizedBox(height: Gap.s),
        _hint(sta
            ? tr(
                'Xe vào WiFi router (chỉ băng 2.4 GHz). Điện thoại vào cùng router, băng 2.4 hay 5 GHz đều được, '
                    'và vẫn có internet. Không vào được router sau 15 giây thì xe tự phát WiFi riêng.',
                'The car joins the router WiFi (2.4 GHz only). The phone joins the same router, 2.4 or 5 GHz, '
                    'and keeps internet. If the car cannot join within 15 seconds it starts its own WiFi.')
            : tr('Xe tự phát WiFi, điện thoại nối thẳng vào xe. Dùng ngoài trời, không cần router.',
                'The car broadcasts its own WiFi and the phone connects straight to it. For outdoors, no router needed.')),

        _heading(tr('Chung', 'General')),
        _field(_name, tr('Tên thiết bị', 'Device name'), e['name'], (v) => cf.name = v.trim(),
            helper: tr('Tên Bluetooth và tên của xe trong mạng router', 'Bluetooth name and the car name on the router network')),
        _field(_port, tr('Port UDP', 'UDP port'), e['udpPort'], (v) => cf.udpPort = int.tryParse(v.trim()) ?? 0,
            keyboard: TextInputType.number, helper: tr('Mặc định 4210. Port $discoveryPort dành cho tìm xe', 'Default 4210. Port $discoveryPort is reserved for car discovery')),

        _heading(tr('WiFi riêng của xe (AP)', 'Car WiFi (AP)')),
        _field(_apSsid, tr('Tên WiFi (SSID)', 'WiFi name (SSID)'), e['apSsid'], (v) => cf.apSsid = v),
        _field(
          _apPass,
          tr('Mật khẩu', 'Password'),
          e['apPass'],
          (v) => cf.apPass = v.isEmpty ? null : v,
          hint: tr('Để trống = giữ mật khẩu hiện tại', 'Leave empty to keep the current password'),
          helper: tr('8–63 ký tự. Cũng là mật khẩu WiFi tạm ở chế độ cấu hình', '8–63 characters. Also the temporary WiFi password in setup mode'),
          obscure: !showApPass,
          suffix: _eye(showApPass, () => setState(() => showApPass = !showApPass)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.m),
          child: DropdownButtonFormField<int>(
            key: ValueKey('ch-${saved!.signature}'), // đọc lại từ xe thì dựng lại với giá trị mới
            initialValue: cf.apChannel.clamp(1, 13).toInt(),
            decoration: InputDecoration(labelText: tr('Kênh WiFi', 'WiFi channel'), errorText: e['apChannel']),
            items: [for (var ch = 1; ch <= 13; ch++) DropdownMenuItem(value: ch, child: Text(tr('Kênh $ch', 'Channel $ch')))],
            onChanged: busy ? null : (v) => setState(() => cf.apChannel = v ?? 1),
          ),
        ),
        _field(_apIp, tr('IP của xe', 'Car IP'), e['apIp'], (v) => cf.apIp = v.trim(),
            keyboard: _ipKeyboard, helper: tr('IP tĩnh, mạng /24. Mặc định 192.168.4.1', 'Static IP, /24 network. Default 192.168.4.1')),

        _heading(tr('WiFi router', 'Router WiFi')),
        _hint(tr('Xe chỉ dùng được WiFi 2.4 GHz. Nếu router đặt tên riêng cho hai băng, chọn tên 2.4 GHz.', 'The car only supports 2.4 GHz WiFi. If the router names the two bands separately, pick the 2.4 GHz one.')),
        _field(_staSsid, tr('Tên WiFi router (SSID)', 'Router WiFi name (SSID)'), e['staSsid'], (v) => cf.staSsid = v),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(tr('Mạng không có mật khẩu', 'Network has no password')),
          value: staOpen,
          onChanged: busy
              ? null
              : (v) => setState(() {
                    cf.staPass = v == true ? '' : (_staPass.text.isEmpty ? null : _staPass.text);
                  }),
        ),
        _field(
          _staPass,
          tr('Mật khẩu router', 'Router password'),
          e['staPass'],
          (v) => cf.staPass = v.isEmpty ? null : v,
          hint: cf.staHasPass ? tr('Để trống = giữ mật khẩu hiện tại', 'Leave empty to keep the current password') : null,
          enabled: !staOpen,
          obscure: !showStaPass,
          suffix: _eye(showStaPass, () => setState(() => showStaPass = !showStaPass)),
        ),
        Text(tr('Địa chỉ IP của xe trong mạng router', 'Car IP address on the router network'), style: AppText.label.copyWith(color: context.tokens.text)),
        const SizedBox(height: Gap.s),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(tr('Động (DHCP)', 'Dynamic (DHCP)'))),
            ButtonSegment(value: false, label: Text(tr('Tĩnh', 'Static'))),
          ],
          selected: {cf.staDhcp},
          onSelectionChanged: busy ? null : (s) => setState(() => cf.staDhcp = s.first),
        ),
        const SizedBox(height: Gap.s),
        if (cf.staDhcp)
          _hint(tr('Router tự cấp IP. App tự tìm xe trong mạng theo mã xe khi kết nối.', 'The router assigns the IP. The app finds the car on the network by its car ID when connecting.'))
        else ...[
          const SizedBox(height: Gap.s),
          _field(_staIp, tr('IP tĩnh', 'Static IP'), e['staIp'], (v) => cf.staIp = v.trim(), keyboard: _ipKeyboard, hint: '192.168.1.50'),
          _field(_staGateway, 'Gateway', e['staGateway'], (v) => cf.staGateway = v.trim(),
              keyboard: _ipKeyboard, hint: '192.168.1.1', helper: tr('Thường là IP của router', 'Usually the router IP')),
          _field(_staSubnet, 'Subnet mask', e['staSubnet'], (v) => cf.staSubnet = v.trim(),
              keyboard: _ipKeyboard, hint: '255.255.255.0'),
          _field(_staDns, tr('DNS (tuỳ chọn)', 'DNS (optional)'), e['staDns'], (v) => cf.staDns = v.trim(),
              keyboard: _ipKeyboard, helper: tr('Để trống = dùng gateway', 'Leave empty to use the gateway')),
          _hint(tr('Chọn IP nằm ngoài dải router tự cấp để không trùng máy khác.', 'Pick an IP outside the router DHCP range so it does not clash with other devices.')),
        ],
      ],
    );
  }

  Widget _statusCard() {
    final t = context.tokens;
    final st = status!;
    final cf = saved!;
    String two(int n) => n.toString().padLeft(2, '0');
    final lines = <String>[
      'IP ${st.ip} · port ${cf.udpPort}',
      if (st.mode == NetMode.sta) 'Router "${cf.staSsid}"${st.rssi != 0 ? tr(' · sóng ${st.rssi} dBm', ' · signal ${st.rssi} dBm') : ''}',
      if (st.mode == NetMode.ap) tr('Phát WiFi "${cf.apSsid}" · ${st.clients} máy đang nối', 'Broadcasting WiFi "${cf.apSsid}" · ${st.clients} device(s) connected'),
      if (st.mode == NetMode.setup)
        tr('Phát WiFi tạm "${st.setupSsid}" · tự thoát sau ${st.setupLeftS ~/ 60}:${two(st.setupLeftS % 60)} nếu không có máy nối', 'Temporary WiFi "${st.setupSsid}" · exits in ${st.setupLeftS ~/ 60}:${two(st.setupLeftS % 60)} if no device connects'),
      if (st.mode != NetMode.sta && cf.staSsid.isNotEmpty && st.staResult != StaResult.none)
        'Router "${cf.staSsid}": ${st.staResult.label}',
      tr('Mã xe ${st.id}', 'Car ID ${st.id}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: Gap.s, runSpacing: Gap.xs, children: [
              Pill(color: st.mode == NetMode.setup ? t.warn : t.ok, label: tr('Đang chạy: ${st.mode.label}', 'Running: ${st.mode.label}')),
              if (st.fellBack) Pill(color: t.bad, label: tr('Không vào được router: ${st.staResult.label}', 'Could not join router: ${st.staResult.label}')),
            ]),
            const SizedBox(height: Gap.s),
            for (final l in lines) Text(l, style: AppText.label.copyWith(color: t.textBody)),
            if (st.fellBack) ...[
              const SizedBox(height: Gap.s),
              Text(tr('Xe đang phát WiFi riêng để bạn sửa thông tin router bên dưới.', 'The car is broadcasting its own WiFi so you can fix the router details below.'),
                  style: AppText.label.copyWith(color: t.bad, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
